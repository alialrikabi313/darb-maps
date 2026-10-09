// البحث المحلي في نقاط الاهتمام.
//
// محلي لا Nominatim: التطبيق يشتغل أوفلاين، وحدّ استخدام Nominatim طلب
// واحد بالثانية — يعني لا نقدر نبحث أثناء الكتابة أصلاً.
//
// قواعد تطبيع العربية تُقرأ من جدول search_meta في نفس القاعدة لا تُكتب
// هنا. السبب: البحث لازم يطبّع بنفس الطريقة التي فُهرست بها، ونسخة ثانية
// من القواعد في Dart تفترق عن بايثون بعد أول تعديل فتضيع النتائج بلا أي
// رسالة خطأ.

import 'dart:convert';
import 'dart:math' as math;

import 'package:maplibre_gl/maplibre_gl.dart';
import 'package:sqflite/sqflite.dart';

import '../config.dart';
import 'geo.dart';
import 'packs.dart';

class Place {
  final int id;
  final String? nameAr;
  final String? nameEn;
  final String category;
  final String? subtype;
  final LatLng pos;
  final int rank;
  final Map<String, dynamic> tags;

  /// مصدر النقطة: `osm` أو `overture:…` أو `osm-address` أو
  /// `osm-inferred`. نعرضه في بطاقة المكان لأن CDLA-Permissive-2.0
  /// تشترط الإسناد، ولأن المستخدم يستحق يعرف من أين جاءت المعلومة حين
  /// تكون خاطئة — وهو أهمّ في المستنتَج.
  final String source;

  /// المسافة من المستخدم بالأمتار — تُحسب وقت البحث لا تُخزَّن.
  final double? distanceM;

  const Place({
    required this.id,
    required this.nameAr,
    required this.nameEn,
    required this.category,
    required this.subtype,
    required this.pos,
    required this.rank,
    required this.tags,
    this.source = 'osm',
    this.distanceM,
  });

  /// اسم المصدر مقروءاً للعرض.
  String get sourceLabel => switch (source) {
        final s when s.startsWith('overture') => 'Overture Maps',
        'osm-address' => 'من عناوين المباني',
        'osm-inferred' => 'اسم مستنتَج — قد يكون غير دقيق',
        _ => 'OpenStreetMap',
      };

  /// الاسم مستنتَج لا مكتوب صراحةً في الخريطة.
  ///
  /// الواجهة تعلّمه، والأهمّ أنه **لا يُنطق أبداً**: التوجيه الصوتي يأخذ
  /// أسماء الشوارع من ڤالهالا مباشرة ولا يمسّ قاعدة البحث. اسم مستنتَج
  /// خاطئ يظهر في نتيجة بحث يصحّحه المستخدم بنظرة، ولو نُطق في مناورة
  /// لأضلّه.
  bool get isInferred => source == 'osm-inferred';

  String get title => nameAr ?? nameEn ?? 'بلا اسم';
  String? get subtitle => nameAr != null && nameEn != null ? nameEn : null;

  Place withDistance(double d) => Place(
        id: id, nameAr: nameAr, nameEn: nameEn, category: category,
        subtype: subtype, pos: pos, rank: rank, tags: tags,
        source: source, distanceM: d,
      );
}

/// تسميات عربية للتصنيفات. تُعرض تحت اسم النتيجة.
const Map<String, String> categoryLabels = {
  'place': 'منطقة',
  'street': 'شارع',
  'hospital': 'مستشفى',
  'pharmacy': 'صيدلية',
  'fuel': 'محطة وقود',
  'restaurant': 'مطعم',
  'mosque': 'جامع',
  'school': 'مدرسة',
  'university': 'جامعة',
  'bank': 'مصرف',
  'market': 'سوق',
  'government': 'دائرة حكومية',
  'transport': 'نقل',
  'hotel': 'فندق',
  'park': 'حديقة',
  'car_service': 'خدمة سيارات',
};

class PoiSearch {
  final List<Database> _dbs = [];

  // قواعد التطبيع كما خزّنها سكربت الاستخراج
  Map<String, String> _normMap = {};
  String _stripChars = '';
  RegExp? _stripRe;

  // البادئات (ال، مستشفى، شارع…) ما نحتاجها وقت البحث: سكربت الاستخراج
  // فهرس الاسم كاملاً وكلماته منزوعة البادئة معاً، ومطابقة البادئة في
  // FTS تمسكها. نقرأها من القاعدة ولا نخزّنها — وجودها هناك توثيق لما
  // فُهرس به، لا مدخل لحساب هنا

  // كل ما ليس حرفاً عربياً أو لاتينياً أو رقماً هو فاصل: OSM يستخدم «-»
  // و«/» و«،» بلا اتساق في نفس المدينة
  static final _sepRe = RegExp(r'[^؀-ۿ\w]+', unicode: true);

  Future<void> open(List<Pack> packs) async {
    for (final p in packs) {
      if (!p.pois.existsSync()) continue;
      final db = await openDatabase(p.pois.path, readOnly: true);
      _dbs.add(db);
      if (_normMap.isEmpty) await _loadMeta(db);
    }
    if (_dbs.isEmpty) {
      throw StateError('ما في قاعدة نقاط اهتمام على الجهاز');
    }
  }

  Future<void> _loadMeta(Database db) async {
    final rows = await db.rawQuery('SELECT key, value FROM search_meta');
    final meta = {for (final r in rows) r['key'] as String: '${r['value']}'};

    _normMap = (jsonDecode(meta['normalize_map'] ?? '{}') as Map)
        .map((k, v) => MapEntry('$k', '$v'));
    _stripChars = meta['strip_chars'] ?? '';

    if (_stripChars.isNotEmpty) {
      _stripRe = RegExp('[${RegExp.escape(_stripChars)}]');
    }
  }

  /// نفس تطبيع tools/arabic.py حرفاً بحرف — القواعد منه لا من هنا.
  String normalize(String text) {
    if (text.isEmpty) return '';
    var t = _stripRe == null ? text : text.replaceAll(_stripRe!, '');
    final sb = StringBuffer();
    for (final ch in t.split('')) {
      sb.write(_normMap[ch] ?? ch);
    }
    return sb.toString().replaceAll(_sepRe, ' ').trim().toLowerCase();
  }

  /// يبحث، ويرتّب بثلاث طبقات قبل الرتبة الثابتة.
  ///
  /// الاستعلام منقول من tools/04_extract_pois.py بعد ما ضبطناه هناك على
  /// بيانات بغداد — نسخة واحدة من المنطق في مكانين، مقابل أن البحث يشتغل
  /// أوفلاين. لو تغيّر هناك يتغيّر هنا.
  Future<List<Place>> search(String query, {LatLng? near}) async {
    final norm = normalize(query);
    final tokens = norm.split(' ').where((t) => t.isNotEmpty).toList();
    if (tokens.isEmpty || norm.length < Cfg.searchMinChars) return [];

    // FTS5 يعدّ المسافة AND ضمناً. النجمة بادئة لأن المستخدم يكتب وهو يبحث
    final andQuery = tokens.map((t) => '"$t"*').join(' ');
    final orQuery = tokens.map((t) => '"$t"*').join(' OR ');

    final out = <int, Place>{};

    for (final db in _dbs) {
      for (final q in [andQuery, if (tokens.length > 1) orQuery]) {
        if (out.length >= Cfg.searchLimit) break;
        final rows = await _run(db, q, norm, Cfg.searchLimit);
        for (final p in rows) {
          out.putIfAbsent(p.id, () => p);
        }
      }
    }

    var results = out.values.toList();

    if (near != null) {
      results = results
          .map((p) => p.withDistance(metersBetween(near, p.pos)))
          .toList();

      // الأقرب أولاً بين متقاربي الرتبة: «صيدلية الرحمة» التي على بعد
      // 300 متر أنفع من واحدة بنفس الاسم في الجهة الثانية من بغداد.
      // ما نرتّب بالمسافة وحدها: «بغداد» على بعد 5 كم تبقى أهم من زقاق
      // على بعد 100 متر
      results.sort((a, b) {
        final byRank = (b.rank ~/ 20).compareTo(a.rank ~/ 20);
        if (byRank != 0) return byRank;
        return (a.distanceM ?? 0).compareTo(b.distanceM ?? 0);
      });
    } else {
      results.sort((a, b) => b.rank.compareTo(a.rank));
    }

    return results.take(Cfg.searchLimit).toList();
  }

  Future<List<Place>> _run(
      Database db, String match, String norm, int limit) async {
    final rows = await db.rawQuery('''
      SELECT p.id, p.name_ar, p.name_en, p.category, p.subtype, p.lat, p.lon,
             p.rank, p.tags, p.source
      FROM poi_fts f JOIN poi p ON p.id = f.rowid
      WHERE poi_fts MATCH ?
      ORDER BY
        (p.name_norm = ?) DESC,
        (p.name_norm LIKE ?) DESC,
        p.rank DESC,
        LENGTH(p.name_norm) ASC,
        bm25(poi_fts)
      LIMIT ?
    ''', [match, norm, '$norm%', limit]);

    return rows.map(_toPlace).toList();
  }

  /// نقاط اهتمام قريبة من نقطة، مفلترة بالتصنيف.
  ///
  /// تستخدمها شاشة «محطات وقود قريبة» وشاشة البحث قبل ما يكتب المستخدم
  /// شيئاً — الفهرس المكاني R*Tree يجيبها بلا مسح الجدول.
  Future<List<Place>> nearby(LatLng center,
      {required List<String> categories,
      double radiusM = 5000,
      int limit = 20}) async {
    // درجة عرض ≈ 111.32 كم. نحوّل نصف القطر لصندوق، ثم نفلتر بالمسافة
    // الحقيقية — الصندوق يجيب زواياه الأبعد من نصف القطر
    final dLat = radiusM / 111320.0;
    final dLon = dLat / math.cos(center.latitude * math.pi / 180.0);

    final placeholders = List.filled(categories.length, '?').join(',');
    final out = <Place>[];

    for (final db in _dbs) {
      final rows = await db.rawQuery('''
        SELECT p.id, p.name_ar, p.name_en, p.category, p.subtype, p.lat, p.lon,
               p.rank, p.tags, p.source
        FROM poi_geo g JOIN poi p ON p.id = g.id
        WHERE g.min_lon >= ? AND g.max_lon <= ?
          AND g.min_lat >= ? AND g.max_lat <= ?
          AND p.category IN ($placeholders)
        LIMIT ?
      ''', [
        center.longitude - dLon, center.longitude + dLon,
        center.latitude - dLat, center.latitude + dLat,
        ...categories,
        limit * 4,
      ]);

      for (final r in rows) {
        final p = _toPlace(r);
        final d = metersBetween(center, p.pos);
        if (d <= radiusM) out.add(p.withDistance(d));
      }
    }

    out.sort((a, b) => (a.distanceM ?? 0).compareTo(b.distanceM ?? 0));
    return out.take(limit).toList();
  }

  Place _toPlace(Map<String, Object?> r) => Place(
        id: r['id'] as int,
        nameAr: r['name_ar'] as String?,
        nameEn: r['name_en'] as String?,
        category: r['category'] as String,
        subtype: r['subtype'] as String?,
        pos: LatLng(r['lat'] as double, r['lon'] as double),
        rank: r['rank'] as int,
        tags: r['tags'] == null
            ? const {}
            : jsonDecode(r['tags'] as String) as Map<String, dynamic>,
        // الحزم القديمة بلا عمود source — نعدّها OSM بدل ما ننهار عليها
        source: (r['source'] as String?) ?? 'osm',
      );

  Future<void> close() async {
    for (final db in _dbs) {
      await db.close();
    }
    _dbs.clear();
  }
}
