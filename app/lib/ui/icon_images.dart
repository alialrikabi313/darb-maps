// تحويل أيقونات Material إلى صور نسجّلها في نمط MapLibre.
//
// ليش هذا التعقيد: علامات البلاغات لازم تتحرك مع الخريطة بلا تأخّر. لو
// رسمناها widgets فوق الخريطة وأسقطنا إحداثياتها للشاشة، لازم نعيد
// الإسقاط كل إطار — وهو ما يصير إلا على onCameraIdle، فتتخلّف العلامات
// عن الخريطة أثناء السحب وتبدو كأنها تطفو.
//
// الحل: نرسم الأيقونة مرة صورةً، ونسجّلها في النمط، فترسمها البطاقة
// الرسومية مع البلاطات نفسها. لا سبريت جاهز نشحنه، ولا تأخّر.

import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

import '../reports/reports.dart';

/// اسم الصورة في النمط لنوع بلاغ.
String reportImageName(String kind) => 'darb-report-$kind';

const String carImageName = 'darb-car';

/// يسجّل صور كل أنواع البلاغات وسهم السيارة في النمط.
///
/// تُنادى بعد onStyleLoaded وقبل إضافة أي symbol: الرمز الذي يشير لصورة
/// غير مسجّلة لا يُرسم ولا يرمي خطأ، فتختفي العلامات بصمت.
Future<void> registerMapImages(
    MapLibreMapController c, List<String> kinds, double devicePixelRatio) async {
  for (final kind in kinds) {
    final look = lookFor(kind);
    final bytes = await _renderPin(look.icon, look.color, devicePixelRatio);
    await c.addImage(reportImageName(kind), bytes);
  }

  await c.addImage(carImageName, await _renderCar(devicePixelRatio));
}

/// يرسم دبّوساً: دائرة ملوّنة بحاشية بيضاء وذيل، والأيقونة في وسطها.
///
/// الحاشية البيضاء ليست تجميلاً: الخريطة فيها مناطق فاتحة وغامقة، وبلاها
/// يختفي الدبّوس الأحمر على مبنى أحمر.
Future<Uint8List> _renderPin(
    IconData icon, Color color, double dpr) async {
  // 44 منطقي — الحجم المريح للمس. نضربه في كثافة الشاشة كي لا يظهر مهشّماً
  const logical = 44.0;
  const tail = 10.0;
  final w = (logical * dpr).round();
  final h = ((logical + tail) * dpr).round();

  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.scale(dpr);

  const r = logical / 2;
  const center = Offset(r, r);

  // الذيل مثلث يشير للموقع الفعلي: الدائرة وحدها تخلّي المستخدم يحدس
  // أين البلاغ بالضبط
  final tailPath = Path()
    ..moveTo(r - 7, logical - 6)
    ..lineTo(r, logical + tail - 1)
    ..lineTo(r + 7, logical - 6)
    ..close();

  canvas.drawPath(tailPath, Paint()..color = Colors.white);
  canvas.drawCircle(center, r - 1, Paint()..color = Colors.white);
  canvas.drawPath(
      tailPath,
      Paint()
        ..color = color
        ..strokeWidth = 0);
  canvas.drawCircle(center, r - 3.5, Paint()..color = color);

  final tp = TextPainter(
    text: TextSpan(
      text: String.fromCharCode(icon.codePoint),
      style: TextStyle(
        fontSize: logical * 0.5,
        fontFamily: icon.fontFamily,
        package: icon.fontPackage,
        color: Colors.white,
      ),
    ),
    textDirection: TextDirection.ltr,
  )..layout();
  tp.paint(canvas, center - Offset(tp.width / 2, tp.height / 2));

  return _toPng(recorder, w, h);
}

/// سهم السيارة: مثلث أزرق بحاشية بيضاء يدور مع الاتجاه.
Future<Uint8List> _renderCar(double dpr) async {
  const logical = 40.0;
  final side = (logical * dpr).round();

  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.scale(dpr);

  const c = Offset(logical / 2, logical / 2);

  // هالة شفافة حول السهم: تفصله عن الطريق الأبيض تحته
  canvas.drawCircle(c, logical * 0.46,
      Paint()..color = const Color(0x332D7FF9));

  // السهم يشير لأعلى، وMapLibre يدوّره بزاوية الاتجاه
  final arrow = Path()
    ..moveTo(c.dx, logical * 0.1)
    ..lineTo(logical * 0.82, logical * 0.86)
    ..lineTo(c.dx, logical * 0.66)
    ..lineTo(logical * 0.18, logical * 0.86)
    ..close();

  canvas.drawPath(
      arrow,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4
        ..strokeJoin = StrokeJoin.round);
  canvas.drawPath(arrow, Paint()..color = const Color(0xFF2D7FF9));

  return _toPng(recorder, side, side);
}

Future<Uint8List> _toPng(ui.PictureRecorder recorder, int w, int h) async {
  final img = await recorder.endRecording().toImage(w, h);
  final data = await img.toByteData(format: ui.ImageByteFormat.png);
  img.dispose();

  if (data == null) {
    // ما صادفناه، لكن لو صار تختفي العلامات بصمت — فنموت برسالة واضحة
    throw StateError('فشل ترميز أيقونة الخريطة إلى PNG');
  }
  return data.buffer.asUint8List();
}
