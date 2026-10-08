// سيرفر HTTP محلي يقدّم البلاطات لـMapLibre من ملف MBTiles.
//
// ليش هذي الطبقة: MapLibre ما يقرأ MBTiles ولا SQLite — يبي مصدراً بـURL.
// والبديلان كانا أسوأ: تطبيق مواصفة PMTiles الثنائية بيدي (مخاطرة في كود
// لا أقدر أختبره إلا بالتجربة الكاملة)، أو خدمة بلاطات على الشبكة (يقتل
// الأوفلاين وهو سبب وجود التطبيق).
//
// السيرفر على 127.0.0.1 ومنفذ عشوائي، ويموت مع التطبيق.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show FlutterError;
import 'package:flutter/services.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:sqflite/sqflite.dart';

import '../config.dart';
import 'packs.dart';

/// علامة gzip في أول بايتين. Planetiler يضغط البلاطات، لكن منتجي MBTiles
/// الآخرين لا كلهم — نفحص البايتين بدل ما نفترض، لأن ترويسة
/// Content-Encoding خاطئة تعطي خريطة فارغة بلا أي رسالة خطأ.
bool _isGzip(Uint8List b) =>
    b.length > 2 && b[0] == 0x1f && b[1] == 0x8b;

class TileServer {
  HttpServer? _server;
  final Map<String, Database> _dbs = {};
  String _styleJson = '';

  /// عنوان السيرفر بعد التشغيل، مثل http://127.0.0.1:53812
  String get base {
    final s = _server;
    if (s == null) {
      throw StateError('سيرفر البلاطات ما اشتغل — نادِ start() أولاً');
    }
    return 'http://127.0.0.1:${s.port}';
  }

  String get styleUrl => '$base/style.json';

  Future<void> start(List<Pack> packs) async {
    for (final p in packs) {
      if (!p.tiles.existsSync()) continue;
      _dbs[p.name] = await openDatabase(p.tiles.path, readOnly: true);
    }
    if (_dbs.isEmpty) {
      throw StateError('ما في حزمة بلاطات على الجهاز');
    }

    _server = await shelf_io.serve(
      _handler,
      InternetAddress.loopbackIPv4,
      Cfg.tileServerPort,
    );

    await _loadStyle();
  }

  /// يقرأ النمط من الأصول ويزرع فيه عنوان السيرفر.
  ///
  /// النمط يحمل العلامة {{TILE_BASE}} لأن المنفذ عشوائي ولا يُعرف إلا بعد
  /// التشغيل — عنوان مكتوب في النمط يعني منفذاً ثابتاً، والثابت يتضارب.
  Future<void> _loadStyle() async {
    final raw = await rootBundle.loadString('assets/style/darb-day.json');
    _styleJson = raw.replaceAll('{{TILE_BASE}}', base);
  }

  static const _cors = {'access-control-allow-origin': '*'};

  static final _tileRe = RegExp(r'^tiles/(\d+)/(\d+)/(\d+)\.pbf$');
  static final _fontRe = RegExp(r'^fonts/([^/]+)/([\d-]+)\.pbf$');

  Future<Response> _handler(Request req) async {
    final path = req.url.path;

    if (path == 'style.json') {
      return Response.ok(_styleJson, headers: {
        'content-type': 'application/json; charset=utf-8',
        ..._cors,
      });
    }

    final font = _fontRe.firstMatch(path);
    if (font != null) return _serveFont(font.group(1)!, font.group(2)!);

    final tile = _tileRe.firstMatch(path);
    if (tile != null) {
      return _serveTile(
        int.parse(tile.group(1)!),
        int.parse(tile.group(2)!),
        int.parse(tile.group(3)!),
      );
    }

    return Response.notFound('غير معروف');
  }

  /// يقدّم glyph من أصول التطبيق.
  ///
  /// MapLibre يطلب نطاقات ما نشحنها (مثل الكوري) لأن النمط ما يحدّد
  /// نطاقاً — يطلب حسب المحارف الموجودة في البلاطة. فالناقص 404 عادي
  /// لا خطأ، وMapLibre يتعامل معه بسقوط صامت على محرف بديل.
  Future<Response> _serveFont(String stack, String range) async {
    try {
      final data = await rootBundle.load('assets/fonts/$stack/$range.pbf');
      return Response.ok(
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
        headers: {
          'content-type': 'application/x-protobuf',
          'cache-control': 'public, max-age=604800',
          ..._cors,
        },
      );
    } on FlutterError {
      return Response.notFound('نطاق غير مشحون: $stack/$range');
    }
  }

  /// يقدّم بلاطة من أول حزمة تحتويها.
  ///
  /// البحث في كل الحِزَم لا في حزمة باسمها: هكذا يصير تنزيل محافظة جديدة
  /// شفافاً للنمط — ما نحتاج نعيد بناء النمط ولا نضيف مصدراً لكل حزمة،
  /// والمصادر المتعددة في MapLibre تعني طلبات مضاعفة لكل بلاطة.
  Future<Response> _serveTile(int z, int x, int y) async {
    for (final db in _dbs.values) {
      final data = await _readTile(db, z, x, y);
      if (data == null) continue;

      final headers = <String, String>{
        'content-type': 'application/x-protobuf',
        // البلاطات لا تتغيّر إلا بتحديث الحزمة — نسمح لـMapLibre بكاشها
        'cache-control': 'public, max-age=86400',
        ..._cors,
      };
      if (_isGzip(data)) headers['content-encoding'] = 'gzip';
      return Response.ok(data, headers: headers);
    }

    // 204 لا 404 للبلاطة الناقصة: MapLibre يعدّ 404 خطأ شبكة ويعيد الطلب
    // مراراً، و204 يعني «لا شيء هنا» فيكفّ. فرق محسوس على أطراف الحزمة
    return Response(204, headers: _cors);
  }

  Future<Uint8List?> _readTile(Database db, int z, int x, int y) async {
    // MBTiles يخزّن الصفوف بنظام TMS (الأصل أسفل اليسار) وMapLibre يطلب
    // XYZ (الأصل أعلى اليسار) — بلا القلب تظهر الخريطة مقلوبة رأسياً،
    // وهو خطأ يصعب تشخيصه لأن الخريطة «تشتغل»
    final tmsY = (1 << z) - 1 - y;

    // `tiles` قد تكون جدولاً أو view: Planetiler يبني للمجموعات الكبيرة
    // tiles_shallow + tiles_data مع tiles كـview، يزيل بها تكرار البلاطات
    // المتطابقة (وهي كثيرة في صحراء العراق). حزمة بغداد الصغيرة جاءت
    // جدولاً عادياً. نقرأ من tiles فنشتغل على الاثنين، وقِسنا الخطة على
    // حزمة العراق: بحث بالمفتاح الأساسي، 0.06ms للبلاطة
    final rows = await db.rawQuery(
      'SELECT tile_data FROM tiles WHERE zoom_level = ? AND tile_column = ? '
      'AND tile_row = ? LIMIT 1',
      [z, x, tmsY],
    );
    if (rows.isEmpty) return null;
    return rows.first['tile_data'] as Uint8List?;
  }

  /// التغطية الفعلية للحزمة: (minLon, minLat, maxLon, maxLat).
  ///
  /// نحسبها من جدول البلاطات لا من metadata.bounds. السبب صادفناه فعلاً:
  /// عيّنة بغداد مقلّمة من ملف العراق ورثت ترويسته، فقال metadata إن
  /// التغطية العراق كامل وهي بغداد وحدها. الجدول لا يكذب.
  Future<List<double>?> packCoverage(String pack) async {
    final db = _dbs[pack];
    if (db == null) return null;

    final z = await db.rawQuery(
        'SELECT MAX(zoom_level) AS z FROM tiles');
    final maxZoom = z.first['z'] as int?;
    if (maxZoom == null) return null;

    final r = await db.rawQuery(
      'SELECT MIN(tile_column) AS x0, MAX(tile_column) AS x1, '
      'MIN(tile_row) AS y0, MAX(tile_row) AS y1 '
      'FROM tiles WHERE zoom_level = ?',
      [maxZoom],
    );
    final row = r.first;
    final n = 1 << maxZoom;

    double lonOf(int x) => x / n * 360.0 - 180.0;
    // عكس إسقاط ويب-مركاتور. tile_row بنظام TMS فنقلبه قبل الحساب
    double latOf(int tmsY) {
      final y = n - 1 - tmsY;
      final t = math.pi * (1 - 2 * y / n);
      return math.atan((math.exp(t) - math.exp(-t)) / 2) * 180.0 / math.pi;
    }

    final x0 = row['x0'] as int, x1 = row['x1'] as int;
    final y0 = row['y0'] as int, y1 = row['y1'] as int;

    return [
      lonOf(x0),
      math.min(latOf(y0), latOf(y1 + 1)),
      lonOf(x1 + 1),
      math.max(latOf(y0), latOf(y1 + 1)),
    ];
  }

  Future<Map<String, String>> packMetadata(String pack) async {
    final db = _dbs[pack];
    if (db == null) return {};
    final rows = await db.rawQuery('SELECT name, value FROM metadata');
    return {
      for (final r in rows) r['name'] as String: '${r['value']}',
    };
  }

  List<String> get loadedPacks => _dbs.keys.toList();

  /// النمط كنصّ — تحتاجه الشاشات التي تبني نمطاً معدّلاً (ليلي مثلاً).
  String get styleJson => _styleJson;

  Map<String, dynamic> get styleMap =>
      jsonDecode(_styleJson) as Map<String, dynamic>;

  Future<void> stop() async {
    for (final db in _dbs.values) {
      await db.close();
    }
    _dbs.clear();
    await _server?.close(force: true);
    _server = null;
  }
}
