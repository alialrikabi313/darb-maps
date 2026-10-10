// مراحل الرحلة متعدّدة المحطات.
//
// الحالة من رد الباكند نفسه لا من فكسچر مخترع: بغداد المركز ← الجادرية
// ← المنصور، محفوظ في test/fixtures/multi_stop_trip.json كما رجع.
//
// ليش تستحق اختباراً: فهارس شكل المناورة نسبية لمرحلتها، فدمج المراحل
// في خط واحد يحتاج إزاحة. الإزاحة الخاطئة ما تنهار — تعطي مناورة تشير
// لمكان آخر على الخريطة، وهو عطل صامت يراه السائق سهماً في غير محلّه.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:darb/nav/route_model.dart';

void main() {
  final raw = File('test/fixtures/multi_stop_trip.json').readAsStringSync();
  final trip =
      (jsonDecode(raw) as Map<String, dynamic>)['trip'] as Map<String, dynamic>;
  final route = NavRoute.fromTrip(trip);

  group('مراحل الرحلة', () {
    test('ثلاث نقاط تعطي مرحلتين', () {
      expect(route.legs.length, 2);
    });

    test('مجموع أطوال المراحل = طول الرحلة', () {
      final sum = route.legs.fold<double>(0, (a, l) => a + l.lengthKm);
      // 0.05 كم تسامحاً: ڤالهالا يقرّب ملخّص الرحلة بثلاث منازل
      expect((sum - route.lengthKm).abs(), lessThan(0.05));
    });

    test('نهاية كل مرحلة داخل الخط ومرتّبة', () {
      var last = -1;
      for (final leg in route.legs) {
        expect(leg.endShapeIndex, greaterThan(last));
        expect(leg.endShapeIndex, lessThan(route.shape.length));
        last = leg.endShapeIndex;
      }
    });

    test('آخر مرحلة تنتهي عند آخر نقطة في الخط', () {
      expect(route.legs.last.endShapeIndex, route.shape.length - 1);
    });

    test('المحطة بين المرحلتين على الخط لا في مكان آخر', () {
      // الإزاحة الخاطئة تضع المحطة في وسط الخط أو خارجه. نفحص أنها
      // حيث انتهت المرحلة الأولى فعلاً، وأنها ليست البداية ولا النهاية
      final stop = route.shape[route.legs.first.endShapeIndex];
      expect(stop, isNot(route.shape.first));
      expect(stop, isNot(route.shape.last));
    });
  });

  group('مناورات الرحلة المدموجة', () {
    test('فهارس المناورات تصاعدية عبر المرحلتين', () {
      // الإزاحة الناقصة كانت تجعل أول مناورة في المرحلة الثانية ترجع
      // لفهرس صفر، فيقفز السهم لبداية الرحلة
      var last = -1;
      for (final m in route.maneuvers) {
        expect(m.beginShapeIndex, greaterThanOrEqualTo(last));
        expect(m.endShapeIndex, lessThan(route.shape.length));
        last = m.beginShapeIndex;
      }
    });

    test('بداية كل مناورة تزيد مع المسافة المقطوعة', () {
      var last = -1.0;
      for (final m in route.maneuvers) {
        expect(m.startOffsetM, greaterThanOrEqualTo(last));
        last = m.startOffsetM;
      }
    });

    test('المناورات من المرحلتين كلتيهما', () {
      final cut = route.legs.first.endShapeIndex;
      expect(route.maneuvers.any((m) => m.beginShapeIndex < cut), isTrue);
      expect(route.maneuvers.any((m) => m.beginShapeIndex >= cut), isTrue);
    });
  });
}
