// حسابات جغرافية. كلها مستوية التقريب لا كروية: على مسافات الملاحة
// (أمتار إلى كيلومترات) خطأ التقريب المستوي سنتمترات، وتُنادى هذي الدوال
// لكل قراءة GPS على كل قطعة من المسار — أي آلاف المرات في الدقيقة.

import 'dart:math' as math;

import 'package:maplibre_gl/maplibre_gl.dart';

/// أمتار لكل درجة عرض. ثابت عملياً (الفرق بين القطب والاستواء 0.5%).
const double _mPerDegLat = 111320.0;

double _mPerDegLon(double lat) =>
    _mPerDegLat * math.cos(lat * math.pi / 180.0);

/// المسافة بالأمتار بين نقطتين.
double metersBetween(LatLng a, LatLng b) {
  final dy = (b.latitude - a.latitude) * _mPerDegLat;
  final dx = (b.longitude - a.longitude) *
      _mPerDegLon((a.latitude + b.latitude) / 2);
  return math.sqrt(dx * dx + dy * dy);
}

/// الاتجاه من a إلى b بالدرجات (0 شمالاً، يزيد باتجاه الشرق).
double bearingBetween(LatLng a, LatLng b) {
  final dy = (b.latitude - a.latitude) * _mPerDegLat;
  final dx = (b.longitude - a.longitude) *
      _mPerDegLon((a.latitude + b.latitude) / 2);
  final deg = math.atan2(dx, dy) * 180.0 / math.pi;
  return (deg + 360.0) % 360.0;
}

/// أصغر فرق زاوي بين اتجاهين (0–180).
double headingDiff(double a, double b) {
  final d = (a - b).abs() % 360.0;
  return d > 180.0 ? 360.0 - d : d;
}

/// يدمج اتجاهاً جديداً مع القديم بتنعيم أسّي، ويعبر حدّ 360/0 صحيحاً.
///
/// الدمج الساذج `old*(1-k) + new*k` يكسر عند العبور: من 350 إلى 10 يمرّ
/// بـ180 فتدور الخريطة دورة كاملة عند كل مرور شمالاً.
double smoothHeading(double current, double target, double k) {
  var delta = (target - current + 540.0) % 360.0 - 180.0;
  return (current + delta * k + 360.0) % 360.0;
}

/// نتيجة إسقاط نقطة على قطعة مستقيمة.
class Projection {
  /// أقرب نقطة على القطعة.
  final LatLng point;

  /// بعد النقطة الأصلية عن القطعة بالأمتار.
  final double distanceM;

  /// موضع الإسقاط على القطعة: 0 عند بدايتها، 1 عند نهايتها.
  final double t;

  const Projection(this.point, this.distanceM, this.t);
}

/// يُسقط p على القطعة [a,b].
Projection projectOnSegment(LatLng p, LatLng a, LatLng b) {
  // نحوّل لمستوي متري محلي حول a: الحساب بالدرجات يشوّه النسب لأن درجة
  // الطول أقصر من درجة العرض بمقدار cos(lat)
  final latRef = (a.latitude + b.latitude) / 2;
  final mLon = _mPerDegLon(latRef);

  final ax = 0.0, ay = 0.0;
  final bx = (b.longitude - a.longitude) * mLon;
  final by = (b.latitude - a.latitude) * _mPerDegLat;
  final px = (p.longitude - a.longitude) * mLon;
  final py = (p.latitude - a.latitude) * _mPerDegLat;

  final dx = bx - ax, dy = by - ay;
  final lenSq = dx * dx + dy * dy;

  // قطعة منعدمة الطول: تحدث فعلاً في خطوط Valhalla حين تتكرر نقطة
  if (lenSq < 1e-9) {
    return Projection(a, metersBetween(p, a), 0.0);
  }

  var t = (px * dx + py * dy) / lenSq;
  t = t.clamp(0.0, 1.0);

  final cx = dx * t, cy = dy * t;
  final dist = math.sqrt((px - cx) * (px - cx) + (py - cy) * (py - cy));

  final proj = LatLng(
    a.latitude + (cy / _mPerDegLat),
    a.longitude + (cx / mLon),
  );
  return Projection(proj, dist, t);
}

/// نتيجة إسقاط نقطة على خط متعدد القطع.
class LineProjection {
  final LatLng point;
  final double distanceM;

  /// فهرس القطعة التي سقطت عليها النقطة (القطعة i بين shape[i] و shape[i+1]).
  final int segmentIndex;

  /// المسافة المقطوعة على الخط من بدايته حتى نقطة الإسقاط، بالأمتار.
  final double traveledM;

  const LineProjection(
      this.point, this.distanceM, this.segmentIndex, this.traveledM);
}

/// يُسقط p على خط، ويرجّع أقرب نقطة ومسافة السير إليها.
///
/// [searchFrom] يحدّ البحث بقطعة معيّنة وما بعدها. ضروري وليس تحسيناً:
/// المسار الذي يمرّ بنفس التقاطع مرتين (دوران حول مجمّع) يُسقط على المرور
/// الأول فيظن المحرّك أن السائق رجع للخلف.
LineProjection projectOnLine(LatLng p, List<LatLng> shape,
    {int searchFrom = 0, int searchWindow = 0}) {
  if (shape.length < 2) {
    final only = shape.isEmpty ? p : shape.first;
    return LineProjection(only, metersBetween(p, only), 0, 0.0);
  }

  final start = searchFrom.clamp(0, shape.length - 2);
  final end = searchWindow > 0
      ? math.min(shape.length - 1, start + searchWindow)
      : shape.length - 1;

  var bestDist = double.infinity;
  var bestIdx = start;
  Projection? best;

  for (var i = start; i < end; i++) {
    final pr = projectOnSegment(p, shape[i], shape[i + 1]);
    if (pr.distanceM < bestDist) {
      bestDist = pr.distanceM;
      bestIdx = i;
      best = pr;
    }
  }

  best ??= projectOnSegment(p, shape[start], shape[start + 1]);

  // المسافة المقطوعة: أطوال القطع الكاملة قبلنا + جزء قطعتنا
  var traveled = 0.0;
  for (var i = 0; i < bestIdx; i++) {
    traveled += metersBetween(shape[i], shape[i + 1]);
  }
  traveled += metersBetween(shape[bestIdx], shape[bestIdx + 1]) * best.t;

  return LineProjection(best.point, best.distanceM, bestIdx, traveled);
}

/// طول الخط كاملاً بالأمتار.
double lineLength(List<LatLng> shape) {
  var total = 0.0;
  for (var i = 0; i + 1 < shape.length; i++) {
    total += metersBetween(shape[i], shape[i + 1]);
  }
  return total;
}

/// يقصّ الخط من مسافة سير معيّنة حتى نهايته.
///
/// نحتاجه لرسم «ما تبقّى من المسار» بلون غامق وما مضى شفافاً — السائق يرى
/// تقدّمه لا خطاً واحداً ثابتاً.
List<LatLng> lineFrom(List<LatLng> shape, double fromM) {
  if (shape.length < 2 || fromM <= 0) return List.of(shape);

  var acc = 0.0;
  for (var i = 0; i + 1 < shape.length; i++) {
    final segLen = metersBetween(shape[i], shape[i + 1]);
    if (acc + segLen >= fromM) {
      final t = segLen < 1e-9 ? 0.0 : (fromM - acc) / segLen;
      final cut = LatLng(
        shape[i].latitude + (shape[i + 1].latitude - shape[i].latitude) * t,
        shape[i].longitude + (shape[i + 1].longitude - shape[i].longitude) * t,
      );
      return [cut, ...shape.sublist(i + 1)];
    }
    acc += segLen;
  }
  return [shape.last];
}

/// صندوق يحوي كل النقاط، مع حاشية نسبية.
///
/// الحاشية نسبية لا ثابتة: مسار 300 متر وحاشية 2 كم يجعله نقطة في وسط
/// الشاشة، ومسار 300 كم وحاشية 2 كم لا تُرى.
LatLngBounds boundsOf(List<LatLng> pts, {double padRatio = 0.12}) {
  var minLat = pts.first.latitude, maxLat = pts.first.latitude;
  var minLon = pts.first.longitude, maxLon = pts.first.longitude;

  for (final p in pts) {
    minLat = math.min(minLat, p.latitude);
    maxLat = math.max(maxLat, p.latitude);
    minLon = math.min(minLon, p.longitude);
    maxLon = math.max(maxLon, p.longitude);
  }

  final padLat = math.max((maxLat - minLat) * padRatio, 0.002);
  final padLon = math.max((maxLon - minLon) * padRatio, 0.002);

  return LatLngBounds(
    southwest: LatLng(minLat - padLat, minLon - padLon),
    northeast: LatLng(maxLat + padLat, maxLon + padLon),
  );
}

/// يفكّك polyline6 المرمَّز الذي يرجّعه Valhalla.
///
/// Valhalla يستخدم دقة 6 منازل لا 5 كما Google — نفس الخوارزمية وقاسم
/// مختلف. خلط القاسمين يعطي خطاً صحيح الشكل ومضروباً بعشرة في الموقع،
/// وهو أسوأ من خطأ صريح لأنه يبدو كأنه يشتغل.
List<LatLng> decodePolyline6(String encoded) {
  final points = <LatLng>[];
  var index = 0, lat = 0, lon = 0;

  while (index < encoded.length) {
    var shift = 0, result = 0;
    int byte;
    do {
      byte = encoded.codeUnitAt(index++) - 63;
      result |= (byte & 0x1f) << shift;
      shift += 5;
    } while (byte >= 0x20);
    lat += (result & 1) != 0 ? ~(result >> 1) : (result >> 1);

    shift = 0;
    result = 0;
    do {
      byte = encoded.codeUnitAt(index++) - 63;
      result |= (byte & 0x1f) << shift;
      shift += 5;
    } while (byte >= 0x20);
    lon += (result & 1) != 0 ? ~(result >> 1) : (result >> 1);

    points.add(LatLng(lat / 1e6, lon / 1e6));
  }
  return points;
}
