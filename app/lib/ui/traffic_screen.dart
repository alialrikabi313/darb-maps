// تبويب الحركة: حالة المرور الآن.
//
// كل رقم هنا محسوب من بلاغات حقيقية في الباكند. ما في رقم تزييني: لو
// ما عندنا بيانات نقول ذلك بدل ما نعرض صفراً يبدو كحقيقة.
//
// ملاحظة صريحة: «الازدحام العام» محسوب من نسبة البلاغات النشطة لا من
// قياس سرعات — قياس السرعات يحتاج كتلة مستخدمين ما عندنا بعد. العنوان
// يقول ذلك، والرقم ما يُقدَّم كأنه مقياس مروري رسمي.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../nav/phrases.dart';
import '../reports/reports.dart';
import '../state/app_state.dart';
import 'saved_screen.dart' show SheetScaffold;
import 'theme.dart';

class TrafficScreen extends StatelessWidget {
  const TrafficScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final reports = app.visibleReports;

    final crashes = reports.where((r) => r.kind == 'crash').length;
    final closures = reports.where((r) => r.kind == 'road_closed').length;
    final jams = reports.where((r) => r.kind == 'jam').length;

    return SheetScaffold(
      title: 'حالة المرور الآن',
      subtitle: app.backendUp
          ? 'مباشر من بلاغات السائقين حولك'
          : 'بلا اتصال — ما نقدر نجيب الحالة',
      icon: Icons.insights_rounded,
      children: [
        Row(
          children: [
            Expanded(
              child: _StatCard(
                icon: Icons.warning_amber_rounded,
                color: D.warn,
                value: '$crashes',
                label: 'حوادث مبلَّغ عنها',
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _StatCard(
                icon: Icons.do_not_disturb_on_outlined,
                color: D.danger,
                value: '$closures',
                label: 'طرق مغلقة',
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _StatCard(
                icon: Icons.directions_car_filled_outlined,
                color: D.trafficHeavy,
                value: '$jams',
                label: 'بلاغات زحام',
              ),
            ),
          ],
        ),

        const SizedBox(height: 14),
        _CoverageCard(app: app),

        const SizedBox(height: 22),
        const DSectionHeader(
          title: 'الحركة حولك',
          subtitle: 'أحدث ما بلّغ به السائقون',
          icon: Icons.sensors_rounded,
        ),
        const SizedBox(height: 10),

        if (reports.isEmpty)
          _Empty(backendUp: app.backendUp)
        else
          for (final r in _nearest(reports)) ...[
            _MovementRow(report: r),
            const SizedBox(height: 8),
          ],
      ],
    );
  }

  static List<Report> _nearest(List<Report> list) {
    final out = [...list]..sort(
        (a, b) => (a.distanceM ?? 1e9).compareTo(b.distanceM ?? 1e9));
    return out.take(6).toList();
  }
}

/// بطاقة تغطية الزحام — الرقم الوحيد الذي يستحق شرحاً.
class _CoverageCard extends StatelessWidget {
  final AppState app;
  const _CoverageCard({required this.app});

  @override
  Widget build(BuildContext context) {
    final route = app.navState.route ?? app.proposed;
    final coverage = route?.trafficCoverage ?? 0;
    final hasRoute = route != null;

    return DCard(
      color: D.cardInner,
      shadow: const [],
      radius: D.rInner,
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text(
                hasRoute ? '${(coverage * 100).round()}%' : '—',
                style: D.num1.copyWith(fontSize: 24),
              ),
              const Spacer(),
              const Expanded(
                flex: 4,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text('تغطية بيانات الزحام', style: D.h3),
                    Text('نسبة طريقك التي عندنا عليها قراءات سرعة',
                        textAlign: TextAlign.right, style: D.caption),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(5),
            child: LinearProgressIndicator(
              value: coverage,
              minHeight: 8,
              backgroundColor: D.divider,
              valueColor: AlwaysStoppedAnimation(
                  coverage > 0.5 ? D.green : D.trafficMid),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            hasRoute
                ? (coverage > 0
                    ? 'كلما زاد عدد السائقين زادت دقّة الأزمنة.'
                    : 'ما عندنا قراءات على هذا الطريق بعد — الزمن تقديري.')
                : 'اختر وجهة لترى تغطية الزحام على طريقك.',
            textAlign: TextAlign.right,
            style: D.caption,
          ),
        ],
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String value;
  final String label;

  const _StatCard({
    required this.icon,
    required this.color,
    required this.value,
    required this.label,
  });

  @override
  Widget build(BuildContext context) => DCard(
        color: D.cardInner,
        shadow: const [],
        radius: D.rInner,
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 10),
        child: Column(
          children: [
            Container(
              width: 38, height: 38,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: color, size: 20),
            ),
            const SizedBox(height: 8),
            Text(value, style: D.num2),
            const SizedBox(height: 2),
            Text(label,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: D.caption),
          ],
        ),
      );
}

class _MovementRow extends StatelessWidget {
  final Report report;
  const _MovementRow({required this.report});

  @override
  Widget build(BuildContext context) {
    final look = lookFor(report.kind);

    return DCard(
      color: D.cardInner,
      shadow: const [],
      radius: D.rInner,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      child: Row(
        children: [
          if (report.distanceM != null)
            Text(distanceLabel(report.distanceM!),
                style: D.caption.copyWith(fontWeight: FontWeight.w700)),
          const Spacer(),
          Expanded(
            flex: 5,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(report.label, style: D.h3.copyWith(fontSize: 14)),
                Text(
                  report.note?.isNotEmpty == true
                      ? report.note!
                      : report.ageLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: D.caption,
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Container(
            width: 38, height: 38,
            decoration: BoxDecoration(
              color: look.color.withValues(alpha: 0.14),
              shape: BoxShape.circle,
            ),
            child: Icon(look.icon, color: look.color, size: 19),
          ),
        ],
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  final bool backendUp;
  const _Empty({required this.backendUp});

  @override
  Widget build(BuildContext context) => DCard(
        color: D.cardInner,
        shadow: const [],
        radius: D.rInner,
        padding: const EdgeInsets.symmetric(vertical: 26, horizontal: 16),
        child: Column(
          children: [
            DIconCircle(
                backendUp ? Icons.traffic_outlined : Icons.cloud_off,
                size: 46,
                foreground: backendUp ? D.green : D.textSoft),
            const SizedBox(height: 10),
            Text(
              backendUp
                  ? 'ما في بلاغات حولك الآن.'
                  : 'حالة المرور تحتاج اتصالاً بالسيرفر.',
              textAlign: TextAlign.center,
              style: D.bodySoft,
            ),
          ],
        ),
      );
}
