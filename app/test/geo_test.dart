// اختبارات الحساب الجغرافي.
//
// كل حالة من بيانات بغداد الفعلية أو من سلوك صادفناه، لا من أرقام
// مخترَعة: الإسقاط على الخط والعبور حول 360 هما مصدر كل خلل رأيناه في
// مطابقة المسار.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

import 'package:darb/core/geo.dart';

void main() {
  group('metersBetween', () {
    test('ساحة التحرير ← مطار بغداد ≈ 18 كم هوائياً', () {
      // المسار بالسيارة 24.2 كم (قِسناه بـValhalla)، والهوائي أقصر
      const tahrir = LatLng(33.3074, 44.4009);
      const airport = LatLng(33.2625, 44.2346);

      final d = metersBetween(tahrir, airport);
      expect(d, closeTo(16500, 1500));
    });

    test('نقطتان متطابقتان تعطيان صفراً', () {
      const p = LatLng(33.3074, 44.4009);
      expect(metersBetween(p, p), 0);
    });
  });

  group('smoothHeading', () {
    test('العبور من 350 إلى 10 يمرّ بـ360 لا بـ180', () {
      // هذي الحالة التي كسرت التنعيم الساذج: السيارة متّجهة شمالاً
      // والدمج الخطّي يدوّر الخريطة دورة كاملة عند كل مرور
      final out = smoothHeading(350, 10, 0.5);
      expect(out, closeTo(0, 1));
    });

    test('العبور من 10 إلى 350 يرجع للخلف لا للأمام', () {
      final out = smoothHeading(10, 350, 0.5);
      expect(out, closeTo(0, 1));
    });

    test('بلا عبور يتصرّف كدمج خطّي عادي', () {
      expect(smoothHeading(100, 140, 0.5), closeTo(120, 0.5));
    });

    test('المخرج يبقى داخل [0,360)', () {
      for (final pair in [(0.0, 180.0), (359.0, 1.0), (180.0, 0.0)]) {
        final out = smoothHeading(pair.$1, pair.$2, 0.25);
        expect(out, greaterThanOrEqualTo(0));
        expect(out, lessThan(360));
      }
    });
  });

  group('projectOnSegment', () {
    test('نقطة فوق منتصف القطعة تُسقط على منتصفها', () {
      const a = LatLng(33.30, 44.40);
      const b = LatLng(33.30, 44.41);
      const p = LatLng(33.3005, 44.405); // ~55م شمال المنتصف

      final pr = projectOnSegment(p, a, b);
      expect(pr.t, closeTo(0.5, 0.05));
      expect(pr.distanceM, closeTo(55, 10));
    });

    test('نقطة خلف بداية القطعة تُحجَز عند t=0', () {
      const a = LatLng(33.30, 44.40);
      const b = LatLng(33.30, 44.41);
      const p = LatLng(33.30, 44.39);

      expect(projectOnSegment(p, a, b).t, 0.0);
    });

    test('قطعة منعدمة الطول لا تقسم على صفر', () {
      // تحدث فعلاً في خطوط Valhalla: نقطة تتكرّر عند وصل رحلتين
      const a = LatLng(33.30, 44.40);
      final pr = projectOnSegment(const LatLng(33.31, 44.40), a, a);
      expect(pr.t, 0.0);
      expect(pr.distanceM, closeTo(1113, 50));
    });
  });

  group('projectOnLine', () {
    final line = [
      const LatLng(33.300, 44.400),
      const LatLng(33.310, 44.400),
      const LatLng(33.310, 44.410),
    ];

    test('المسافة المقطوعة تُحسب على الخط لا هوائياً', () {
      // النقطة عند نهاية الخط: المقطوع = طول القطعتين
      final pr = projectOnLine(line.last, line);
      expect(pr.traveledM, closeTo(lineLength(line), 1));
    });

    test('searchFrom يمنع القفز لمرور سابق على نفس الشارع', () {
      // الحالة: مسار يرجع على نفسه (دوران حول مجمّع). بلا searchFrom
      // يُسقط الموقع على المرور الأول فيظن المحرّك أن السائق رجع للخلف
      final loop = [
        const LatLng(33.300, 44.400),
        const LatLng(33.310, 44.400),
        const LatLng(33.310, 44.410),
        const LatLng(33.300, 44.410),
        const LatLng(33.300, 44.400), // رجعنا لنقطة البداية
      ];

      const nearStart = LatLng(33.3005, 44.4001);

      final naive = projectOnLine(nearStart, loop);
      final guided = projectOnLine(nearStart, loop, searchFrom: 3);

      expect(naive.segmentIndex, 0);
      expect(guided.segmentIndex, 3);
      expect(guided.traveledM, greaterThan(naive.traveledM));
    });
  });

  group('decodePolyline6', () {
    // الفِكسچر خطّ حقيقي رجّعه Valhalla لمسار ساحة التحرير ← المنصور
    // على رسم بغداد. محفوظ في test/fixtures/ لا مكتوباً هنا لأنه 667
    // حرفاً، ولأنه بيانات لا كود
    late String encoded;

    setUpAll(() {
      encoded = File('test/fixtures/tahrir_to_mansour.polyline6.txt')
          .readAsStringSync()
          .trim();
    });

    test('النقطة الأولى في ساحة التحرير والأخيرة في المنصور', () {
      final pts = decodePolyline6(encoded);

      expect(pts.length, 159);
      expect(pts.first.latitude, closeTo(33.3074, 0.001));
      expect(pts.first.longitude, closeTo(44.4010, 0.001));
      expect(pts.last.latitude, closeTo(33.3093, 0.001));
      expect(pts.last.longitude, closeTo(44.3381, 0.001));
    });

    test('القاسم 1e6: بـ1e5 تخرج الإحداثيات عن نطاقها أصلاً', () {
      // هذا جوهر الفرق بين polyline5 و polyline6. فكّ نفس السلسلة
      // بـ1e5 يعطي 333° عرضاً — رقم مستحيل. فلو انقلب القاسم يوماً
      // يسقط هذا الاختبار فوراً لا بعد ما يلاحظ أحد أن الخط في المحيط
      for (final p in decodePolyline6(encoded)) {
        expect(p.latitude.abs(), lessThanOrEqualTo(90));
        expect(p.longitude.abs(), lessThanOrEqualTo(180));
      }
    });

    test('الطول المفكوك يطابق ملخّص ڤالهالا (7.56 كم)', () {
      final pts = decodePolyline6(encoded);
      expect(lineLength(pts) / 1000, closeTo(7.56, 0.2));
    });

    test('نصّ فارغ يعطي قائمة فارغة لا استثناء', () {
      expect(decodePolyline6(''), isEmpty);
    });
  });

  group('lineFrom', () {
    test('القصّ من منتصف الخط يُبقي النصف الثاني', () {
      final line = [
        const LatLng(33.300, 44.400),
        const LatLng(33.310, 44.400),
      ];
      final total = lineLength(line);
      final cut = lineFrom(line, total / 2);

      expect(lineLength(cut), closeTo(total / 2, 2));
      expect(cut.last.latitude, closeTo(33.310, 1e-9));
    });

    test('القصّ من صفر يرجّع الخط كاملاً', () {
      final line = [
        const LatLng(33.300, 44.400),
        const LatLng(33.310, 44.400),
      ];
      expect(lineFrom(line, 0).length, line.length);
    });
  });
}
