// طبقة الملاحة فوق الخريطة.
//
// كل شيء هنا مقروء بطرف العين: الدائرة النعناعية الكبيرة للمناورة، ورقم
// المسافة أثقل ما في الشاشة، وشريط المسارات تحته. السائق ينظر أقل من
// ثانية في المرة.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../nav/nav_engine.dart';
import '../nav/phrases.dart';
import '../nav/route_model.dart';
import '../reports/reports.dart';
import '../state/app_state.dart';
import 'maneuver_icon.dart';
import 'theme.dart';

class NavOverlay extends StatelessWidget {
  final VoidCallback onStop;
  const NavOverlay({super.key, required this.onStop});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final nav = app.navState;
    final pad = MediaQuery.of(context).padding;

    return Stack(
      children: [
        Positioned(
          top: pad.top + 8,
          left: 12,
          right: 12,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _ManeuverCard(nav: nav, onStop: onStop),
              if (nav.next != null) ...[
                const SizedBox(height: 8),
                _LaneStrip(maneuver: nav.next!),
              ],
              if (nav.notice != null) ...[
                const SizedBox(height: 8),
                _StatusChip(text: nav.notice!, warning: nav.offRoute),
              ],
              if (nav.activeAlert != null) ...[
                const SizedBox(height: 8),
                _AlertCard(
                  report: nav.activeAlert!,
                  distanceM: nav.activeAlertDistanceM ?? 0,
                ),
              ],
            ],
          ),
        ),

        Positioned(
          right: 14,
          bottom: 148,
          child: Column(
            children: [
              DMapButton(
                icon: app.muted ? Icons.volume_off : Icons.volume_up,
                tooltip: app.muted ? 'شغّل الصوت' : 'اكتم الصوت',
                onTap: () => app.setMuted(!app.muted),
              ),
              const SizedBox(height: 10),
              DMapButton(
                icon: Icons.near_me,
                tooltip: 'رجّع الكاميرا للمسار',
                onTap: () => app.setCameraMode(CameraMode.navigate),
              ),
              const SizedBox(height: 10),
              DMapButton(
                icon: Icons.add_location_alt_outlined,
                tooltip: 'أبلِغ',
                background: D.mint,
                foreground: D.greenDeep,
                onTap: app.backendUp ? () => _quickReport(context) : null,
              ),
            ],
          ),
        ),

        if (nav.speedKmh > 1)
          Positioned(
            left: 14,
            bottom: 148,
            child: _SpeedCluster(
              kmh: nav.speedKmh,
              limitKmh: nav.speedLimitKmh,
            ),
          ),

        Positioned(
          left: 0, right: 0, bottom: 0,
          child: _NavBottomBar(nav: nav, onStop: onStop),
        ),
      ],
    );
  }

  void _quickReport(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const QuickReportGrid(),
    );
  }
}

// ── بطاقة المناورة ─────────────────────────────────────────────────────────

class _ManeuverCard extends StatelessWidget {
  final NavState nav;
  final VoidCallback onStop;

  const _ManeuverCard({required this.nav, required this.onStop});

  @override
  Widget build(BuildContext context) {
    final m = nav.next ?? nav.current;
    if (m == null) return const SizedBox.shrink();

    return DCard(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // زرّ الإنهاء على اليسار — كما في التصميم
          DMapButton(
            icon: Icons.close,
            tooltip: 'أوقف الملاحة',
            onTap: onStop,
            size: 40,
            background: D.cardInner,
          ),

          const Spacer(),

          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(maneuverTitle(m), style: D.num2.copyWith(fontSize: 23)),
              const SizedBox(height: 2),
              SizedBox(
                width: MediaQuery.of(context).size.width * 0.46,
                child: Text(
                  _subtitle(m),
                  textAlign: TextAlign.right,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: D.body.copyWith(color: D.textSoft),
                ),
              ),
            ],
          ),

          const SizedBox(width: 12),

          // الدائرة النعناعية الكبيرة + المسافة تحتها
          Column(
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: const BoxDecoration(
                    color: D.mint, shape: BoxShape.circle),
                child: Center(
                  child: ManeuverIcon(
                    type: m.type,
                    roundaboutExit: m.roundaboutExitCount,
                    size: 46,
                    color: D.ink,
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Text(distanceLabel(nav.distanceToManeuverM),
                  style: D.h3.copyWith(fontSize: 16)),
            ],
          ),
        ],
      ),
    );
  }

  static String _subtitle(Maneuver m) {
    final street = m.announceStreet;
    if (m.exitNumber != null) {
      return 'مخرج ${m.exitNumber}'
          '${m.exitToward.isEmpty ? '' : ' باتجاه ${m.exitToward.first}'}';
    }
    // 8% فقط من طرق العراق مسمّاة في OSM، فالاسم غائب غالباً — نكتب
    // «كمّل على طريقك» لا سطراً فارغاً
    if (street == null) return m.isArrival ? 'وجهتك' : 'كمّل على طريقك';
    return m.isArrival ? street : 'إلى $street';
  }
}

/// شريط إرشاد المسارات. نعرضه بلا بيانات مسارات حقيقية من OSM: نستنتج
/// عدد المسارات من صنف الطريق ونبرز الجهة المطلوبة.
///
/// صريح: OSM العراق ما فيه وسم turn:lanes إلا نادراً، فهذا إرشاد تقريبي
/// يوضّح الجهة لا عدد المسارات الحقيقي. إخفاؤه كلياً يفقد السائق إشارة
/// مفيدة، وادّعاء الدقة أسوأ — ولهذا لا نلوّن إلا سهم الجهة.
class _LaneStrip extends StatelessWidget {
  final Maneuver maneuver;
  const _LaneStrip({required this.maneuver});

  @override
  Widget build(BuildContext context) {
    final side = _side(maneuver.type);
    if (side == 0) return const SizedBox.shrink();

    const lanes = 4;

    return DCard(
      radius: D.rPill,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (var i = 0; i < lanes; i++) ...[
            if (i > 0)
              Container(
                width: 1.2,
                height: 22,
                margin: const EdgeInsets.symmetric(horizontal: 6),
                color: D.divider,
              ),
            _lane(isTarget: side > 0 ? i == 0 : i == lanes - 1, side: side),
          ],
        ],
      ),
    );
  }

  Widget _lane({required bool isTarget, required int side}) {
    return Container(
      width: 54,
      height: 34,
      decoration: BoxDecoration(
        color: isTarget ? D.mint : Colors.transparent,
        borderRadius: BorderRadius.circular(D.rPill),
      ),
      child: Icon(
        isTarget
            ? (side > 0 ? Icons.turn_right : Icons.turn_left)
            : Icons.straight,
        size: 22,
        color: isTarget ? D.ink : D.textSoft,
      ),
    );
  }

  /// موجب = يمين، سالب = يسار، صفر = لا إرشاد.
  static int _side(int type) => switch (type) {
        Mnv.right ||
        Mnv.slightRight ||
        Mnv.sharpRight ||
        Mnv.rampRight ||
        Mnv.exitRight ||
        Mnv.stayRight ||
        Mnv.mergeRight =>
          1,
        Mnv.left ||
        Mnv.slightLeft ||
        Mnv.sharpLeft ||
        Mnv.rampLeft ||
        Mnv.exitLeft ||
        Mnv.stayLeft ||
        Mnv.mergeLeft =>
          -1,
        _ => 0,
      };
}

// ── عدّاد السرعة وحدّها ─────────────────────────────────────────────────────

class _SpeedCluster extends StatelessWidget {
  final double kmh;
  final double? limitKmh;

  const _SpeedCluster({required this.kmh, this.limitKmh});

  @override
  Widget build(BuildContext context) {
    final over = limitKmh != null && kmh > limitKmh! + 5;

    return DCard(
      radius: D.rPill,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (limitKmh != null) ...[
            // لوحة الحدّ: دائرة بحلقة حمراء كما في الطريق
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
                border: Border.all(color: D.danger, width: 3.5),
              ),
              child: Center(
                child: Text('${limitKmh!.round()}',
                    style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: D.text)),
              ),
            ),
            const SizedBox(width: 10),
          ],
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('${kmh.round()}',
                  style: D.num2.copyWith(
                      fontSize: 24,
                      height: 1,
                      color: over ? D.danger : D.text)),
              const Text('كم/س',
                  style: TextStyle(fontSize: 10, color: D.textSoft)),
            ],
          ),
        ],
      ),
    );
  }
}

// ── التنبيهات ──────────────────────────────────────────────────────────────

class _AlertCard extends StatelessWidget {
  final Report report;
  final double distanceM;

  const _AlertCard({required this.report, required this.distanceM});

  @override
  Widget build(BuildContext context) {
    final app = context.read<AppState>();
    final look = lookFor(report.kind);

    return DCard(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        children: [
          // «موجود / مو موجود» زرّان كبيران: التصويت وهو يسوق ما يكون قائمة
          _voteButton(Icons.thumb_down_alt_outlined, D.danger, 'مو موجود',
              () => app.voteReport(report.id, isUp: false)),
          const SizedBox(width: 4),
          _voteButton(Icons.thumb_up_alt_outlined, D.green, 'موجود',
              () => app.voteReport(report.id, isUp: true)),
          const Spacer(),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text('${report.label} بعد ${distanceLabel(distanceM)}',
                  style: D.h3),
              Text(
                report.confirmed
                    ? report.ageLabel
                    // «غير مؤكّد» صريحة لا مخفيّة: المستخدم يقرّر بنفسه
                    : '${report.ageLabel} — غير مؤكّد',
                style: D.caption,
              ),
            ],
          ),
          const SizedBox(width: 10),
          DIconCircle(look.icon,
              size: 40,
              background: look.color.withValues(alpha: 0.14),
              foreground: look.color),
        ],
      ),
    );
  }

  Widget _voteButton(
      IconData icon, Color color, String tooltip, VoidCallback onTap) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: color.withValues(alpha: 0.1),
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(9),
            child: Icon(icon, size: 19, color: color),
          ),
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  final String text;
  final bool warning;

  const _StatusChip({required this.text, required this.warning});

  @override
  Widget build(BuildContext context) {
    return DCard(
      radius: D.rPill,
      color: warning ? D.danger : D.ink,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (warning) ...[
            const Icon(Icons.warning_amber, color: Colors.white, size: 16),
            const SizedBox(width: 6),
          ],
          Flexible(
            child: Text(text,
                style: const TextStyle(color: Colors.white, fontSize: 13)),
          ),
        ],
      ),
    );
  }
}

// ── الشريط الأسفل ──────────────────────────────────────────────────────────

class _NavBottomBar extends StatelessWidget {
  final NavState nav;
  final VoidCallback onStop;

  const _NavBottomBar({required this.nav, required this.onStop});

  @override
  Widget build(BuildContext context) {
    final route = nav.route;

    return Container(
      decoration: const BoxDecoration(
        color: D.card,
        borderRadius: BorderRadius.vertical(top: Radius.circular(D.rSheet)),
        boxShadow: [
          BoxShadow(color: Color(0x1A000000), blurRadius: 24,
              offset: Offset(0, -4)),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
          child: Row(
            children: [
              DMapButton(
                icon: Icons.keyboard_arrow_up,
                tooltip: 'تفاصيل الرحلة',
                onTap: () => _showSteps(context, nav),
                size: 42,
                background: D.cardInner,
              ),

              Expanded(
                child: Column(
                  children: [
                    Text(durationLabel(nav.remainingS),
                        style: D.num1.copyWith(fontSize: 25)),
                    const SizedBox(height: 2),
                    Text(
                      [
                        distanceLabel(nav.remainingM),
                        if (nav.eta != null) arrivalLabel(nav.eta!),
                        // تغطية الزحام معروضة: ETA بتغطية 10% لا يُقدَّم
                        // بنفس ثقة ETA بتغطية 90%
                        if (route != null && route.trafficCoverage > 0)
                          'زحام ${(route.trafficCoverage * 100).round()}%',
                      ].join(' • '),
                      style: D.bodySoft,
                    ),
                  ],
                ),
              ),

              DMapButton(
                icon: Icons.more_horiz,
                tooltip: 'خيارات',
                onTap: () => _showSteps(context, nav),
                size: 42,
                background: D.cardInner,
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showSteps(BuildContext context, NavState nav) {
    final route = nav.route;
    if (route == null) return;

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _StepsSheet(route: route, currentIndex: _indexOf(nav)),
    );
  }

  static int _indexOf(NavState nav) {
    final route = nav.route;
    final cur = nav.current;
    if (route == null || cur == null) return 0;
    final i = route.maneuvers.indexOf(cur);
    return i < 0 ? 0 : i;
  }
}

class _StepsSheet extends StatelessWidget {
  final NavRoute route;
  final int currentIndex;

  const _StepsSheet({required this.route, required this.currentIndex});

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.75),
      decoration: const BoxDecoration(
        color: D.card,
        borderRadius: BorderRadius.vertical(top: Radius.circular(D.rSheet)),
      ),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const DGrabber(),
          DSectionHeader(
            title: 'خطوات الطريق',
            subtitle: '${route.maneuvers.length} مناورة · '
                '${route.lengthKm.toStringAsFixed(1)} كم',
            icon: Icons.list_alt,
          ),
          const SizedBox(height: 10),
          Flexible(
            child: ListView.separated(
              shrinkWrap: true,
              itemCount: route.maneuvers.length,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (_, i) {
                final m = route.maneuvers[i];
                final done = i < currentIndex;
                final active = i == currentIndex;

                return DCard(
                  color: active ? D.mintPale : D.cardInner,
                  shadow: const [],
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 10),
                  child: Opacity(
                    opacity: done ? 0.45 : 1,
                    child: Row(
                      children: [
                        Text(distanceLabel(m.lengthM), style: D.caption),
                        const Spacer(),
                        Expanded(
                          flex: 5,
                          child: Text(
                            maneuverDetail(m),
                            textAlign: TextAlign.right,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: D.body.copyWith(
                                fontWeight: active
                                    ? FontWeight.w700
                                    : FontWeight.w500),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Container(
                          width: 38, height: 38,
                          decoration: BoxDecoration(
                            color: active ? D.mint : D.mintLight,
                            shape: BoxShape.circle,
                          ),
                          child: Center(
                            child: ManeuverIcon(
                                type: m.type,
                                roundaboutExit: m.roundaboutExitCount,
                                size: 24,
                                color: D.ink),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ── شبكة الإبلاغ السريع ────────────────────────────────────────────────────

/// لمسة واحدة لا شاشة: السائق يبلّغ وهو يسوق. التفاصيل في شاشة الإبلاغ
/// الكاملة من تبويب المجتمع.
class QuickReportGrid extends StatelessWidget {
  const QuickReportGrid({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.read<AppState>();
    final types = app.reports.types;

    return Container(
      decoration: const BoxDecoration(
        color: D.card,
        borderRadius: BorderRadius.vertical(top: Radius.circular(D.rSheet)),
      ),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const DGrabber(),
          const DSectionHeader(
            title: 'شنو شفت؟',
            subtitle: 'بلاغك يوصل للسائقين اللي وراك',
            icon: Icons.campaign_outlined,
          ),
          const SizedBox(height: 14),
          if (types.isEmpty)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                  app.reports.lastError ??
                      'ما قدرنا نجيب أنواع البلاغات من السيرفر',
                  style: D.bodySoft),
            )
          else
            GridView.count(
              shrinkWrap: true,
              crossAxisCount: 4,
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              childAspectRatio: 0.82,
              physics: const NeverScrollableScrollPhysics(),
              children: [
                for (final t in types)
                  ReportTypeTile(
                    type: t,
                    onTap: () async {
                      final err = await app.sendReport(t.kind);
                      if (!context.mounted) return;
                      Navigator.of(context).pop();
                      showDarbSnack(context,
                          err ?? 'شكراً — وصل بلاغك', isError: err != null);
                    },
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

/// مربّع نوع البلاغ: خلفية ملوّنة باهتة وأيقونة ملوّنة — كما في التصميم.
class ReportTypeTile extends StatelessWidget {
  final ReportType type;
  final bool selected;
  final VoidCallback onTap;

  const ReportTypeTile({
    super.key,
    required this.type,
    required this.onTap,
    this.selected = false,
  });

  @override
  Widget build(BuildContext context) {
    final look = type.look;

    return DCard(
      radius: D.rTile,
      color: selected ? look.color.withValues(alpha: 0.18) : D.card,
      shadow: D.shadowSoft,
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
      onTap: onTap,
      border: selected ? Border.all(color: look.color, width: 2) : null,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 42, height: 42,
            decoration: BoxDecoration(
              color: look.color.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(13),
            ),
            child: Icon(look.icon, color: look.color, size: 22),
          ),
          const SizedBox(height: 7),
          Text(type.label,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: D.caption.copyWith(
                  color: D.text,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500)),
        ],
      ),
    );
  }
}

/// شريط رسالة بنفس لغة التصميم — لا SnackBar الافتراضي المربّع.
void showDarbSnack(BuildContext context, String message,
    {bool isError = false}) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
    behavior: SnackBarBehavior.floating,
    backgroundColor: isError ? D.danger : D.ink,
    shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(D.rPill)),
    margin: const EdgeInsets.fromLTRB(16, 0, 16, 96),
    content: Text(message,
        textAlign: TextAlign.center,
        style: const TextStyle(fontWeight: FontWeight.w600)),
  ));
}
