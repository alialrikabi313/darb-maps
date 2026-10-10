// ورقة خيارات الطريق قبل الانطلاق.
//
// مطابقة للمرئي: عنوان الوجهة، ثم بطاقة لكل مسار فيها وصفه («الأسرع»،
// «أقل ازدحاماً») ومدته ومسافته وزرّ اختيار دائري، ثم زرّ أسود كبير.
//
// وصف المسار محسوب من أرقامه لا مُسمّى اعتباطاً: الأسرع هو الأقصر زمناً،
// والأقصر هو الأقصر مسافةً، و«أقل ازدحاماً» للذي زحامه أخفّ. وإذا ما
// اختلفت الأرقام ما نخترع وصفاً.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../nav/phrases.dart';
import '../nav/route_model.dart';
import '../state/app_state.dart';
import 'route_options_sheet.dart';
import 'theme.dart';
import 'trip_planner_screen.dart';

class RouteSheet extends StatelessWidget {
  final VoidCallback onStart;
  final VoidCallback onCancel;

  const RouteSheet({super.key, required this.onStart, required this.onCancel});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();

    return Container(
      decoration: const BoxDecoration(
        color: D.card,
        borderRadius: BorderRadius.vertical(top: Radius.circular(D.rSheet)),
        boxShadow: [
          BoxShadow(color: Color(0x1A000000), blurRadius: 28,
              offset: Offset(0, -6)),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const DGrabber(),

              Row(
                children: [
                  DMapButton(
                    icon: Icons.close,
                    tooltip: 'إلغاء',
                    onTap: onCancel,
                    size: 36,
                    background: D.cardInner,
                  ),
                  const Spacer(),
                  Expanded(
                    flex: 6,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        const Text('خيارات الطريق', style: D.h2),
                        Text(
                          'إلى ${app.destination?.title ?? ''}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: D.caption,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  const DIconCircle(Icons.alt_route,
                      size: 36, foreground: D.greenDeep),
                ],
              ),

              const SizedBox(height: 14),

              if (app.routing)
                const _Loading()
              else if (app.routeError != null)
                _ErrorBox(message: app.routeError!)
              else if (app.proposed != null)
                _Options(
                  primary: app.proposed!,
                  alternates: app.alternates,
                  onPick: app.pickAlternate,
                ),

              if (!app.routing && app.proposed != null) ...[
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: DChip(
                        label: modeLabel(app.costing),
                        icon: modeIcon(app.costing),
                        onTap: () => showModalBottomSheet<void>(
                          context: context,
                          backgroundColor: Colors.transparent,
                          isScrollControlled: true,
                          builder: (_) => const RouteOptionsSheet(),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: DChip(
                        label: app.stops.isEmpty
                            ? 'أضف محطة'
                            : 'المحطات (${hd('${app.stops.length}')})',
                        icon: Icons.add_location_alt_outlined,
                        selected: app.stops.isNotEmpty,
                        onTap: () => Navigator.of(context).push<void>(
                            MaterialPageRoute(
                                builder: (_) => const TripPlannerScreen())),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                DBigButton(
                  label: 'ابدأ الرحلة',
                  subtitle: 'ابدأ رحلتك عبر ${app.destination?.title ?? ''}',
                  icon: Icons.near_me,
                  onTap: onStart,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _Options extends StatelessWidget {
  final NavRoute primary;
  final List<NavRoute> alternates;
  final void Function(int) onPick;

  const _Options({
    required this.primary,
    required this.alternates,
    required this.onPick,
  });

  @override
  Widget build(BuildContext context) {
    final all = [primary, ...alternates];
    final labels = _labelRoutes(all);

    return Column(
      children: [
        for (var i = 0; i < all.length; i++) ...[
          if (i > 0) const SizedBox(height: 8),
          _RouteOption(
            route: all[i],
            label: labels[i].$1,
            note: labels[i].$2,
            icon: labels[i].$3,
            selected: i == 0,
            // الأساسي هو الأول دائماً؛ اختيار بديل يبدّله فيصير أولاً
            onTap: i == 0 ? null : () => onPick(i - 1),
          ),
        ],
      ],
    );
  }

  /// يصف كل مسار من أرقامه. الأوصاف تُشتقّ لا تُفترض.
  static List<(String, String, IconData)> _labelRoutes(List<NavRoute> rs) {
    if (rs.length == 1) {
      return [('الطريق المقترح', 'أفضل ما وجدناه', Icons.bolt)];
    }

    var fastest = 0, shortest = 0, smoothest = 0;
    for (var i = 1; i < rs.length; i++) {
      if (rs[i].effectiveTimeS < rs[fastest].effectiveTimeS) fastest = i;
      if (rs[i].lengthKm < rs[shortest].lengthKm) shortest = i;
      if (rs[i].trafficPenaltyS < rs[smoothest].trafficPenaltyS) {
        smoothest = i;
      }
    }

    final out = <(String, String, IconData)>[];
    for (var i = 0; i < rs.length; i++) {
      if (i == fastest) {
        out.add(('الأسرع',
            'الوصول المتوقّع ${arrivalLabel(DateTime.now().add(Duration(seconds: rs[i].effectiveTimeS.round())))}',
            Icons.bolt));
      } else if (i == smoothest && rs[i].trafficPenaltyS > 0) {
        out.add(('أقل ازدحاماً', 'طريق أكثر انسيابية الآن', Icons.waves));
      } else if (i == shortest) {
        out.add(('الأقصر', 'مسافة أقل مع بعض الازدحام', Icons.straighten));
      } else {
        out.add(('طريق بديل', 'عبر طريق آخر', Icons.alt_route));
      }
    }
    return out;
  }
}

class _RouteOption extends StatelessWidget {
  final NavRoute route;
  final String label;
  final String note;
  final IconData icon;
  final bool selected;
  final VoidCallback? onTap;

  const _RouteOption({
    required this.route,
    required this.label,
    required this.note,
    required this.icon,
    required this.selected,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return DCard(
      color: selected ? D.mintPale : D.cardInner,
      shadow: const [],
      radius: D.rInner,
      border: selected ? Border.all(color: D.mint, width: 2) : null,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      onTap: onTap,
      // ترتيب الصف من اليمين كما في المرئي: الاختيار، ثم الوصف، ثم
      // الأرقام، ثم مصغّرة الخط في أقصى اليسار
      child: Row(
        children: [
          DRadio(selected: selected),

          const SizedBox(width: 12),

          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(label, style: D.h3),
                    const SizedBox(width: 6),
                    Icon(icon, size: 16, color: D.green),
                  ],
                ),
                const SizedBox(height: 2),
                Text(note,
                    textAlign: TextAlign.right,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: D.caption),
                if (route.closuresAvoided > 0)
                  Text('تجنّبنا ${route.closuresAvoided} إغلاقاً',
                      style: D.caption.copyWith(color: D.danger)),
              ],
            ),
          ),

          const SizedBox(width: 8),

          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(durationLabel(route.effectiveTimeS),
                  style: D.num2.copyWith(fontSize: 19)),
              Row(
                children: [
                  Text(hd('${route.lengthKm.toStringAsFixed(1)} كم'),
                      style: D.caption),
                  const SizedBox(width: 4),
                  const Icon(Icons.straighten, size: 12, color: D.textSoft),
                ],
              ),
            ],
          ),

          const SizedBox(width: 10),

          DRouteThumb(
            shape: [
              for (final p in route.shape) (lat: p.latitude, lon: p.longitude)
            ],
            selected: selected,
          ),
        ],
      ),
    );
  }
}

class _Loading extends StatelessWidget {
  const _Loading();

  @override
  Widget build(BuildContext context) => const Padding(
        padding: EdgeInsets.symmetric(vertical: 26),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                    strokeWidth: 2.2, color: D.green)),
            SizedBox(width: 12),
            Text('نحسب أفضل طريق…', style: D.bodySoft),
          ],
        ),
      );
}

class _ErrorBox extends StatelessWidget {
  final String message;
  const _ErrorBox({required this.message});

  @override
  Widget build(BuildContext context) {
    return DCard(
      color: D.errorBg,
      shadow: const [],
      radius: D.rInner,
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          Expanded(
            child: Text(message,
                textAlign: TextAlign.right,
                style: const TextStyle(
                    color: D.errorInk, height: 1.4, fontSize: 13)),
          ),
          const SizedBox(width: 10),
          const Icon(Icons.error_outline, color: D.danger),
        ],
      ),
    );
  }
}
