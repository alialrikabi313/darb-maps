// ورقة «الخيارات»: نمط المركبة وما نتجنّبه.
//
// كل تبديل هنا يعيد حساب المسار فوراً لا عند الإغلاق: المستخدم يبي يشوف
// أثر «تجنّب السريع» على الزمن قبل ما يقرّر، لا بعد ما يخرج من الورقة.
//
// ═══ قرارك ═══
// أنماط المركبة المعروضة قرار مجال. حذفنا الشاحنة لأن توجيهها يحتاج أبعاداً
// وأوزاناً (ارتفاع الجسر، حمولة الطريق) ما عندنا منها شيء في بيانات العراق،
// وعرضها بلاها يعطي مساراً يمرّ تحت جسر واطئ.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import 'theme.dart';

/// الأنماط كما يسمّيها ڤالهالا، مع تسميتها العربية وأيقونتها.
const _modes = <(String, String, IconData)>[
  ('auto', 'سيارة', Icons.directions_car),
  ('motorcycle', 'دراجة نارية', Icons.two_wheeler),
  ('bus', 'حافلة', Icons.directions_bus),
  ('bicycle', 'دراجة', Icons.pedal_bike),
  ('pedestrian', 'مشياً', Icons.directions_walk),
];

String modeLabel(String costing) =>
    _modes.firstWhere((m) => m.$1 == costing, orElse: () => _modes.first).$2;

IconData modeIcon(String costing) =>
    _modes.firstWhere((m) => m.$1 == costing, orElse: () => _modes.first).$3;

class RouteOptionsSheet extends StatelessWidget {
  const RouteOptionsSheet({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final motorised = app.costing != 'pedestrian' && app.costing != 'bicycle';

    return Container(
      decoration: const BoxDecoration(
        color: D.card,
        borderRadius: BorderRadius.vertical(top: Radius.circular(D.rSheet)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const DGrabber(),
              const DSectionHeader(
                title: 'خيارات الطريق',
                subtitle: 'النمط وما نتجنّبه',
                icon: Icons.tune,
              ),

              const SizedBox(height: 14),

              SizedBox(
                height: 86,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: _modes.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 10),
                  itemBuilder: (_, i) {
                    final m = _modes[i];
                    final on = app.costing == m.$1;
                    return _ModeTile(
                      label: m.$2,
                      icon: m.$3,
                      selected: on,
                      onTap: () => app.setCosting(m.$1),
                    );
                  },
                ),
              ),

              const SizedBox(height: 10),

              // التجنّب للمحرّكات فقط: المشاة والدراجة ما يمرّون على
              // طريق سريع ولا يدفعون رسماً أصلاً
              if (motorised) ...[
                _AvoidRow(
                  label: 'تجنّب الطرق السريعة',
                  note: 'طريق داخلي أطول زمناً وأهدأ',
                  icon: Icons.alt_route,
                  value: app.avoidHighways,
                  onChanged: (v) => app.setAvoid(highways: v),
                ),
                _AvoidRow(
                  label: 'تجنّب الطرق المدفوعة',
                  note: 'ما في رسوم على طرق العراق حالياً — الخيار للمسافر',
                  icon: Icons.toll,
                  value: app.avoidTolls,
                  onChanged: (v) => app.setAvoid(tolls: v),
                ),
              ],
              _AvoidRow(
                label: 'تجنّب المعديات',
                note: 'عبور النهر بالعبّارة',
                icon: Icons.directions_boat,
                value: app.avoidFerries,
                onChanged: (v) => app.setAvoid(ferries: v),
              ),

              const SizedBox(height: 14),
              DBigButton(
                label: 'تمّ',
                onTap: () => Navigator.of(context).pop(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ModeTile extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  const _ModeTile({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => DCard(
        radius: D.rTile,
        color: selected ? D.mint : D.cardInner,
        shadow: selected ? D.shadowSoft : const [],
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        onTap: onTap,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 26, color: selected ? D.greenDeep : D.text),
            const SizedBox(height: 6),
            Text(label,
                style: D.caption.copyWith(
                    fontWeight: FontWeight.w700,
                    color: selected ? D.greenDeep : D.text)),
          ],
        ),
      );
}

class _AvoidRow extends StatelessWidget {
  final String label;
  final String note;
  final IconData icon;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _AvoidRow({
    required this.label,
    required this.note,
    required this.icon,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: DCard(
          radius: D.rInner,
          color: D.cardInner,
          shadow: const [],
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Row(
            children: [
              DIconCircle(icon, size: 34, foreground: D.greenDeep),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label,
                        style: D.body.copyWith(fontWeight: FontWeight.w600)),
                    Text(note, style: D.caption),
                  ],
                ),
              ),
              Switch(
                value: value,
                onChanged: onChanged,
                activeThumbColor: Colors.white,
                activeTrackColor: D.green,
              ),
            ],
          ),
        ),
      );
}
