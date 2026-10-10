// نظام التصميم — مستخرَج من مرئيات المشروع (٩ شاشات).
//
// كل لون ونصف قطر وظل هنا مقروء من التصميم لا مخترَع. أي شاشة تكتب لوناً
// بيدها تفترق عن البقية بعد أول تعديل، فالقاعدة: لا Color حرفي خارج هذا
// الملف إلا ألوان الخريطة في darb-day.json.

import 'package:flutter/material.dart';

import '../config.dart';

class D {
  D._();

  // ── الألوان ──────────────────────────────────────────────────────────────

  /// خلفية الصفحة: نعناعي فاتح. ما هي بيضاء — البياض محجوز للبطاقات،
  /// والتباين بينهما هو ما يجعلها تطفو
  static const bg = Color(0xFFE6F2EC);

  /// سطح البطاقة
  static const card = Color(0xFFFFFFFF);

  /// بطاقة داخل بطاقة (صفوف القوائم): أفتح من الخلفية وأغمق من البطاقة
  static const cardInner = Color(0xFFF4FAF7);

  /// الأخضر النعناعي للعناصر النشطة: الزرّ الأساسي، الشريحة المختارة،
  /// خط المسار
  static const mint = Color(0xFF8FE3B8);
  static const mintLight = Color(0xFFD6F0E3);
  static const mintPale = Color(0xFFEAF7F1);

  /// الأخضر الغامق: الأيقونات على خلفية نعناعية، ونصّ التأكيد
  static const green = Color(0xFF17A06B);
  static const greenDeep = Color(0xFF0E7A51);

  /// الأسود: الأزرار الحاسمة («ابدأ الرحلة»، «اتجاهات») وعلامات الوجهة.
  /// ليس أسود صافياً — الأسود الصافي يبدو ثقباً على خلفية فاتحة
  static const ink = Color(0xFF0C1512);

  static const text = Color(0xFF0F1A16);
  static const textSoft = Color(0xFF7E8F89);
  static const textFaint = Color(0xFFA8B6B0);

  static const divider = Color(0xFFE4EDE8);

  // حالات المرور تُقرأ من Cfg لا تُكتب هنا. كانت منسوخة بقيم أفتح،
  // فخطّ الزحام على الخريطة يطلع بلون والشريحة اللي تشرحه بلون ثانٍ
  static final trafficFree = trafficColor('free');
  static final trafficMid = trafficColor('moderate');
  static final trafficHeavy = trafficColor('heavy');
  static final trafficJam = trafficColor('jam');

  static Color trafficColor(String level) =>
      Color(Cfg.trafficColors[level] ?? Cfg.trafficColors['free']!);

  static const danger = Color(0xFFEF4444);
  static const warn = Color(0xFFF59E0B);
  static const info = Color(0xFF3B82F6);

  // شريط التنبيه وصندوق الخطأ. كانت هذه الستة منسوخة بيدها في خمسة
  // ملفات، فتعديل درجة الأصفر في مكان يترك الباقي خلفه
  static const noticeBg = Color(0xFFFFF6E2);
  static const noticeInk = Color(0xFF7A5A14);
  static const noticeIcon = Color(0xFF8A6418);

  static const errorBg = Color(0xFFFDECEC);
  static const errorInk = Color(0xFF8E2121);
  static const errorTint = Color(0xFFFDE7E7);

  /// أزرق نقطة الموقع. ما هو من لوحة التصميم بقصد: هو العرف العالمي
  /// لـ«أنت هنا»، وصبغه بالنعناعي يخلّيه يذوب في خط المسار
  static const locationBlue = Color(0xFF2D7FF9);
  static const locationHalo = Color(0x332D7FF9);

  // ── نصف الأقطار ──────────────────────────────────────────────────────────

  /// الشرائح وأشرطة البحث: كبسولة كاملة
  static const rPill = 999.0;
  static const rCard = 24.0;
  static const rInner = 18.0;
  static const rSheet = 30.0;
  static const rTile = 20.0;

  // ── الظلال ───────────────────────────────────────────────────────────────

  /// ظل البطاقة العائمة فوق الخريطة. واسع وخفيف — الظل الضيق الغامق
  /// يعطي مظهراً صلباً لا يشبه التصميم
  static const List<BoxShadow> shadow = [
    BoxShadow(color: Color(0x14000000), blurRadius: 20, offset: Offset(0, 6)),
    BoxShadow(color: Color(0x0A000000), blurRadius: 6, offset: Offset(0, 2)),
  ];

  static const List<BoxShadow> shadowSoft = [
    BoxShadow(color: Color(0x0F000000), blurRadius: 12, offset: Offset(0, 3)),
  ];

  /// هالة حول الزرّ النعناعي الكبير — تُرى في «ابدأ» و«اذهب»
  static const List<BoxShadow> glowMint = [
    BoxShadow(color: Color(0x4D8FE3B8), blurRadius: 24, offset: Offset(0, 8)),
  ];

  // ── النصوص ───────────────────────────────────────────────────────────────

  static const h1 = TextStyle(
      fontSize: 22, fontWeight: FontWeight.w700, color: text, height: 1.3);
  static const h2 = TextStyle(
      fontSize: 18, fontWeight: FontWeight.w700, color: text, height: 1.3);
  static const h3 = TextStyle(
      fontSize: 15, fontWeight: FontWeight.w700, color: text, height: 1.35);

  /// الأرقام الكبيرة: المدة والمسافة والسرعة. أثقل من العناوين لأنها
  /// تُقرأ بطرف العين أثناء السياقة
  static const num1 = TextStyle(
      fontSize: 28, fontWeight: FontWeight.w800, color: text, height: 1.1);
  static const num2 = TextStyle(
      fontSize: 20, fontWeight: FontWeight.w800, color: text, height: 1.15);

  static const body = TextStyle(fontSize: 14, color: text, height: 1.4);
  static const bodySoft =
      TextStyle(fontSize: 13, color: textSoft, height: 1.4);
  static const caption =
      TextStyle(fontSize: 11.5, color: textSoft, height: 1.35);

  static ThemeData theme() {
    final base = ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: green,
        primary: green,
        surface: card,
      ),
      scaffoldBackgroundColor: bg,
    );

    return base.copyWith(
      textTheme: base.textTheme.apply(bodyColor: text, displayColor: text),
      splashFactory: InkRipple.splashFactory,
      dividerTheme: const DividerThemeData(color: divider, thickness: 1),
    );
  }
}

// ── عناصر متكرّرة ───────────────────────────────────────────────────────────

/// بطاقة بيضاء عائمة — أساس كل شيء في هذا التصميم.
class DCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;
  final Color color;
  final List<BoxShadow> shadow;
  final VoidCallback? onTap;
  final Border? border;

  const DCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(14),
    this.radius = D.rCard,
    this.color = D.card,
    this.shadow = D.shadow,
    this.onTap,
    this.border,
  });

  @override
  Widget build(BuildContext context) {
    final r = BorderRadius.circular(radius);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color,
        borderRadius: r,
        boxShadow: shadow,
        border: border,
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: r,
        child: InkWell(
          onTap: onTap,
          borderRadius: r,
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
  }
}

/// دائرة أيقونة بخلفية نعناعية باهتة — تتكرّر في كل بطاقة تقريباً.
class DIconCircle extends StatelessWidget {
  final IconData icon;
  final double size;
  final Color background;
  final Color foreground;

  const DIconCircle(
    this.icon, {
    super.key,
    this.size = 40,
    this.background = D.mintLight,
    this.foreground = D.text,
  });

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(color: background, shape: BoxShape.circle),
        child: Icon(icon, size: size * 0.5, color: foreground),
      );
}

/// زرّ دائري أبيض عائم فوق الخريطة (طبقات، صوت، تحديد الموقع).
class DMapButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;
  final String tooltip;
  final Color? background;
  final Color? foreground;
  final double size;

  const DMapButton({
    super.key,
    required this.icon,
    required this.onTap,
    required this.tooltip,
    this.background,
    this.foreground,
    this.size = 46,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: background ?? D.card,
          shape: BoxShape.circle,
          boxShadow: D.shadow,
        ),
        child: Material(
          color: Colors.transparent,
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: Icon(icon,
                size: size * 0.46, color: foreground ?? D.text),
          ),
        ),
      ),
    );
  }
}

/// شريحة كبسولة — صفوف التصنيفات وأزرار الاختصار.
class DChip extends StatelessWidget {
  final IconData? icon;
  final String label;
  final bool selected;
  final VoidCallback? onTap;

  const DChip({
    super.key,
    required this.label,
    this.icon,
    this.selected = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return DCard(
      radius: D.rPill,
      color: selected ? D.mint : D.card,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      shadow: selected ? D.shadow : D.shadowSoft,
      onTap: onTap,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label,
              style: D.body.copyWith(
                  fontWeight: FontWeight.w600,
                  color: selected ? D.greenDeep : D.text)),
          if (icon != null) ...[
            const SizedBox(width: 8),
            DIconCircle(icon!,
                size: 28,
                background: selected ? Colors.white : D.mintLight,
                foreground: selected ? D.greenDeep : D.text),
          ],
        ],
      ),
    );
  }
}

/// الزرّ الأساسي الكبير. أسود للحسم («ابدأ الرحلة»، «اتجاهات»)، ونعناعي
/// للمتابعة اللينة («ابدأ») — كما في التصميم.
class DBigButton extends StatelessWidget {
  final String label;
  final String? subtitle;
  final IconData? icon;
  final VoidCallback? onTap;
  final bool dark;

  const DBigButton({
    super.key,
    required this.label,
    this.subtitle,
    this.icon,
    this.onTap,
    this.dark = true,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    final fg = dark ? Colors.white : D.greenDeep;

    return Opacity(
      opacity: enabled ? 1 : 0.5,
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          color: dark ? D.ink : D.mint,
          borderRadius: BorderRadius.circular(D.rPill),
          boxShadow: dark ? D.shadow : D.glowMint,
        ),
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(D.rPill),
          child: InkWell(
            borderRadius: BorderRadius.circular(D.rPill),
            onTap: onTap,
            child: Padding(
              padding: EdgeInsets.symmetric(
                  vertical: subtitle == null ? 17 : 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(label,
                          style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w700,
                              color: fg)),
                      if (subtitle != null)
                        Text(subtitle!,
                            style: TextStyle(
                                fontSize: 12,
                                color: fg.withValues(alpha: 0.75))),
                    ],
                  ),
                  if (icon != null) ...[
                    const SizedBox(width: 10),
                    Icon(icon, color: fg, size: 20),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// عنوان قسم: نصّ عريض + دائرة أيقونة صغيرة، ورابط اختياري يساره.
class DSectionHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  final IconData icon;
  final String? actionLabel;
  final VoidCallback? onAction;

  const DSectionHeader({
    super.key,
    required this.title,
    required this.icon,
    this.subtitle,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        DIconCircle(icon, size: 30, foreground: D.green),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: D.h2),
              if (subtitle != null)
                Text(subtitle!, style: D.caption),
            ],
          ),
        ),
        if (actionLabel != null)
          TextButton(
            onPressed: onAction,
            style: TextButton.styleFrom(
                foregroundColor: D.textSoft,
                visualDensity: VisualDensity.compact),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(actionLabel!, style: D.bodySoft),
                const Icon(Icons.chevron_left, size: 18),
              ],
            ),
          ),
      ],
    );
  }
}

/// مقبض السحب أعلى الأوراق السفلية.
class DGrabber extends StatelessWidget {
  const DGrabber({super.key});

  @override
  Widget build(BuildContext context) => Center(
        child: Container(
          width: 46,
          height: 4.5,
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            color: D.divider,
            borderRadius: BorderRadius.circular(3),
          ),
        ),
      );
}

/// مبدّل شرائح داخل كبسولة: المختار كبسولة داكنة، كما في «الآن / لاحقاً».
class DSegmented extends StatelessWidget {
  final List<String> labels;
  final int selected;
  final ValueChanged<int> onPick;

  const DSegmented({
    super.key,
    required this.labels,
    required this.selected,
    required this.onPick,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: D.cardInner,
        borderRadius: BorderRadius.circular(D.rPill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < labels.length; i++)
            GestureDetector(
              onTap: () => onPick(i),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                padding:
                    const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
                decoration: BoxDecoration(
                  color: i == selected ? D.ink : Colors.transparent,
                  borderRadius: BorderRadius.circular(D.rPill),
                ),
                child: Text(
                  labels[i],
                  style: D.body.copyWith(
                    fontWeight: FontWeight.w700,
                    color: i == selected ? Colors.white : D.textSoft,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// دائرة الاختيار في قوائم الخيارات الحصرية (المسارات، أنماط المركبة).
class DRadio extends StatelessWidget {
  final bool selected;
  final double size;

  const DRadio({super.key, required this.selected, this.size = 24});

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: selected ? D.green : Colors.transparent,
          border:
              Border.all(color: selected ? D.green : D.divider, width: 2),
        ),
        child: selected
            ? Center(
                child: Icon(Icons.circle,
                    size: size * 0.33, color: Colors.white))
            : null,
      );
}

/// مصغّرة المسار داخل بطاقة الخيار.
///
/// رسم يدوي لا صورة بلاطات: البلاطات تحتاج خريطة ثانية لكل بطاقة، وثلاث
/// خرائط في ورقة واحدة تأكل الذاكرة وتتأخّر. والخط وحده هو ما يميّز
/// المسارات عن بعضها في التصميم أصلاً.
class DRouteThumb extends StatelessWidget {
  final List<({double lat, double lon})> shape;
  final bool selected;
  final double width;
  final double height;

  const DRouteThumb({
    super.key,
    required this.shape,
    required this.selected,
    this.width = 92,
    this.height = 56,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: Container(
        width: width,
        height: height,
        color: selected ? D.mintPale : D.cardInner,
        child: CustomPaint(
          painter: _ThumbPainter(shape, selected ? D.green : D.textFaint),
        ),
      ),
    );
  }
}

class _ThumbPainter extends CustomPainter {
  final List<({double lat, double lon})> shape;
  final Color color;

  _ThumbPainter(this.shape, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    if (shape.length < 2) return;

    var minLat = shape.first.lat, maxLat = minLat;
    var minLon = shape.first.lon, maxLon = minLon;
    for (final p in shape) {
      if (p.lat < minLat) minLat = p.lat;
      if (p.lat > maxLat) maxLat = p.lat;
      if (p.lon < minLon) minLon = p.lon;
      if (p.lon > maxLon) maxLon = p.lon;
    }

    // الهامش يمنع التصاق الخط بالحافة، والمقياس الواحد للمحورين يحفظ
    // شكل المسار — مقياسان يفلطحان الطريق المستقيم فيصير كل المسارات سواء
    const pad = 9.0;
    final spanLat = (maxLat - minLat).abs();
    final spanLon = (maxLon - minLon).abs();
    final scale = [
      spanLon > 0 ? (size.width - pad * 2) / spanLon : double.infinity,
      spanLat > 0 ? (size.height - pad * 2) / spanLat : double.infinity,
    ].reduce((a, b) => a < b ? a : b);
    if (!scale.isFinite) return;

    final cx = size.width / 2, cy = size.height / 2;
    Offset at(({double lat, double lon}) p) => Offset(
          cx + ((p.lon - (minLon + maxLon) / 2) * scale),
          cy - ((p.lat - (minLat + maxLat) / 2) * scale),
        );

    final path = Path()..moveTo(at(shape.first).dx, at(shape.first).dy);
    // عيّنة لا كل النقطة: مسار بين محافظتين فيه آلاف النقاط على 92 بكسل
    final step = (shape.length / 90).ceil();
    for (var i = step; i < shape.length; i += step) {
      path.lineTo(at(shape[i]).dx, at(shape[i]).dy);
    }
    path.lineTo(at(shape.last).dx, at(shape.last).dy);

    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.6
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );

    canvas.drawCircle(at(shape.first), 3.2, Paint()..color = D.textFaint);
    canvas.drawCircle(at(shape.last), 4.2, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_ThumbPainter old) =>
      old.shape != shape || old.color != color;
}

/// وسيلة إيضاح ألوان الزحام — تطفو أسفل الخريطة في شاشة الخيارات.
class DTrafficLegend extends StatelessWidget {
  const DTrafficLegend({super.key});

  @override
  Widget build(BuildContext context) {
    const levels = ['jam', 'moderate', 'free'];
    return DCard(
      radius: D.rPill,
      shadow: D.shadowSoft,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final lv in levels) ...[
            if (lv != levels.first) const SizedBox(width: 14),
            Container(
              width: 9,
              height: 9,
              decoration: BoxDecoration(
                  color: D.trafficColor(lv), shape: BoxShape.circle),
            ),
            const SizedBox(width: 6),
            Text(Cfg.trafficLabels[lv]!,
                style: D.caption.copyWith(fontWeight: FontWeight.w600)),
          ],
        ],
      ),
    );
  }
}

/// أعمدة ٢٤ ساعة — «أفضل أوقات الانطلاق». العمود الحالي معلَّم.
class DHourBars extends StatelessWidget {
  /// شدّة الزحام لكل ساعة بين 0 و1، أو null للساعة التي ما عندنا عنها قراءات.
  final List<double?> hours;
  final int highlightHour;

  const DHourBars({
    super.key,
    required this.hours,
    required this.highlightHour,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 92,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (var h = 23; h >= 0; h--)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 1.5),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Container(
                      height: 10 + (hours[h] ?? 0) * 62,
                      decoration: BoxDecoration(
                        // الساعة بلا قراءات تبقى شبحاً: عمود قصير باهت
                        // أصدق من عمود أخضر يوحي بأن الطريق سالك
                        color: hours[h] == null
                            ? D.divider
                            : _shade(hours[h]!).withValues(
                                alpha: h == highlightHour ? 1 : 0.75),
                        borderRadius: BorderRadius.circular(5),
                        border: h == highlightHour
                            ? Border.all(color: D.ink, width: 1.4)
                            : null,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  static Color _shade(double v) => v < 0.33
      ? D.trafficFree
      : v < 0.66
          ? D.trafficMid
          : D.trafficJam;
}

/// شريط البحث العلوي — كبسولة بيضاء، النصّ يميناً والأيقونة يساراً.
class DSearchBar extends StatelessWidget {
  final String hint;
  final VoidCallback? onTap;
  final Widget? leading;
  final Widget? trailing;

  const DSearchBar({
    super.key,
    required this.hint,
    this.onTap,
    this.leading,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return DCard(
      radius: D.rPill,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      onTap: onTap,
      child: Row(
        children: [
          ?leading,
          const SizedBox(width: 6),
          const Icon(Icons.search, color: D.textSoft, size: 22),
          const SizedBox(width: 8),
          Expanded(
            child: Text(hint,
                textAlign: TextAlign.right,
                style: D.body.copyWith(
                    color: D.textSoft, fontWeight: FontWeight.w500)),
          ),
          const SizedBox(width: 6),
          ?trailing,
        ],
      ),
    );
  }
}
