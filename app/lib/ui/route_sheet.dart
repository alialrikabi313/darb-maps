// معاينة المسار قبل الانطلاق: الملخّص والبدائل وزرّ البدء.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../nav/phrases.dart';
import '../nav/route_model.dart';
import '../state/app_state.dart';

class RouteSheet extends StatelessWidget {
  final VoidCallback onStart;
  final VoidCallback onCancel;

  const RouteSheet({super.key, required this.onStart, required this.onCancel});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();

    return Material(
      elevation: 14,
      color: Colors.white,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.place, color: Color(0xFFD6333F)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      app.destination?.title ?? '',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 17, fontWeight: FontWeight.bold),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: onCancel,
                    tooltip: 'إلغاء',
                  ),
                ],
              ),
              const SizedBox(height: 6),

              if (app.routing)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 22),
                  child: Center(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        SizedBox(
                          width: 18, height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                        SizedBox(width: 12),
                        Text('نحسب الطريق…'),
                      ],
                    ),
                  ),
                )
              else if (app.routeError != null)
                _ErrorBox(message: app.routeError!)
              else if (app.proposed != null)
                _RouteBody(
                  route: app.proposed!,
                  alternates: app.alternates,
                  onPickAlternate: app.pickAlternate,
                  onStart: onStart,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RouteBody extends StatelessWidget {
  final NavRoute route;
  final List<NavRoute> alternates;
  final void Function(int) onPickAlternate;
  final VoidCallback onStart;

  const _RouteBody({
    required this.route,
    required this.alternates,
    required this.onPickAlternate,
    required this.onStart,
  });

  @override
  Widget build(BuildContext context) {
    final eta = DateTime.now()
        .add(Duration(seconds: route.effectiveTimeS.round()));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(durationLabel(route.effectiveTimeS),
                style: const TextStyle(
                    fontSize: 28, fontWeight: FontWeight.bold,
                    color: Color(0xFF111827))),
            const SizedBox(width: 10),
            Text('${route.lengthKm.toStringAsFixed(1)} كم',
                style: const TextStyle(
                    fontSize: 17, color: Color(0xFF6B7280))),
            const Spacer(),
            Text('الوصول ${arrivalLabel(eta)}',
                style: const TextStyle(
                    fontSize: 14, color: Color(0xFF6B7280))),
          ],
        ),

        // حالة الزحام معلنة بصراحة: «ما عندنا قراءات» ليست عيباً نخفيه،
        // وهي الحالة الغالبة قبل ما تكبر كتلة المستخدمين
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              if (route.timeWithTrafficS != null &&
                  route.trafficCoverage > 0)
                _Tag(
                  icon: Icons.traffic,
                  text: 'الزحام محسوب على '
                      '${(route.trafficCoverage * 100).round()}% من الطريق',
                  color: const Color(0xFFF07B2B),
                )
              else
                const _Tag(
                  icon: Icons.info_outline,
                  text: 'بلا بيانات زحام — الزمن تقديري',
                  color: Color(0xFF6B7280),
                ),
              if (route.closuresAvoided > 0)
                _Tag(
                  icon: Icons.block,
                  text: 'تجنّبنا ${route.closuresAvoided} إغلاقاً مبلَّغاً',
                  color: const Color(0xFFB91C1C),
                ),
            ],
          ),
        ),

        if (alternates.isNotEmpty) ...[
          const SizedBox(height: 10),
          const Text('طرق بديلة',
              style: TextStyle(
                  fontSize: 13, fontWeight: FontWeight.bold,
                  color: Color(0xFF6B7280))),
          const SizedBox(height: 6),
          SizedBox(
            height: 46,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: alternates.length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (_, i) {
                final a = alternates[i];
                final diff = a.effectiveTimeS - route.effectiveTimeS;
                return OutlinedButton(
                  onPressed: () => onPickAlternate(i),
                  child: Row(
                    children: [
                      Text(durationLabel(a.effectiveTimeS)),
                      const SizedBox(width: 6),
                      Text(
                        diff >= 0
                            ? '+${(diff / 60).round()}د'
                            : '${(diff / 60).round()}د',
                        style: TextStyle(
                          fontSize: 12,
                          color: diff > 0
                              ? const Color(0xFFD6333F)
                              : const Color(0xFF2BB673),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],

        const SizedBox(height: 14),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: onStart,
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF2BB673),
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
            icon: const Icon(Icons.navigation),
            label: const Text('انطلق',
                style: TextStyle(
                    fontSize: 18, fontWeight: FontWeight.bold)),
          ),
        ),
      ],
    );
  }
}

class _Tag extends StatelessWidget {
  final IconData icon;
  final String text;
  final Color color;

  const _Tag({required this.icon, required this.text, required this.color});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 4),
        Text(text, style: TextStyle(fontSize: 12, color: color)),
      ],
    );
  }
}

class _ErrorBox extends StatelessWidget {
  final String message;
  const _ErrorBox({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFEE2E2),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline, color: Color(0xFFB91C1C)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(message,
                style: const TextStyle(
                    color: Color(0xFF7F1D1D), height: 1.4)),
          ),
        ],
      ),
    );
  }
}
