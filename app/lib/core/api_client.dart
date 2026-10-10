// عميل الباكند: البلاغات والزحام والتوجيه.
//
// التطبيق يشتغل بلا باكند: الخريطة والبحث والتوجيه الأساسي كلها محلية.
// فكل دالة هنا ترمي ApiDown عند فشل الشبكة، والمتصل يعرف أنها ميزة
// ناقصة لا خطأ قاتل. ما نبتلع الخطأ بصمت ولا نموت.

import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:maplibre_gl/maplibre_gl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config.dart';

/// الباكند مو متاح — شبكة مقطوعة أو سيرفر واقف.
class ApiDown implements Exception {
  final String message;
  const ApiDown(this.message);
  @override
  String toString() => message;
}

/// الباكند رفض الطلب لسبب معروف. الرسالة عربية جاهزة للعرض.
class ApiRejected implements Exception {
  final int status;
  final String message;
  const ApiRejected(this.status, this.message);
  @override
  String toString() => message;
}

class ApiClient {
  static const _tokenKey = 'darb.device_token';

  String? _token;
  final _http = http.Client();

  bool get hasToken => _token != null;

  /// يحمّل التوكن المحفوظ، ويسجّل الجهاز إن كانت أول مرة.
  ///
  /// التسجيل بلا بريد ولا كلمة مرور: ويز يشتغل بلا حساب، وفرض التسجيل
  /// على مستخدم يبي يعرف الطريق للمستشفى يفقدنا إياه.
  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    _token = prefs.getString(_tokenKey);
    if (_token != null) return;

    // الفشل هنا ليس قاتلاً: التطبيق يشتغل أوفلاين بلا توكن، ونعيد
    // المحاولة عند أول إبلاغ
    try {
      final j = await _post('/auth/device', null, auth: false);
      _token = j['token'] as String;
      await prefs.setString(_tokenKey, _token!);
    } on ApiDown {
      return;
    }
  }

  Uri _uri(String path, [Map<String, String>? q]) =>
      Uri.parse('${Cfg.apiBase}$path').replace(queryParameters: q);

  Map<String, String> _headers({bool auth = true}) => {
        'content-type': 'application/json; charset=utf-8',
        if (auth && _token != null) 'authorization': 'Bearer $_token',
      };

  Future<dynamic> _send(Future<http.Response> Function() call) async {
    http.Response r;
    try {
      r = await call();
    } on SocketException {
      throw const ApiDown('لا اتصال بالسيرفر');
    } on http.ClientException catch (e) {
      throw ApiDown('فشل الاتصال: ${e.message}');
    }

    if (r.statusCode >= 200 && r.statusCode < 300) {
      if (r.body.isEmpty) return null;
      return jsonDecode(utf8.decode(r.bodyBytes));
    }

    // الباكند يرسل رسالة عربية في detail — نمرّرها للمستخدم كما هي لأنها
    // تفرّق بين «صوّتت سابقاً» و«البلاغ انتهى»، والفرق يهمّه
    var msg = 'خطأ ${r.statusCode}';
    try {
      final j = jsonDecode(utf8.decode(r.bodyBytes));
      final d = j is Map ? j['detail'] : null;
      if (d is String) {
        msg = d;
      } else if (d is List && d.isNotEmpty) {
        msg = '${(d.first as Map)['msg']}';
      }
    } on FormatException {
      // رد غير JSON: نُبقي الرسالة العامة
    }
    throw ApiRejected(r.statusCode, msg);
  }

  Future<dynamic> _post(String path, Object? body,
          {bool auth = true, Duration? timeout}) =>
      _send(() => _http
          .post(_uri(path),
              headers: _headers(auth: auth),
              body: body == null ? null : jsonEncode(body))
          .timeout(timeout ?? Cfg.apiTimeout));

  Future<dynamic> _get(String path,
          [Map<String, String>? q, Duration? timeout]) =>
      _send(() => _http
          .get(_uri(path, q), headers: _headers())
          .timeout(timeout ?? Cfg.apiTimeoutLive));

  // ── التوجيه ──────────────────────────────────────────────────────────────

  Future<Map<String, dynamic>> route({
    required List<LatLng> points,
    String costing = 'auto',
    bool avoidClosures = true,
    bool avoidHighways = false,
    bool avoidTolls = false,
    bool avoidFerries = false,
    int alternates = 2,
  }) async {
    final j = await _post('/route', {
      'locations': [
        for (final p in points) {'lat': p.latitude, 'lon': p.longitude}
      ],
      'costing': costing,
      'avoid_closures': avoidClosures,
      'avoid_highways': avoidHighways,
      'avoid_tolls': avoidTolls,
      'avoid_ferries': avoidFerries,
      'alternates': alternates,
    });
    return j as Map<String, dynamic>;
  }

  // ── البلاغات ─────────────────────────────────────────────────────────────

  Future<Map<String, dynamic>> reportTypes() async =>
      (await _get('/reports/types')) as Map<String, dynamic>;

  Future<Map<String, dynamic>> createReport({
    required String kind,
    required LatLng pos,
    double? heading,
    String? note,
  }) async {
    if (_token == null) await init();
    if (_token == null) throw const ApiDown('ما قدرنا نسجّل الجهاز');

    final j = await _post('/reports', {
      'kind': kind,
      'lat': pos.latitude,
      'lon': pos.longitude,
      // المفتاح يُحذف إذا كان الاتجاه null — الباكند يعدّه «بلا اتجاه»
      // فما يفلتر البلاغ بالجهة
      'heading': ?heading,
      if (note != null && note.isNotEmpty) 'note': note,
    });
    return j as Map<String, dynamic>;
  }

  Future<List<Map<String, dynamic>>> reportsNear(LatLng center,
      {int radiusM = 2000, double? heading}) async {
    final j = await _get('/reports/near', {
      'lat': '${center.latitude}',
      'lon': '${center.longitude}',
      'radius_m': '$radiusM',
      if (heading != null) 'heading': '$heading',
    });
    return (j as List).cast<Map<String, dynamic>>();
  }

  Future<Map<String, dynamic>> vote(int reportId, {required bool isUp}) async {
    final j = await _post('/reports/$reportId/vote', {'is_up': isUp});
    return j as Map<String, dynamic>;
  }

  // ── الزحام ───────────────────────────────────────────────────────────────

  /// يرسل قطعة مسار مجهولة. بلا توكن بقصد — ربط القراءة بجهاز هو بالضبط
  /// ما نتجنّبه.
  Future<int> submitTrace(List<Map<String, dynamic>> points) async {
    final j = await _post('/traffic/trace', {'points': points}, auth: false);
    return ((j as Map)['stored'] as num).toInt();
  }

  Future<List<Map<String, dynamic>>> trafficSegments(List<int> wayIds) async {
    if (wayIds.isEmpty) return const [];
    final j = await _get('/traffic/segments', {'way_ids': wayIds.join(',')});
    return (j as List).cast<Map<String, dynamic>>();
  }

  /// منحنى الزحام بساعات اليوم. الساعة بلا قراءات كافية ترجع null —
  /// والشاشة ترسمها عموداً باهتاً لا أخضر.
  Future<({List<double?> hours, int windowDays})> trafficProfile() async {
    final j = (await _get('/traffic/profile')) as Map<String, dynamic>;
    return (
      hours: [
        for (final v in (j['hours'] as List)) (v as num?)?.toDouble()
      ],
      windowDays: (j['window_days'] as num?)?.toInt() ?? 7,
    );
  }

  Future<bool> ping() async {
    try {
      await _get('/health', null, const Duration(seconds: 3));
      return true;
    } on ApiDown {
      return false;
    } on ApiRejected {
      return false;
    }
  }

  void dispose() => _http.close();
}
