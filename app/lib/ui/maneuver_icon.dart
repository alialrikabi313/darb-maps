// سهم المناورة.
//
// مرسوم لا أيقونة من خطّ: Material ما فيه «يمين حاد» ولا «ثالث مخرج من
// الدوّار»، واستعارة أيقونة قريبة تخلّي السائق يقرأ مناورة غير التي أمامه.

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../nav/route_model.dart';

class ManeuverIcon extends StatelessWidget {
  final int type;
  final int? roundaboutExit;
  final double size;
  final Color color;

  const ManeuverIcon({
    super.key,
    required this.type,
    this.roundaboutExit,
    this.size = 44,
    this.color = Colors.white,
  });

  @override
  Widget build(BuildContext context) {
    if (type == Mnv.roundaboutEnter || type == Mnv.roundaboutExit) {
      return CustomPaint(
        size: Size.square(size),
        painter: _RoundaboutPainter(color, roundaboutExit),
      );
    }

    final uturn = _isUturn(type);
    return CustomPaint(
      size: Size.square(size),
      painter: _ArrowPainter(
          color,
          uturn ? _uturnSide(type) : _turnAngle(type),
          uturn,
          _isMerge(type)),
    );
  }

  /// زاوية الانعطاف بالدرجات: سلبية يسار، موجبة يمين، صفر مستقيم.
  static double _turnAngle(int t) {
    switch (t) {
      case Mnv.slightRight:
      case Mnv.rampRight:
      case Mnv.exitRight:
      case Mnv.stayRight:
        return 30;
      case Mnv.right:
        return 75;
      case Mnv.sharpRight:
        return 115;
      case Mnv.slightLeft:
      case Mnv.rampLeft:
      case Mnv.exitLeft:
      case Mnv.stayLeft:
        return -30;
      case Mnv.left:
        return -75;
      case Mnv.sharpLeft:
        return -115;
      default:
        return 0;
    }
  }

  static bool _isUturn(int t) =>
      t == Mnv.uturnLeft || t == Mnv.uturnRight;

  /// جهة الالتفاف: سالب يسار، موجب يمين — يقرأها رسّام حرف U
  static double _uturnSide(int t) => t == Mnv.uturnRight ? 1 : -1;

  static bool _isMerge(int t) =>
      t == Mnv.merge || t == Mnv.mergeLeft || t == Mnv.mergeRight;
}

class _ArrowPainter extends CustomPainter {
  final Color color;
  final double angleDeg;
  final bool uturn;
  final bool merge;

  _ArrowPainter(this.color, this.angleDeg, this.uturn, this.merge);

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final stroke = w * 0.16;

    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final path = Path();

    if (uturn) {
      // ساق صاعد، نصف دائرة، ثم نزول — شكل حرف U مقلوب.
      // الجهة تتبع نوع المناورة: uturnRight و uturnLeft كانا يُرسمان
      // شكلاً واحداً يلتفّ يساراً
      final toLeft = angleDeg <= 0;
      final up = toLeft ? w * 0.68 : w * 0.32;
      final down = toLeft ? w * 0.32 : w * 0.68;

      path.moveTo(up, h * 0.9);
      path.lineTo(up, h * 0.42);
      path.arcToPoint(Offset(down, h * 0.42),
          radius: Radius.circular(w * 0.18), clockwise: !toLeft);
      path.lineTo(down, h * 0.62);
      canvas.drawPath(path, paint);
      _arrowHead(canvas, paint, Offset(down, h * 0.62), 180, w);
      return;
    }

    // الساق يبدأ من أسفل الوسط — موضع السيارة
    final stemX = w * 0.5;
    path.moveTo(stemX, h * 0.92);

    if (angleDeg.abs() < 1) {
      path.lineTo(stemX, h * 0.2);
      canvas.drawPath(path, paint);
      _arrowHead(canvas, paint, Offset(stemX, h * 0.2), 0, w);
      return;
    }

    final right = angleDeg > 0;
    final sharp = angleDeg.abs() > 100;

    // الساق حتى نقطة الانعطاف، ثم منحنى، ثم ذراع في الاتجاه الجديد
    final turnY = sharp ? h * 0.52 : h * 0.46;
    path.lineTo(stemX, turnY);

    final armLen = w * (sharp ? 0.26 : 0.3);
    final rad = angleDeg * math.pi / 180.0;
    // الاتجاه الجديد: صفر = لأعلى، فندور حوله
    final dx = math.sin(rad) * armLen;
    final dy = -math.cos(rad) * armLen;
    final tip = Offset(stemX + dx, turnY + dy);

    // نقطة تحكّم عند الزاوية تعطي منحنى مستدير لا كسرة حادة
    path.quadraticBezierTo(
      stemX + (right ? w * 0.06 : -w * 0.06),
      turnY - h * 0.06,
      tip.dx,
      tip.dy,
    );
    canvas.drawPath(path, paint);
    _arrowHead(canvas, paint, tip, angleDeg, w);

    if (merge) {
      // خط منقّط قصير يمثّل المسار الذي ندمج فيه
      final dash = Paint()
        ..color = color.withValues(alpha: 0.45)
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke * 0.6
        ..strokeCap = StrokeCap.round;
      final mx = right ? w * 0.82 : w * 0.18;
      for (var y = h * 0.2; y < h * 0.5; y += h * 0.12) {
        canvas.drawLine(Offset(mx, y), Offset(mx, y + h * 0.06), dash);
      }
    }
  }

  /// رأس السهم: خطّان من الطرف بزاوية حول اتجاه السير.
  void _arrowHead(Canvas canvas, Paint paint, Offset tip, double angleDeg,
      double w) {
    final len = w * 0.22;
    final rad = angleDeg * math.pi / 180.0;

    for (final spread in [140.0, -140.0]) {
      final a = rad + spread * math.pi / 180.0;
      canvas.drawLine(
        tip,
        Offset(tip.dx + math.sin(a) * len, tip.dy - math.cos(a) * len),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_ArrowPainter old) =>
      old.color != color || old.angleDeg != angleDeg ||
      old.uturn != uturn || old.merge != merge;
}

class _RoundaboutPainter extends CustomPainter {
  final Color color;
  final int? exitNumber;

  _RoundaboutPainter(this.color, this.exitNumber);

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.13
      ..strokeCap = StrokeCap.round;

    final c = Offset(w * 0.5, h * 0.44);
    final r = w * 0.24;

    // حلقة الدوّار مفتوحة من الأسفل — من هناك ندخل
    canvas.drawArc(Rect.fromCircle(center: c, radius: r),
        math.pi * 0.35, math.pi * 1.65, false, paint);

    // ساق الدخول
    canvas.drawLine(Offset(w * 0.5, h * 0.95),
        Offset(w * 0.5, c.dy + r), paint);

    // ذراع الخروج: زاويته من رقم المخرج.
    //
    // الخطوة كانت 0.42π فالمخرج الثاني يقع عند −61° (أسفل-يمين) أي
    // **خلف** السائق، والثالث عند −137°. فكل مخرج غير الأول كان يُرسم
    // مشيراً للجهة التي جاء منها — في أهمّ مناورة بُني هذا الرسّام لأجلها.
    //
    // 0.5π/خطوة توزّع المخارج على الربع الأيمن فالأعلى فالأيسر:
    // الأول يمين (0°)، الثاني أمام (90°)، الثالث يسار (180°) — وهو
    // ترتيب الدوّار الفعلي في السير على اليمين
    final n = (exitNumber ?? 2).clamp(1, 5);
    final angle = (n - 1) * math.pi * 0.5 - math.pi * 0.0;

    // 1.7r لا 2.2r: الطرف كان يخرج من مربّع الرسم ومن الدائرة
    // النعناعية حوله بلا قصّ
    final tip = Offset(c.dx + math.cos(angle) * r * 1.7,
        c.dy - math.sin(angle) * r * 1.7);

    canvas.drawLine(
        Offset(c.dx + math.cos(angle) * r, c.dy - math.sin(angle) * r),
        tip, paint);

    final head = w * 0.18;
    for (final spread in [0.75, -0.75]) {
      final a = angle + math.pi + spread;
      canvas.drawLine(tip,
          Offset(tip.dx + math.cos(a) * head, tip.dy - math.sin(a) * head),
          paint);
    }
  }

  @override
  bool shouldRepaint(_RoundaboutPainter old) =>
      old.color != color || old.exitNumber != exitNumber;
}
