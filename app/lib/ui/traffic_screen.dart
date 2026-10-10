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

import '../core/api_client.dart' show ApiDown, ApiRejected;
import '../nav/phrases.dart';
import '../nav/route_model.dart';
import '../reports/reports.dart';
import '../state/app_state.dart';
import 'saved_screen.dart' show SheetScaffold;
import 'theme.dart';

class TrafficScreen extends StatefulWidget {
  const TrafficScreen({super.key});

  @override
  State<TrafficScreen> createState() => _TrafficScreenState();
}

class _TrafficScreenState extends State<TrafficScreen> {
  /// 0 = الآن، 1 = لاحقاً (منحنى ساعات اليوم)
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final reports = app.visibleReports;

    final crashes = reports.where((r) => r.kind == 'crash').length;
    final closures = reports.where((r) => r.kind == 'road_closed').length;
    final jams = reports.where((r) => r.kind == 'jam').length;

    return SheetScaffold(
      title: _tab == 0 ? 'حالة المرور الآن' : 'المرور لاحقاً',
      subtitle: _tab == 1
          ? 'منحنى ساعات اليوم من قراءات السائقين'
          : app.backendUp
              ? 'مباشر من بلاغات السائقين حولك'
              : 'بلا اتصال — ما نقدر نجيب الحالة',
      icon: Icons.insights_rounded,
      children: [
        Align(
          alignment: Alignment.centerRight,
          child: DSegmented(
            labels: const ['الآن', 'لاحقاً'],
            selected: _tab,
            onPick: (i) => setState(() => _tab = i),
          ),
        ),
        const SizedBox(height: 14),

        if (_tab == 1) ...[
          const _HourProfile(),
          const SizedBox(height: 22),
          const _FastestRoutes(),
        ] else ...[
          ..._nowTab(app, reports, crashes, closures, jams),
        ],
      ],
    );
  }

  List<Widget> _nowTab(AppState app, List<Report> reports, int crashes,
      int closures, int jams) {
    return [
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
        const _FastestRoutes(),

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
    ];
  }

  static List<Report> _nearest(List<Report> list) {
    final out = [...list]..sort(
        (a, b) => (a.distanceM ?? 1e9).compareTo(b.distanceM ?? 1e9));
    return out.take(6).toList();
  }
}

/// منحنى الزحام بساعات اليوم.
///
/// وطنيّ لا محلّي، ونقولها في السطر تحته: القراءة عندنا ما تحمل موقعاً
/// (way_id وحده) وهذا وعد خصوصية. منحنى باسم «بغداد» كان يقتضي أن نعرف
/// أين السائق، وما نعرف ولا نبي.
class _HourProfile extends StatefulWidget {
  const _HourProfile();

  @override
  State<_HourProfile> createState() => _HourProfileState();
}

class _HourProfileState extends State<_HourProfile> {
  List<double?>? _hours;
  int _days = 7;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final p = await context.read<AppState>().api.trafficProfile();
      if (!mounted) return;
      setState(() {
        _hours = p.hours;
        _days = p.windowDays;
      });
    } on ApiDown {
      if (mounted) setState(() => _failed = true);
    } on ApiRejected {
      if (mounted) setState(() => _failed = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final hours = _hours;
    final known = hours?.where((h) => h != null).length ?? 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const DSectionHeader(
          title: 'أفضل أوقات الانطلاق اليوم',
          subtitle: 'لتجنّب الزحام',
          icon: Icons.schedule,
        ),
        const SizedBox(height: 10),
        DCard(
          color: D.cardInner,
          shadow: const [],
          radius: D.rInner,
          padding: const EdgeInsets.fromLTRB(12, 14, 12, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (hours == null)
                SizedBox(
                  height: 92,
                  child: Center(
                    child: Text(
                      _failed
                          ? 'المنحنى يحتاج اتصالاً بالسيرفر.'
                          : 'نجيب القراءات…',
                      style: D.bodySoft,
                    ),
                  ),
                )
              else ...[
                DHourBars(hours: hours, highlightHour: DateTime.now().hour),
                const SizedBox(height: 6),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    for (final h in [0, 6, 12, 18])
                      Text(_hourLabel(h), style: D.caption),
                  ].reversed.toList(),
                ),
                const SizedBox(height: 8),
                Text(
                  known == 0
                      ? 'ما عندنا قراءات كافية بعد. المنحنى يمتلئ كلما سافر '
                          'سائقون أكثر — والقراءة تُحذف بعد $_days أيام.'
                      : 'من قراءات سرعة سائقي درب في العراق كلّه خلال '
                          '$_days أيام. ${hd('$known')} ساعة من ٢٤ عندها '
                          'قراءات كافية؛ الباقي باهت لأننا ما نعرفه.',
                  textAlign: TextAlign.right,
                  style: D.caption,
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  static String _hourLabel(int h) {
    final period = h < 12 ? 'ص' : 'م';
    final hh = h % 12 == 0 ? 12 : h % 12;
    return hd('$hh $period');
  }
}

/// «الطرق الأسرع»: وجهات المستخدم المتكرّرة بزمنها الآن.
///
/// من رحلاته لا من قائمة ثابتة: «من المنصور إلى الكرادة» لا تعني شيئاً
/// لساكن البصرة. وبلا رحلات محفوظة نقول ذلك بدل ما نخترع مسارين.
class _FastestRoutes extends StatefulWidget {
  const _FastestRoutes();

  @override
  State<_FastestRoutes> createState() => _FastestRoutesState();
}

class _FastestRoutesState extends State<_FastestRoutes> {
  /// العنوان ← (الزمن بالثواني، الشارع الأطول على المسار)
  final Map<String, (double, String?)> _eta = {};
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    if (_busy) return;
    final app = context.read<AppState>();
    final from = app.fix?.pos;
    if (from == null) return;

    // ثلاثة فقط: كل واحدة طلب توجيه كامل، وقائمة من عشر وجهات تعني
    // عشرة طلبات في كل مرة يفتح فيها التبويب
    final trips = app.recentTrips.take(3).toList();
    if (trips.isEmpty) return;

    setState(() => _busy = true);
    for (final t in trips) {
      try {
        final j = await app.api
            .route(points: [from, t.pos], alternates: 0);
        final route = NavRoute.fromTrip(j['trip'] as Map<String, dynamic>);
        if (!mounted) return;
        _eta[t.title] = (route.effectiveTimeS, _mainStreet(route));
      } on ApiDown {
        break;
      } on ApiRejected {
        continue;
      }
    }
    if (mounted) setState(() => _busy = false);
  }

  /// اسم أطول مناورة لها اسم — هو ما يقوله السائق حين يصف طريقه.
  static String? _mainStreet(NavRoute r) {
    Maneuver? longest;
    for (final m in r.maneuvers) {
      if (m.announceStreet == null) continue;
      if (longest == null || m.lengthM > longest.lengthM) longest = m;
    }
    return longest?.announceStreet;
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final trips = app.recentTrips.take(3).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const DSectionHeader(
          title: 'الطرق الأسرع',
          subtitle: 'وجهاتك المتكرّرة بزمنها الآن',
          icon: Icons.route_outlined,
        ),
        const SizedBox(height: 10),
        if (trips.isEmpty)
          DCard(
            color: D.cardInner,
            shadow: const [],
            radius: D.rInner,
            padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
            child: Text(
              'تظهر هنا بعد أول رحلة. كل وجهة تروحها تُحفَظ، وتصير زمنها '
              'الآن معروضاً قبل ما تنطلق.',
              textAlign: TextAlign.center,
              style: D.bodySoft,
            ),
          )
        else
          for (final t in trips) ...[
            _FastRouteRow(
              title: t.title,
              seconds: _eta[t.title]?.$1,
              via: _eta[t.title]?.$2,
              busy: _busy && !_eta.containsKey(t.title),
              onTap: () => app.chooseDestination(Destination(t.title, t.pos)),
            ),
            const SizedBox(height: 8),
          ],
      ],
    );
  }
}

class _FastRouteRow extends StatelessWidget {
  final String title;
  final double? seconds;
  final String? via;
  final bool busy;
  final VoidCallback onTap;

  const _FastRouteRow({
    required this.title,
    required this.seconds,
    required this.via,
    required this.busy,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => DCard(
        color: D.cardInner,
        shadow: const [],
        radius: D.rInner,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
        onTap: onTap,
        child: Row(
          children: [
            DCard(
              radius: D.rPill,
              color: D.mintLight,
              shadow: const [],
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              child: Text(
                busy
                    ? '…'
                    : seconds == null
                        ? '—'
                        : durationLabel(seconds!),
                style: D.caption.copyWith(
                    fontWeight: FontWeight.w800, color: D.greenDeep),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text('إلى $title',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: D.h3.copyWith(fontSize: 14)),
                  Text(
                    via != null
                        ? 'عبر $via'
                        : seconds == null
                            ? 'ما حسبناه بعد'
                            : 'الطريق المقترح',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: D.caption,
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_left, size: 18, color: D.textSoft),
          ],
        ),
      );
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
