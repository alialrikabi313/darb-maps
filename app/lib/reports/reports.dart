// البلاغات: النموذج، شكلها على الخريطة، وجلبها من الباكند.
//
// الأنواع وصلاحياتها تجي من السيرفر لا مكتوبة هنا: إضافة نوع بلاغ تصير
// بتعديل tools/config.py وإعادة تشغيل السيرفر، بلا نشر إصدار جديد من
// التطبيق. الأيقونة واللون هنا لأنهما شكل لا سياسة، ومع افتراضي للنوع
// الذي ما نعرفه كي لا يختفي بلاغ جديد من الخريطة.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

import '../core/api_client.dart';
import '../core/geo.dart';

class Report {
  final int id;
  final String kind;
  final String label;
  final LatLng pos;

  /// اتجاه المُبلِّغ. الرادار والسيطرة على جهة واحدة من الطريق.
  final double? heading;

  final String? note;
  final DateTime createdAt;
  final DateTime expiresAt;
  final int upVotes;
  final int downVotes;
  final bool confirmed;
  final double confidence;

  /// عدد البلاغات المجمّعة في هذا. نعرضه عدّاداً لا أيقونات متراكبة.
  final int clusterSize;

  final double? distanceM;

  const Report({
    required this.id,
    required this.kind,
    required this.label,
    required this.pos,
    required this.heading,
    required this.note,
    required this.createdAt,
    required this.expiresAt,
    required this.upVotes,
    required this.downVotes,
    required this.confirmed,
    required this.confidence,
    required this.clusterSize,
    required this.distanceM,
  });

  factory Report.fromJson(Map<String, dynamic> j) => Report(
        id: (j['id'] as num).toInt(),
        kind: j['kind'] as String,
        label: j['label'] as String,
        pos: LatLng((j['lat'] as num).toDouble(), (j['lon'] as num).toDouble()),
        heading: (j['heading'] as num?)?.toDouble(),
        note: j['note'] as String?,
        createdAt: DateTime.parse(j['created_at'] as String),
        expiresAt: DateTime.parse(j['expires_at'] as String),
        upVotes: (j['up_votes'] as num).toInt(),
        downVotes: (j['down_votes'] as num).toInt(),
        confirmed: j['confirmed'] as bool,
        confidence: (j['confidence'] as num).toDouble(),
        clusterSize: (j['cluster_size'] as num?)?.toInt() ?? 1,
        distanceM: (j['distance_m'] as num?)?.toDouble(),
      );

  /// عمر البلاغ مكتوباً — السائق يحكم بنفسه على بلاغ عمره ساعة.
  String get ageLabel {
    final mins = DateTime.now().difference(createdAt).inMinutes;
    if (mins < 1) return 'الآن';
    if (mins < 60) return 'قبل $mins دقيقة';
    final h = mins ~/ 60;
    if (h < 24) return h == 1 ? 'قبل ساعة' : 'قبل $h ساعات';
    final d = h ~/ 24;
    return d == 1 ? 'قبل يوم' : 'قبل $d أيام';
  }
}

/// شكل كل نوع. الافتراضي يضمن أن نوعاً جديداً من السيرفر يُعرض ولا يختفي.
class ReportLook {
  final IconData icon;
  final Color color;
  const ReportLook(this.icon, this.color);
}

const _fallbackLook = ReportLook(Icons.info_outline, Color(0xFF6B7280));

const Map<String, ReportLook> _looks = {
  'crash': ReportLook(Icons.car_crash, Color(0xFFD6333F)),
  'jam': ReportLook(Icons.traffic, Color(0xFFF07B2B)),
  'police': ReportLook(Icons.local_police, Color(0xFF2563EB)),
  'speed_camera': ReportLook(Icons.photo_camera, Color(0xFF7C3AED)),
  'hazard': ReportLook(Icons.warning_amber, Color(0xFFF2C037)),
  'pothole': ReportLook(Icons.dangerous, Color(0xFF8B5E34)),
  'road_closed': ReportLook(Icons.block, Color(0xFFB91C1C)),
  'flood': ReportLook(Icons.water, Color(0xFF0EA5E9)),
  'checkpoint': ReportLook(Icons.shield, Color(0xFF1D4ED8)),
  'fuel_queue': ReportLook(Icons.local_gas_station, Color(0xFF059669)),
};

ReportLook lookFor(String kind) => _looks[kind] ?? _fallbackLook;

/// نوع بلاغ كما يعرّفه السيرفر.
class ReportType {
  final String kind;
  final String label;
  final int ttlMin;
  final int votesToConfirm;

  const ReportType({
    required this.kind,
    required this.label,
    required this.ttlMin,
    required this.votesToConfirm,
  });

  ReportLook get look => lookFor(kind);
}

class ReportsRepo {
  final ApiClient api;
  ReportsRepo(this.api);

  List<ReportType> _types = const [];
  List<Report> _nearby = const [];
  DateTime _lastFetch = DateTime.fromMillisecondsSinceEpoch(0);
  LatLng? _lastCenter;

  List<ReportType> get types => _types;
  List<Report> get nearby => _nearby;

  /// آخر خطأ شبكة — الواجهة تعرضه شريطاً لا حواراً يقطع الملاحة.
  String? lastError;

  /// يحمّل أنواع البلاغات. إن فشل، نبقى بلا أنواع والزرّ يُعرض معطّلاً
  /// برسالة — لا نخترع أنواعاً من عندنا فيرفضها السيرفر عند الإرسال.
  Future<void> loadTypes() async {
    try {
      final j = await api.reportTypes();
      _types = j.entries
          .map((e) => ReportType(
                kind: e.key,
                label: (e.value as Map)['label'] as String,
                ttlMin: ((e.value as Map)['ttl_min'] as num).toInt(),
                votesToConfirm:
                    ((e.value as Map)['votes_to_confirm'] as num).toInt(),
              ))
          .toList();
      lastError = null;
    } on ApiDown catch (e) {
      lastError = e.message;
    }
  }

  /// يجلب البلاغات حول نقطة. لا يعيد الجلب إن كان المركز ما تحرّك كثيراً
  /// ولم يمضِ وقت كافٍ — أثناء الملاحة تُنادى كل قراءة GPS.
  Future<List<Report>> refresh(LatLng center,
      {double? heading,
      bool force = false,
      Duration minInterval = const Duration(seconds: 20),
      double minMoveM = 400}) async {
    final now = DateTime.now();
    final moved = _lastCenter == null
        ? double.infinity
        : _roughMeters(_lastCenter!, center);

    if (!force &&
        now.difference(_lastFetch) < minInterval &&
        moved < minMoveM) {
      return _nearby;
    }

    try {
      final list = await api.reportsNear(center, heading: heading);
      _nearby = list.map(Report.fromJson).toList();
      _lastFetch = now;
      _lastCenter = center;
      lastError = null;
    } on ApiDown catch (e) {
      lastError = e.message;
      // نُبقي البلاغات القديمة معروضة: بلاغ عمره خمس دقائق أنفع من خريطة
      // فاضية، وعمره معروض على البطاقة فالمستخدم يحكم بنفسه
    } on ApiRejected catch (e) {
      lastError = e.message;
    }
    return _nearby;
  }

  Future<Report?> send({
    required String kind,
    required LatLng pos,
    double? heading,
    String? note,
  }) async {
    final j = await api.createReport(
        kind: kind, pos: pos, heading: heading, note: note);
    final r = Report.fromJson(j);
    _nearby = [r, ..._nearby];
    return r;
  }

  Future<Report> vote(int id, {required bool isUp}) async {
    final j = await api.vote(id, isUp: isUp);
    final updated = Report.fromJson(j);
    _nearby = _nearby.map((r) => r.id == id ? updated : r).toList();
    return updated;
  }

  static double _roughMeters(LatLng a, LatLng b) =>
      metersBetween(a, b);
}
