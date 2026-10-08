// طبقة الملاحة فوق الخريطة: التعليمة، التنبيه، والشريط الأسفل.
//
// كل شيء هنا مقروء بطرف العين: خطوط كبيرة، تضاد عالٍ، ولا تفصيل يحتاج
// تدقيقاً. السائق ينظر للشاشة أقل من ثانية في المرة.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../nav/nav_engine.dart';
import '../nav/phrases.dart';
import '../reports/reports.dart';
import '../state/app_state.dart';
import 'maneuver_icon.dart';

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
          left: 10,
          right: 10,
          child: Column(
            children: [
              _InstructionBanner(nav: nav),
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

        // التعليمة التي بعد القادمة: السائق يحتاجها حين تكون المناورتان
        // متقاربتين («يمين ثم يسار فوراً») وهي حالة شائعة في بغداد
        if (nav.next != null && nav.distanceToManeuverM < 400)
          Positioned(
            top: pad.top + 108,
            left: 10,
            child: _ThenChip(nav: nav),
          ),

        Positioned(
          left: 0, right: 0, bottom: 0,
          child: _NavBottomBar(nav: nav, onStop: onStop),
        ),

        Positioned(
          right: 14,
          bottom: 130,
          child: Column(
            children: [
              _MiniButton(
                icon: app.muted ? Icons.volume_off : Icons.volume_up,
                onTap: () => app.setMuted(!app.muted),
                tooltip: app.muted ? 'شغّل الصوت' : 'اكتم الصوت',
              ),
              const SizedBox(height: 10),
              _MiniButton(
                icon: Icons.add_alert,
                color: const Color(0xFFF2A33C),
                onTap: app.backendUp
                    ? () => _quickReport(context)
                    : null,
                tooltip: 'أبلِغ',
              ),
            ],
          ),
        ),

        if (nav.speedKmh > 1)
          Positioned(
            left: 14,
            bottom: 130,
            child: _SpeedDial(kmh: nav.speedKmh),
          ),
      ],
    );
  }

  void _quickReport(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _QuickReportGrid(),
    );
  }
}

// ── الشريط الأعلى: التعليمة القادمة ────────────────────────────────────────

class _InstructionBanner extends StatelessWidget {
  final NavState nav;
  const _InstructionBanner({required this.nav});

  @override
  Widget build(BuildContext context) {
    final m = nav.next ?? nav.current;
    if (m == null) return const SizedBox.shrink();

    return Material(
      elevation: 8,
      borderRadius: BorderRadius.circular(16),
      color: const Color(0xFF1F3B63),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            ManeuverIcon(
              type: m.type,
              roundaboutExit: m.roundaboutExitCount,
              size: 52,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    distanceLabel(nav.distanceToManeuverM),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 30,
                      fontWeight: FontWeight.bold,
                      height: 1.1,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    maneuverDetail(m),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xFFD6E2F2),
                      fontSize: 15,
                      height: 1.25,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ThenChip extends StatelessWidget {
  final NavState nav;
  const _ThenChip({required this.nav});

  @override
  Widget build(BuildContext context) {
    final route = nav.route;
    final next = nav.next;
    if (route == null || next == null) return const SizedBox.shrink();

    final i = route.maneuvers.indexOf(next);
    if (i < 0 || i + 1 >= route.maneuvers.length) {
      return const SizedBox.shrink();
    }
    final after = route.maneuvers[i + 1];

    return Material(
      elevation: 4,
      borderRadius: BorderRadius.circular(12),
      color: const Color(0xCC1F3B63),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        child: Row(
          children: [
            const Text('ثم ',
                style: TextStyle(color: Color(0xFFD6E2F2), fontSize: 13)),
            ManeuverIcon(
              type: after.type,
              roundaboutExit: after.roundaboutExitCount,
              size: 22,
            ),
            const SizedBox(width: 6),
            Text(distanceLabel(after.lengthM),
                style: const TextStyle(color: Colors.white, fontSize: 13)),
          ],
        ),
      ),
    );
  }
}

// ── بطاقة التنبيه ──────────────────────────────────────────────────────────

class _AlertCard extends StatelessWidget {
  final Report report;
  final double distanceM;

  const _AlertCard({required this.report, required this.distanceM});

  @override
  Widget build(BuildContext context) {
    final app = context.read<AppState>();
    final look = lookFor(report.kind);

    return Material(
      elevation: 6,
      borderRadius: BorderRadius.circular(14),
      color: Colors.white,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                  color: look.color, shape: BoxShape.circle),
              child: Icon(look.icon, color: Colors.white, size: 22),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${report.label} بعد ${distanceLabel(distanceM)}',
                      style: const TextStyle(
                          fontSize: 15, fontWeight: FontWeight.bold)),
                  Text(
                    report.confirmed
                        ? report.ageLabel
                        // «غير مؤكّد» معروضة صريحة لا مخفيّة: المستخدم
                        // يقرّر بنفسه، وإخفاء غير المؤكّد يعني أن أول
                        // مُبلِّغ لا يفيد أحداً
                        : '${report.ageLabel} — غير مؤكّد',
                    style: const TextStyle(
                        fontSize: 12, color: Color(0xFF6B7280)),
                  ),
                ],
              ),
            ),
            // «موجود / مو موجود»: التصويت وهو يسوق لازم يكون زرّين
            // كبيرين لا قائمة
            IconButton(
              onPressed: () => app.voteReport(report.id, isUp: true),
              icon: const Icon(Icons.thumb_up_alt_outlined),
              color: const Color(0xFF2BB673),
              tooltip: 'موجود',
            ),
            IconButton(
              onPressed: () => app.voteReport(report.id, isUp: false),
              icon: const Icon(Icons.thumb_down_alt_outlined),
              color: const Color(0xFFD6333F),
              tooltip: 'مو موجود',
            ),
          ],
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
    return Material(
      borderRadius: BorderRadius.circular(10),
      color: warning ? const Color(0xFFD6333F) : const Color(0xFF374151),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
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
      ),
    );
  }
}

// ── الشريط الأسفل: ETA والمسافة والإيقاف ───────────────────────────────────

class _NavBottomBar extends StatelessWidget {
  final NavState nav;
  final VoidCallback onStop;

  const _NavBottomBar({required this.nav, required this.onStop});

  @override
  Widget build(BuildContext context) {
    final route = nav.route;

    return Material(
      elevation: 12,
      color: Colors.white,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
          child: Row(
            children: [
              IconButton.filled(
                onPressed: onStop,
                style: IconButton.styleFrom(
                    backgroundColor: const Color(0xFFD6333F)),
                icon: const Icon(Icons.close),
                tooltip: 'أوقف الملاحة',
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        Text(durationLabel(nav.remainingS),
                            style: const TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF111827))),
                        const SizedBox(width: 10),
                        Text(distanceLabel(nav.remainingM),
                            style: const TextStyle(
                                fontSize: 16, color: Color(0xFF6B7280))),
                      ],
                    ),
                    Row(
                      children: [
                        if (nav.eta != null)
                          Text('الوصول ${arrivalLabel(nav.eta!)}',
                              style: const TextStyle(
                                  fontSize: 13, color: Color(0xFF6B7280))),
                        // تغطية الزحام معروضة: ETA بتغطية 10% لا يُقدَّم
                        // بنفس ثقة ETA بتغطية 90%، والمستخدم يستحق يعرف
                        if (route != null && route.trafficCoverage > 0) ...[
                          const SizedBox(width: 10),
                          Text(
                            'زحام ${(route.trafficCoverage * 100).round()}%',
                            style: const TextStyle(
                                fontSize: 12, color: Color(0xFFF07B2B)),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SpeedDial extends StatelessWidget {
  final double kmh;
  const _SpeedDial({required this.kmh});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 62,
      height: 62,
      decoration: const BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(color: Color(0x33000000), blurRadius: 6,
              offset: Offset(0, 2))
        ],
      ),
      child: Center(
        child: Text('${kmh.round()}',
            style: const TextStyle(
                fontSize: 24, fontWeight: FontWeight.bold,
                color: Color(0xFF111827))),
      ),
    );
  }
}

class _MiniButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;
  final String tooltip;
  final Color? color;

  const _MiniButton({
    required this.icon,
    required this.onTap,
    required this.tooltip,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        elevation: 4,
        shape: const CircleBorder(),
        color: color ?? Colors.white,
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(11),
            child: Icon(icon,
                color: color == null ? const Color(0xFF374151) : Colors.white),
          ),
        ),
      ),
    );
  }
}

/// شبكة إبلاغ سريعة أثناء الملاحة: أزرار كبيرة بلا كتابة ولا تفاصيل.
///
/// السائق يبلّغ وهو يسوق — لمسة واحدة لا شاشة. التفاصيل (ملاحظة نصّية)
/// في شاشة الإبلاغ الكاملة من وضع الاستكشاف.
class _QuickReportGrid extends StatelessWidget {
  const _QuickReportGrid();

  @override
  Widget build(BuildContext context) {
    final app = context.read<AppState>();
    final types = app.reports.types;

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('شنو شفت؟',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 14),
          if (types.isEmpty)
            const Padding(
              padding: EdgeInsets.all(12),
              child: Text('ما قدرنا نجيب أنواع البلاغات من السيرفر',
                  style: TextStyle(color: Color(0xFF6B7280))),
            )
          else
            GridView.count(
              shrinkWrap: true,
              crossAxisCount: 4,
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              childAspectRatio: 0.85,
              physics: const NeverScrollableScrollPhysics(),
              children: [
                for (final t in types)
                  _ReportTile(
                    type: t,
                    onTap: () async {
                      final err = await app.sendReport(t.kind);
                      if (!context.mounted) return;
                      Navigator.of(context).pop();
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                        content: Text(err ?? 'شكراً — وصل بلاغك'),
                        backgroundColor: err == null
                            ? const Color(0xFF2BB673)
                            : const Color(0xFFD6333F),
                      ));
                    },
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

class _ReportTile extends StatelessWidget {
  final ReportType type;
  final VoidCallback onTap;

  const _ReportTile({required this.type, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final look = type.look;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 50,
            height: 50,
            decoration:
                BoxDecoration(color: look.color, shape: BoxShape.circle),
            child: Icon(look.icon, color: Colors.white, size: 26),
          ),
          const SizedBox(height: 6),
          Text(type.label,
              textAlign: TextAlign.center,
              maxLines: 2,
              style: const TextStyle(fontSize: 11, height: 1.15)),
        ],
      ),
    );
  }
}
