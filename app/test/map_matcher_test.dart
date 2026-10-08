// اختبارات مطابقة الموقع على المسار.
//
// المسار المستخدم خطّ حقيقي من ڤالهالا (ساحة التحرير ← المنصور، 159
// نقطة، 7.56 كم). الحالات الملتوية هنا من سلوك صادفناه أو توقّعناه في
// شوارع بغداد: الخدمي الموازي لطريق محمد القاسم، والقفزة بعد النفق،
// والمسار الذي يمرّ بنفس التقاطع مرتين.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

import 'package:darb/config.dart';
import 'package:darb/core/geo.dart';
import 'package:darb/nav/map_matcher.dart';
import 'package:darb/nav/route_model.dart';

/// مسار من نقاط معطاة، بمناورة واحدة لكل قطعتين — يكفي لاختبار المطابقة
/// بلا تزييف رد ڤالهالا كاملاً.
NavRoute routeFrom(List<LatLng> shape) {
  final maneuvers = <Maneuver>[];
  var offset = 0.0;

  for (var i = 0; i + 1 < shape.length; i += 2) {
    final end = (i + 2).clamp(0, shape.length - 1);
    final seg = shape.sublist(i, end + 1);
    final len = lineLength(seg);

    maneuvers.add(Maneuver(
      type: i == 0 ? Mnv.start : Mnv.continueOn,
      streetNames: const [],
      beginStreetNames: const [],
      beginShapeIndex: i,
      endShapeIndex: end,
      lengthKm: len / 1000,
      timeS: len / 10,
      roundaboutExitCount: null,
      exitNumber: null,
      exitToward: const [],
      bearingBefore: null,
      bearingAfter: null,
      trafficLevel: null,
      shape: seg,
      startOffsetM: offset,
    ));
    offset += len;
  }

  final total = lineLength(shape);
  return NavRoute(
    shape: shape,
    maneuvers: maneuvers,
    lengthKm: total / 1000,
    timeS: total / 10,
    timeWithTrafficS: null,
    trafficCoverage: 0,
    closuresAvoided: 0,
  );
}

void main() {
  late List<LatLng> realShape;

  setUpAll(() {
    realShape = decodePolyline6(
        File('test/fixtures/tahrir_to_mansour.polyline6.txt')
            .readAsStringSync()
            .trim());
  });

  group('التقدّم على مسار حقيقي', () {
    test('السير على نقاط المسار نفسها يعطي انحرافاً صفرياً', () {
      final m = MapMatcher(routeFrom(realShape));

      for (var i = 0; i < realShape.length; i += 7) {
        final r = m.update(realShape[i]);
        expect(r.deviationM, lessThan(1.0),
            reason: 'النقطة $i على المسار حرفياً');
        expect(r.offRoute, isFalse);
      }
    });

    test('المسافة المقطوعة تزيد ولا تنقص مع التقدّم', () {
      // الرجوع للخلف هو العرض الذي يظهر حين تنكسر نافذة البحث: يعلن
      // المحرّك مناورة سابقة وينطقها من جديد
      final m = MapMatcher(routeFrom(realShape));
      var last = -1.0;

      for (var i = 0; i < realShape.length; i += 3) {
        final r = m.update(realShape[i]);
        expect(r.traveledM, greaterThanOrEqualTo(last - 1.0),
            reason: 'رجعنا للخلف عند النقطة $i');
        last = r.traveledM;
      }
    });

    test('المتبقّي ينقص حتى يقارب الصفر عند النهاية', () {
      final route = routeFrom(realShape);
      final m = MapMatcher(route);

      for (var i = 0; i < realShape.length; i += 5) {
        m.update(realShape[i]);
      }
      final end = m.update(realShape.last);

      expect(end.remainingM, lessThan(5));
      expect(end.traveledM, closeTo(route.totalLengthM, 5));
    });

    test('فهرس المناورة يتقدّم ولا يتراجع', () {
      final m = MapMatcher(routeFrom(realShape));
      var lastIdx = -1;

      for (var i = 0; i < realShape.length; i += 4) {
        final r = m.update(realShape[i]);
        expect(r.maneuverIndex, greaterThanOrEqualTo(lastIdx));
        lastIdx = r.maneuverIndex;
      }
    });
  });

  group('الخروج عن المسار', () {
    test('قراءة شاذة واحدة لا تعلن خروجاً', () {
      // هذي الحالة التي تبرّر عتبة القراءات المتتالية: GPS يرمي قراءة
      // بعيدة كل دقيقة تقريباً، وإعادة الحساب عندها تربك السائق
      final m = MapMatcher(routeFrom(realShape));
      m.update(realShape[10]);

      final spike = LatLng(
        realShape[10].latitude + 0.004, // ~440م
        realShape[10].longitude,
      );
      final r = m.update(spike);

      expect(r.deviationM, greaterThan(Cfg.offRouteThresholdM));
      expect(r.offRoute, isFalse, reason: 'قراءة واحدة ما تكفي');
    });

    test('ثلاث قراءات بعيدة متتالية تعلن خروجاً', () {
      final m = MapMatcher(routeFrom(realShape));
      m.update(realShape[10]);

      late MatchResult r;
      for (var i = 0; i < Cfg.offRouteConsecutiveFixes; i++) {
        r = m.update(LatLng(
          realShape[10].latitude + 0.004 + i * 0.0005,
          realShape[10].longitude,
        ));
      }
      expect(r.offRoute, isTrue);
    });

    test('الرجوع للمسار يصفّر العدّاد فوراً', () {
      final m = MapMatcher(routeFrom(realShape));
      m.update(realShape[10]);
      m.update(LatLng(realShape[10].latitude + 0.004,
          realShape[10].longitude));
      m.update(LatLng(realShape[10].latitude + 0.004,
          realShape[10].longitude));

      final back = m.update(realShape[12]);
      expect(back.offRoute, isFalse);
    });

    test('الخدمي الموازي على 25م يبقى «على المسار»', () {
      // طريق محمد القاسم عريض وله خدمي موازٍ. عتبة أضيق من 40م تعلن
      // خروجاً وأنت على مسارك
      final m = MapMatcher(routeFrom(realShape));
      final offset = LatLng(
        realShape[20].latitude + 0.000225, // ~25م
        realShape[20].longitude,
      );
      final r = m.update(offset);

      expect(r.deviationM, closeTo(25, 6));
      expect(r.offRoute, isFalse);
    });
  });

  group('المسار الذي يمرّ بنفس المكان مرتين', () {
    // دوران حول مجمّع، أو ذهاب ورجوع على نفس الشارع
    final loop = [
      const LatLng(33.300, 44.400),
      const LatLng(33.305, 44.400),
      const LatLng(33.310, 44.400),
      const LatLng(33.310, 44.405),
      const LatLng(33.310, 44.410),
      const LatLng(33.305, 44.410),
      const LatLng(33.300, 44.410),
      const LatLng(33.300, 44.405),
      const LatLng(33.300, 44.400), // رجعنا للبداية
    ];

    test('المرور الثاني ما يُسقط على المرور الأول', () {
      final m = MapMatcher(routeFrom(loop));

      // نمشي الحلقة كاملة
      for (final p in loop) {
        m.update(p);
      }

      // الآن قريب من نقطة البداية، لكننا في آخر المسار لا أوّله
      final r = m.update(const LatLng(33.3001, 44.4001));

      expect(r.traveledM, greaterThan(lineLength(loop) * 0.8),
          reason: 'ظنّ المحرّك أننا في أول المسار لا آخره');
      expect(r.remainingM, lessThan(lineLength(loop) * 0.2));
    });
  });

  group('الزمن المتبقّي', () {
    test('ينقص مع التقدّم', () {
      final route = routeFrom(realShape);
      final m = MapMatcher(route);

      final early = m.remainingTimeS(m.update(realShape[5]));
      for (var i = 10; i < realShape.length - 10; i += 5) {
        m.update(realShape[i]);
      }
      final late_ = m.remainingTimeS(m.update(realShape[realShape.length - 5]));

      expect(late_, lessThan(early));
    });

    test('يقارب صفراً عند الوصول', () {
      final route = routeFrom(realShape);
      final m = MapMatcher(route);
      for (var i = 0; i < realShape.length; i += 5) {
        m.update(realShape[i]);
      }
      final end = m.update(realShape.last);
      expect(m.remainingTimeS(end), lessThan(route.timeS * 0.05));
    });

    test('يبدأ قريباً من زمن المسار الكامل', () {
      final route = routeFrom(realShape);
      final m = MapMatcher(route);
      final start = m.remainingTimeS(m.update(realShape.first));
      expect(start, closeTo(route.timeS, route.timeS * 0.1));
    });
  });

  group('مسار منحلّ', () {
    test('مسار بنقطة واحدة ما يرمي استثناء', () {
      // يحدث لو كانت الوجهة هي موقع المستخدم نفسه
      final m = MapMatcher(routeFrom([const LatLng(33.30, 44.40)]));
      final r = m.update(const LatLng(33.30, 44.40));
      expect(r.traveledM, 0);
      expect(r.offRoute, isFalse);
    });
  });
}
