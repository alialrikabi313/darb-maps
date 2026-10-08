// الهيكل: الخريطة دائماً في الأسفل، والتبويبات طبقات فوقها.
//
// ليش الخريطة خارج التبويبات: بناء MapLibreMap ينشئ platform view ويحمّل
// النمط من الصفر — ثانية شاشةً رمادية في كل تبديل تبويب. فتبقى في مكانها
// وتتبدّل الطبقات فوقها.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import 'community_screen.dart';
import 'map_screen.dart';
import 'nav_overlay.dart';
import 'profile_screen.dart';
import 'report_sheet.dart';
import 'saved_screen.dart';
import 'theme.dart';
import 'traffic_screen.dart';

enum DarbTab { map, traffic, community, saved, profile }

class Shell extends StatefulWidget {
  const Shell({super.key});

  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  DarbTab _tab = DarbTab.map;

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();

    if (app.fatalError != null) return FatalScreen(message: app.fatalError!);
    if (!app.ready) return SplashScreen(progress: app.packProgress);

    // أثناء الملاحة يختفي كل شيء إلا الخريطة وطبقتها: السائق ما يتصفّح
    // تبويبات وهو يسوق، وشريط التنقّل يسرق مساحة يحتاجها الطريق
    final navigating = app.navState.isActive;

    return Scaffold(
      backgroundColor: D.bg,
      body: Stack(
        children: [
          const MapCanvas(),

          if (navigating)
            NavOverlay(onStop: app.stopNavigation)
          else ...[
            Positioned.fill(child: _tabLayer()),
            Positioned(
              left: 0, right: 0, bottom: 0,
              child: _BottomNav(
                current: _tab,
                onSelect: (t) => setState(() => _tab = t),
                onReport: () => _openReport(context),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _tabLayer() => switch (_tab) {
        DarbTab.map => const MapOverlay(),
        DarbTab.traffic => const TrafficScreen(),
        DarbTab.community => const CommunityScreen(),
        DarbTab.saved => const SavedScreen(),
        DarbTab.profile => const ProfileScreen(),
      };

  void _openReport(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const ReportSheet(),
    );
  }
}

// ── شريط التنقّل السفلي ─────────────────────────────────────────────────────

class _BottomNav extends StatelessWidget {
  final DarbTab current;
  final void Function(DarbTab) onSelect;
  final VoidCallback onReport;

  const _BottomNav({
    required this.current,
    required this.onSelect,
    required this.onReport,
  });

  @override
  Widget build(BuildContext context) {
    // الترتيب من اليمين لليسار بصرياً (RTL): الخريطة أولاً كما في التصميم
    const items = [
      (DarbTab.map, Icons.map_outlined, Icons.map, 'الخريطة'),
      (DarbTab.traffic, Icons.bar_chart_outlined, Icons.bar_chart, 'الحركة'),
      (DarbTab.community, Icons.people_outline, Icons.people, 'المجتمع'),
      (DarbTab.saved, Icons.bookmark_outline, Icons.bookmark, 'المحفوظة'),
      (DarbTab.profile, Icons.person_outline, Icons.person, 'حسابي'),
    ];

    return Container(
      decoration: const BoxDecoration(
        color: D.card,
        borderRadius: BorderRadius.vertical(top: Radius.circular(D.rSheet)),
        boxShadow: [
          BoxShadow(color: Color(0x18000000), blurRadius: 24,
              offset: Offset(0, -4)),
        ],
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 66,
          child: Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.center,
            children: [
              Row(
                children: [
                  for (final it in items.take(2))
                    Expanded(child: _navItem(it)),
                  // فراغ لزرّ الإبلاغ العائم في الوسط
                  const SizedBox(width: 74),
                  for (final it in items.skip(2))
                    Expanded(child: _navItem(it)),
                ],
              ),

              // زرّ الإبلاغ: أسود دائري يطفو فوق الشريط. وضعه في الوسط
              // بقصد — هو الفعل الوحيد الذي يسويه السائق وهو واقف بالزحام
              Positioned(
                top: -22,
                child: _ReportFab(onTap: onReport),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _navItem((DarbTab, IconData, IconData, String) it) {
    final active = current == it.$1;
    return InkWell(
      onTap: () => onSelect(it.$1),
      borderRadius: BorderRadius.circular(14),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(active ? it.$3 : it.$2,
              size: 22, color: active ? D.greenDeep : D.textSoft),
          const SizedBox(height: 3),
          Text(it.$4,
              style: TextStyle(
                fontSize: 10.5,
                height: 1.2,
                fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                color: active ? D.greenDeep : D.textSoft,
              )),
          // الخط تحت التبويب النشط — كما في التصميم
          Container(
            margin: const EdgeInsets.only(top: 3),
            width: active ? 18 : 0,
            height: 2.5,
            decoration: BoxDecoration(
              color: D.greenDeep,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ],
      ),
    );
  }
}

class _ReportFab extends StatelessWidget {
  final VoidCallback onTap;
  const _ReportFab({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 56,
          height: 56,
          decoration: const BoxDecoration(
            color: D.ink,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(color: Color(0x33000000), blurRadius: 16,
                  offset: Offset(0, 5)),
            ],
          ),
          child: Material(
            color: Colors.transparent,
            shape: const CircleBorder(),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: onTap,
              child: const Icon(Icons.add, color: Colors.white, size: 28),
            ),
          ),
        ),
        const SizedBox(height: 2),
        const Text('إبلاغ',
            style: TextStyle(
                fontSize: 10.5, fontWeight: FontWeight.w700, color: D.text)),
      ],
    );
  }
}
