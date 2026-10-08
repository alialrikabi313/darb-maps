// اختبارات صياغة الجمل العربية.
//
// الحالات من مناورات حقيقية رجّعها Valhalla على مسارات بغداد التي
// جرّبناها في tools/03_build_routing_graph.py — أنواع 1, 8, 10, 13, 15,
// 16, 24 كلها ظهرت فعلاً هناك.

import 'package:flutter_test/flutter_test.dart';

import 'package:darb/nav/phrases.dart';
import 'package:darb/nav/route_model.dart';

Maneuver mk(int type,
        {List<String> streets = const [],
        List<String> beginStreets = const [],
        int? roundaboutExit,
        String? exitNumber}) =>
    Maneuver(
      type: type,
      streetNames: streets,
      beginStreetNames: beginStreets,
      beginShapeIndex: 0,
      endShapeIndex: 1,
      lengthKm: 1.0,
      timeS: 60,
      roundaboutExitCount: roundaboutExit,
      exitNumber: exitNumber,
      exitToward: const [],
      bearingBefore: null,
      bearingAfter: null,
      trafficLevel: null,
      shape: const [],
      startOffsetM: 0,
    );

void main() {
  group('distanceText — المسافة منطوقة', () {
    test('تحت 30 متر تصير «الآن»', () {
      // دقة زائفة: «بعد 12 متر، انعطف» أبطأ نطقاً من المناورة نفسها
      expect(distanceText(12), 'الآن');
    });

    test('تحت 150 متر تُقرَّب لعشرة', () {
      expect(distanceText(87), '90 متر');
    });

    test('فوق 150 متر تُقرَّب لخمسين', () {
      // «بعد 487 متر» ما يقولها إنسان
      expect(distanceText(487), '500 متر');
    });

    test('الكيلومتر الكسري بمنزلة واحدة بلا صفر زائد', () {
      expect(distanceText(2000), '2 كيلومتر');
      expect(distanceText(2400), '2.4 كيلومتر');
    });

    test('فوق عشرة كيلومترات بلا كسور', () {
      expect(distanceText(24200), '24 كيلومتر');
    });
  });

  group('durationLabel', () {
    test('تحت دقيقة', () => expect(durationLabel(30), 'أقل من دقيقة'));
    test('دقائق', () => expect(durationLabel(960), '16 دقيقة'));
    test('ساعة مفردة بلا رقم', () => expect(durationLabel(3600), 'ساعة'));
    test('ساعة ودقائق', () => expect(durationLabel(4500), 'ساعة و15 دقيقة'));
    test('ساعات', () => expect(durationLabel(7200), '2 ساعات'));
  });

  group('maneuverTitle — أنواع ظهرت فعلاً في مسارات بغداد', () {
    test('type=1 بداية', () => expect(maneuverTitle(mk(1)), 'ابدأ السير'));
    test('type=8 استمرار', () => expect(maneuverTitle(mk(8)), 'كمّل مستقيم'));
    test('type=10 يمين', () => expect(maneuverTitle(mk(10)), 'انعطف يمين'));
    test('type=15 يسار', () => expect(maneuverTitle(mk(15)), 'انعطف يسار'));
    test('type=16 ميل يسار', () => expect(maneuverTitle(mk(16)), 'مِل يسار'));
    test('type=13 استدارة', () {
      // ظهرت على شارع المحيط في مسار الكاظمية ← المنصور
      expect(maneuverTitle(mk(13)), 'استدر بالعكس');
    });
    test('type=24 ابقَ يسار', () {
      // ظهرت على طريق المطار السريع
      expect(maneuverTitle(mk(24)), 'ابقَ يسار');
    });

    test('نوع ما نعرفه ما يرجّع نصّاً فارغاً', () {
      // أنواع ڤالهالا تزيد بالإصدارات، والنصّ الفارغ يعني شريطاً فاضياً
      expect(maneuverTitle(mk(99)), isNotEmpty);
    });
  });

  group('مخرج الدوّار بالترتيب العربي', () {
    test('ثالث مخرج', () {
      expect(maneuverTitle(mk(Mnv.roundaboutEnter, roundaboutExit: 3)),
          'ادخل الدوّار واخرج من ثالث مخرج');
    });

    test('بلا رقم مخرج ما نخترع واحداً', () {
      expect(maneuverTitle(mk(Mnv.roundaboutEnter)), 'ادخل الدوّار');
    });

    test('التنفيذ يذكر الترتيب وحده — السائق عند الدوّار', () {
      final v = maneuverVoice(
          mk(Mnv.roundaboutEnter, roundaboutExit: 2), 20, 2);
      expect(v, 'ثاني مخرج');
    });
  });

  group('maneuverDetail — الشارع والحرف الصحيح', () {
    test('الانعطاف «إلى» شارع', () {
      expect(maneuverDetail(mk(10, beginStreets: ['شارع الخلد'])),
          'انعطف يمين إلى شارع الخلد');
    });

    test('الاستمرار «على» شارع — أنت فيه أصلاً', () {
      expect(maneuverDetail(mk(8, streets: ['طريق المطار للمرور السريع'])),
          'كمّل مستقيم على طريق المطار للمرور السريع');
    });

    test('اسم ما سندخله يسبق اسم ما نحن فيه', () {
      final m = mk(10,
          streets: ['الشارع القديم'], beginStreets: ['الشارع الجديد']);
      expect(maneuverDetail(m), contains('الشارع الجديد'));
      expect(maneuverDetail(m), isNot(contains('القديم')));
    });

    test('رقم المخرج يتقدّم على اسم الشارع', () {
      // على الطريق السريع اللوحة تحمل الرقم والسائق يبحث عنه بعينه
      final m = mk(20, streets: ['شارع'], exitNumber: '14');
      expect(maneuverDetail(m), contains('مخرج 14'));
    });

    test('بلا اسم شارع نرجّع الفعل وحده لا «إلى null»', () {
      // الحالة الغالبة في العراق: 8% فقط من الطرق مسمّاة في OSM
      expect(maneuverDetail(mk(10)), 'انعطف يمين');
    });
  });

  group('maneuverVoice — المراحل الثلاث', () {
    final m = mk(10, beginStreets: ['شارع الخلد']);

    test('التمهيد يبدأ بالمسافة كي يعرف السائق أنها ليست الآن', () {
      final v = maneuverVoice(m, 800, 0);
      expect(v.startsWith('بعد'), isTrue);
      expect(v, contains('شارع الخلد'));
    });

    test('التنفيذ أقصر ما يمكن وبلا مسافة', () {
      expect(maneuverVoice(m, 60, 2), 'انعطف يمين');
    });

    test('الوصول في التنفيذ جملة واحدة', () {
      expect(maneuverVoice(mk(Mnv.destination), 10, 2), 'وصلت وجهتك');
    });

    test('الوصول في التمهيد يذكر المسافة', () {
      expect(maneuverVoice(mk(Mnv.destinationRight), 500, 0),
          contains('500 متر'));
    });
  });

  group('reportAlertVoice', () {
    test('الرادار يُنطق بتنبيه لا بتسمية جافة', () {
      expect(reportAlertVoice('speed_camera', 'رادار', 600),
          'انتبه، رادار بعد 600 متر');
    });

    test('الحفرة بلا مسافة — قريبة أصلاً', () {
      expect(reportAlertVoice('pothole', 'حفرة', 100), 'حفرة قدّامك');
    });

    test('نوع ما نعرفه يستخدم تسميته من السيرفر', () {
      // أنواع البلاغات تجي من السيرفر، فقد يظهر نوع أحدث من التطبيق
      expect(reportAlertVoice('new_kind', 'شي جديد', 300),
          'شي جديد بعد 300 متر');
    });
  });

  group('arrivalLabel — 12 ساعة عربية', () {
    test('الصباح', () {
      expect(arrivalLabel(DateTime(2026, 10, 8, 9, 5)), '9:05 ص');
    });
    test('بعد الظهر', () {
      expect(arrivalLabel(DateTime(2026, 10, 8, 14, 30)), '2:30 م');
    });
    test('منتصف الليل يصير 12 لا 0', () {
      expect(arrivalLabel(DateTime(2026, 10, 8, 0, 15)), '12:15 ص');
    });
    test('الظهر يصير 12 م لا 0 م', () {
      expect(arrivalLabel(DateTime(2026, 10, 8, 12, 0)), '12:00 م');
    });
  });
}
