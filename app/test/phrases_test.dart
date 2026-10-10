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

  landmarkTests();

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

// ── التعليمة بالمعلم ───────────────────────────────────────────────────────
//
// 9% فقط من طرق العراق مسمّاة. قِسنا على خمسة مسارات في خمس مدن:
// التعليمات التي فيها اسم شارع 46%، وبإضافة المعالم 83%. فهذا المنطق
// يحمل نصف ما يُنطق للسائق.

void landmarkTests() {
  group('maneuverDetail بالمعلم', () {
    test('اسم الشارع يتقدّم على المعلم حين يوجد', () {
      final m = mk(10, beginStreets: ['شارع الخلد']);
      final out = maneuverDetail(m,
          landmark: const Landmark('محطة وقود النصر'));
      expect(out, 'انعطف يمين إلى شارع الخلد');
      expect(out, isNot(contains('محطة')));
    });

    test('بلا اسم شارع يحمل المعلم التعليمة', () {
      expect(
        maneuverDetail(mk(10), landmark: const Landmark('جامع الكاظمية')),
        'انعطف يمين عند جامع الكاظمية',
      );
    });

    test('المعلم قبل المناورة يأخذ «بعد»', () {
      // الفرق يهمّ السائق: «بعد المحطة انعطف» غير «انعطف عند المحطة»
      expect(
        maneuverDetail(mk(15),
            landmark: const Landmark('محطة الوقود', where: LandmarkWhere.before)),
        'انعطف يسار بعد محطة الوقود',
      );
    });

    test('بلا شارع ولا معلم يرجّع الفعل وحده لا نصّاً مكسوراً', () {
      expect(maneuverDetail(mk(10)), 'انعطف يمين');
    });

    test('رقم المخرج يتقدّم على المعلم', () {
      final m = mk(20, exitNumber: '14');
      expect(maneuverDetail(m, landmark: const Landmark('مول بغداد')),
          contains('مخرج 14'));
    });

    test('الوصول بمعلم يطمئن السائق أنه في المكان الصحيح', () {
      expect(
        maneuverDetail(mk(Mnv.destination),
            landmark: const Landmark('مستشفى اليرموك')),
        'وصلت — وجهتك عند مستشفى اليرموك',
      );
    });
  });

  group('maneuverVoice بالمعلم', () {
    test('التمهيد يذكر المسافة ثم المعلم', () {
      expect(
        maneuverVoice(mk(10), 500, 0,
            landmark: const Landmark('محطة وقود النصر')),
        'بعد 500 متر، انعطف يمين عند محطة وقود النصر',
      );
    });

    test('التنفيذ يُبقي المعلم حين لا اسم شارع', () {
      // «انعطف يمين» وحدها عند تقاطع مزدوج تترك السائق يحزر
      expect(
        maneuverVoice(mk(10), 50, 2, landmark: const Landmark('الجامع')),
        'انعطف يمين عند الجامع',
      );
    });

    test('التنفيذ يسقط المعلم حين يوجد اسم شارع', () {
      // الجملة عند التقاطع لازم تكون أقصر ما يمكن
      expect(
        maneuverVoice(mk(10, beginStreets: ['شارع الخلد']), 50, 2,
            landmark: const Landmark('الجامع')),
        'انعطف يمين',
      );
    });

    test('ما نجمع اسم الشارع والمعلم في جملة واحدة', () {
      // جملة فيها الاثنان أطول من أن تُسمع قبل التقاطع
      final out = maneuverVoice(mk(10, beginStreets: ['شارع الخلد']), 500, 0,
          landmark: const Landmark('جامع الكاظمية'));
      expect(out, contains('شارع الخلد'));
      expect(out, isNot(contains('جامع')));
    });

    test('الوصول بمعلم', () {
      expect(
        maneuverVoice(mk(Mnv.destination), 10, 2,
            landmark: const Landmark('مقهى الزهاوي')),
        'وصلت وجهتك عند مقهى الزهاوي',
      );
    });

    test('الدوّار يبقى بترتيب المخرج لا بالمعلم', () {
      expect(
        maneuverVoice(mk(Mnv.roundaboutEnter, roundaboutExit: 3), 20, 2,
            landmark: const Landmark('النصب')),
        'ثالث مخرج',
      );
    });
  });

  group('Landmark', () {
    test('حرف الجرّ يتبع الموضع', () {
      expect(const Landmark('س').preposition, 'عند');
      expect(const Landmark('س', where: LandmarkWhere.before).preposition, 'بعد');
      expect(const Landmark('س', where: LandmarkWhere.after).preposition, 'قبل');
    });
  });
}
