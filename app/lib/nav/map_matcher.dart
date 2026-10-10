// مطابقة موقع السائق على المسار، واكتشاف خروجه عنه.
//
// هذي أدقّ قطعة في المحرّك. الأخطاء فيها تظهر كسلوك غريب لا كتعطّل:
// سهم يمشي على الرصيف، أو إعلان «طلعت عن الطريق» وأنت على مسارك، أو
// مناورة تتخطّى نفسها قبل التقاطع.

import 'package:maplibre_gl/maplibre_gl.dart';

import '../config.dart';
import '../core/geo.dart';
import 'route_model.dart';

class MatchResult {
  /// الموقع مثبَّتاً على المسار. هذا ما نرسمه لا قراءة GPS الخام.
  final LatLng snapped;

  /// بعد قراءة GPS عن المسار بالأمتار.
  final double deviationM;

  /// المسافة المقطوعة على المسار من بدايته.
  final double traveledM;

  /// ما تبقّى من المسار بالأمتار.
  final double remainingM;

  /// فهرس المناورة الحالية (التي نتّجه نحو نهايتها).
  final int maneuverIndex;

  /// المسافة إلى بداية المناورة التالية — هذي التي تُعرض وتُنطق.
  final double distanceToManeuverM;

  /// هل السائق خارج المسار الآن (بعد تأكيد عدّة قراءات).
  final bool offRoute;

  /// فهرس القطعة التي سقط عليها الموقع — تستخدمه فلترة البلاغات كي
  /// تبحث من موضعنا لا من أول المسار.
  final int segmentIndex;

  const MatchResult({
    required this.snapped,
    required this.deviationM,
    required this.traveledM,
    required this.remainingM,
    required this.maneuverIndex,
    required this.distanceToManeuverM,
    required this.offRoute,
    required this.segmentIndex,
  });
}

class MapMatcher {
  final NavRoute route;

  /// فهرس القطعة التي سقط عليها الموقع آخر مرة. نبدأ البحث منه لا من
  /// صفر: المسار الذي يمرّ بنفس التقاطع مرتين (دوران حول مجمّع، أو
  /// ذهاب ورجوع على نفس الطريق) يُسقط على المرور الأول فيظن المحرّك أن
  /// السائق رجع كيلومترين للخلف.
  int _cursor = 0;

  int _offRouteStreak = 0;

  /// نافذة البحث حول المؤشّر بعدد القطع. واسعة بقدر ما يمسك قفزة GPS
  /// بعد نفق، وضيّقة بقدر ما لا تقفز لمرور ثانٍ على نفس الشارع.
  static const int _window = 120;

  MapMatcher(this.route);

  /// آخر مسافة مقطوعة مقبولة. نرفض قفزة أكبر مما تسمح به السرعة.
  double _lastTraveled = 0;

  /// أقصى فرق زاوي بين اتجاه السائق واتجاه القطعة قبل رفضها.
  ///
  /// بلا هذي البوابة كانت المطابقة تلتصق بالكاريجوي المقابل: الجزيرة
  /// الوسطية 10–25م وعتبة الخروج 40م، فالاتجاه المعاكس داخل العتبة
  /// دائماً. قراءة GPS واحدة منحرفة عشرة أمتار تنقل المؤشّر لقطعة
  /// الرجوع، ويبقى هناك لأن انحرافه الجديد تحت العتبة فلا بحث كامل
  /// ولا إعلان خروج. النتيجة: السهم يسير عكس اتجاه السائق، والمسافة
  /// المتبقّية تزيد كلما تقدّم، وكل المناورات تضيع.
  static const double _maxHeadingDiff = 65.0;

  /// معامل أقصى قفزة: السرعة × الزمن × هذا. ما نقدر نعرف الزمن بين
  /// قراءتين هنا، فنستخدم سقفاً مطلقاً معايَراً على أسوأ حالة
  /// (120 كم/س × 3 ثوان ≈ 100م) مع هامش
  static const double _maxJumpM = 250.0;

  MatchResult update(LatLng pos, {double? headingDeg, double? speedKmh}) {
    // نبحث في نافذة أمام المؤشّر أولاً — الحالة الغالبة
    var proj = projectOnLine(pos, route.shape,
        searchFrom: _cursor, searchWindow: _window);

    // بعيد عن النافذة؟ نبحث المسار كاملاً مرة. يحدث بعد نفق أو بعد ما
    // يرجع التطبيق من الخلفية وقد قطع السائق مسافة بلا قراءات
    if (proj.distanceM > Cfg.offRouteThresholdM) {
      final full = projectOnLine(pos, route.shape);
      if (full.distanceM < proj.distanceM) proj = full;
    }

    // بوابة الاتجاه: نرفض إسقاطاً على قطعة تسير عكس السائق. نطبّقها
    // فوق عتبة السرعة فقط — تحتها اتجاه GPS لا يُوثق به
    final trustHeading = headingDeg != null &&
        (speedKmh ?? 0) >= Cfg.headingFromGpsMinSpeedKmh;

    if (trustHeading && _segmentOpposes(proj.segmentIndex, headingDeg)) {
      // نبحث قطعة موافقة للاتجاه في النافذة
      final aligned = _nearestAligned(pos, headingDeg);
      if (aligned != null) proj = aligned;
    }

    // سقف القفزة: قفزة أكبر من المعقول بين قراءتين تعني مطابقة على
    // مرور آخر لنفس الشارع، لا تقدّماً حقيقياً
    final jump = (proj.traveledM - _lastTraveled).abs();
    if (_lastTraveled > 0 && jump > _maxJumpM) {
      final near = projectOnLine(pos, route.shape,
          searchFrom: _cursor, searchWindow: 20);
      if (near.distanceM <= Cfg.offRouteThresholdM) proj = near;
    }

    _cursor = proj.segmentIndex;
    _lastTraveled = proj.traveledM;

    final offNow = proj.distanceM > Cfg.offRouteThresholdM;
    // لا نعلن الخروج من أول قراءة: قراءة GPS شاذة تحدث كل دقيقة، وإعادة
    // الحساب عندها تربك السائق أكثر مما تساعده
    _offRouteStreak = offNow ? _offRouteStreak + 1 : 0;

    final remaining = (route.totalLengthM - proj.traveledM).clamp(0.0, 1e9);

    // مسار بلا مناورات: يحدث حين تكون الوجهة موقع المستخدم نفسه، أو
    // حين يرجّع ڤالهالا رحلة منحلّة. انهار عليها فعلاً بـRangeError.
    // المسافة للمناورة = المتبقّي، أي «وصلت» — وهو الصحيح منطقياً
    if (route.maneuvers.isEmpty) {
      return MatchResult(
        snapped: proj.point,
        deviationM: proj.distanceM,
        traveledM: proj.traveledM,
        remainingM: remaining,
        maneuverIndex: 0,
        distanceToManeuverM: remaining,
        offRoute: false,
        segmentIndex: proj.segmentIndex,
      );
    }

    final idx = _maneuverAt(proj.traveledM);
    final next = idx + 1 < route.maneuvers.length ? idx + 1 : idx;
    final toManeuver =
        (route.maneuvers[next].startOffsetM - proj.traveledM).clamp(0.0, 1e9);

    return MatchResult(
      snapped: proj.point,
      deviationM: proj.distanceM,
      traveledM: proj.traveledM,
      remainingM: remaining,
      maneuverIndex: idx,
      distanceToManeuverM: toManeuver,
      offRoute: _offRouteStreak >= Cfg.offRouteConsecutiveFixes,
      segmentIndex: proj.segmentIndex,
    );
  }

  /// هل تسير القطعة عكس اتجاه السائق.
  bool _segmentOpposes(int index, double headingDeg) {
    if (index + 1 >= route.shape.length) return false;
    final segBearing =
        bearingBetween(route.shape[index], route.shape[index + 1]);
    return headingDiff(segBearing, headingDeg) > _maxHeadingDiff;
  }

  /// أقرب قطعة في النافذة تسير باتجاه السائق.
  LineProjection? _nearestAligned(LatLng pos, double headingDeg) {
    final start = _cursor.clamp(0, route.shape.length - 2);
    final end = (start + _window).clamp(1, route.shape.length - 1);

    Projection? best;
    var bestDist = double.infinity;
    var bestIndex = start;

    for (var i = start; i < end; i++) {
      if (_segmentOpposes(i, headingDeg)) continue;
      final pr = projectOnSegment(pos, route.shape[i], route.shape[i + 1]);
      if (pr.distanceM < bestDist) {
        bestDist = pr.distanceM;
        best = pr;
        bestIndex = i;
      }
    }

    if (best == null || bestDist > Cfg.offRouteThresholdM) return null;

    var traveled = 0.0;
    for (var i = 0; i < bestIndex; i++) {
      traveled += metersBetween(route.shape[i], route.shape[i + 1]);
    }
    traveled +=
        metersBetween(route.shape[bestIndex], route.shape[bestIndex + 1]) *
            best.t;

    return LineProjection(best.point, best.distanceM, bestIndex, traveled);
  }

  /// المناورة التي نحن داخلها الآن بناءً على المسافة المقطوعة.
  ///
  /// بحث خطّي لا ثنائي: عدد المناورات عشرات لا آلاف، والبحث الخطّي من
  /// المناورة السابقة يكلّف خطوة أو اثنتين في الحالة الغالبة.
  int _maneuverAt(double traveledM) {
    final ms = route.maneuvers;
    for (var i = ms.length - 1; i >= 0; i--) {
      if (traveledM >= ms[i].startOffsetM) return i;
    }
    return 0;
  }

  /// الزمن المتبقّي تقديراً من نسبة ما تبقّى.
  ///
  /// تقدير خطّي مُعترَف بنقصه: يفترض أن ما تبقّى بنفس متوسط سرعة الكل،
  /// وهو غلط إذا كان الباقي طريقاً سريعاً والماضي داخل المدينة. البديل
  /// الصحيح جمع أزمنة المناورات المتبقّية — وهو ما نسويه أدناه، ونترك
  /// هذي للحالة التي ما فيها مناورات.
  double remainingTimeS(MatchResult m) {
    final ms = route.maneuvers;
    if (ms.isEmpty || m.remainingM <= 0) {
      final ratio = route.totalLengthM <= 0
          ? 0.0
          : m.remainingM / route.totalLengthM;
      return route.effectiveTimeS * ratio;
    }

    // المناورات الكاملة الباقية + الجزء المتبقّي من الحالية
    var total = 0.0;
    for (var i = m.maneuverIndex + 1; i < ms.length; i++) {
      total += ms[i].timeS;
    }

    final cur = ms[m.maneuverIndex];
    if (cur.lengthM > 1) {
      final doneInCur =
          (m.traveledM - cur.startOffsetM).clamp(0.0, cur.lengthM);
      total += cur.timeS * (1 - doneInCur / cur.lengthM);
    }

    // الباكند صحّح الزمن الكلي للزحام؛ نطبّق نفس النسبة على المتبقّي
    final trafficFactor = route.timeS <= 0
        ? 1.0
        : route.effectiveTimeS / route.timeS;
    return total * trafficFactor;
  }
}
