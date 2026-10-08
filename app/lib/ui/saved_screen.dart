// تبويب المحفوظة: الأماكن المفضّلة، الرحلات المتكرّرة، اختصارات سريعة.
//
// كل ما هنا محلي على الجهاز: الأماكن المفضّلة في SharedPreferences
// والرحلات مستنتَجة منها. لا حساب ولا مزامنة — التطبيق يشتغل بلا تسجيل.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/favorites.dart';
import '../core/search.dart';
import '../nav/phrases.dart';
import '../state/app_state.dart';
import 'place_card.dart';
import 'search_screen.dart';
import 'theme.dart';

/// اختصارات التصنيفات أسفل الشاشة — نفس ترتيب التصميم.
const _shortcuts = <(String, String, IconData)>[
  ('fuel', 'محطات الوقود', Icons.local_gas_station),
  ('restaurant', 'مطاعم', Icons.restaurant),
  ('mosque', 'معالم', Icons.mosque),
  ('market', 'أسواق', Icons.shopping_bag),
  ('hospital', 'مستشفيات', Icons.local_hospital),
];

class SavedScreen extends StatelessWidget {
  const SavedScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();

    return _SheetScaffold(
      title: 'المحفوظة',
      subtitle: 'أماكنك ورحلاتك المتكرّرة',
      icon: Icons.bookmark,
      children: [
        DSectionHeader(
          title: 'أماكني المفضّلة',
          icon: Icons.star_rounded,
          actionLabel: app.favorites.isEmpty ? null : 'عرض الكل',
          onAction: () {},
        ),
        const SizedBox(height: 10),
        _FavoritesRow(app: app),

        const SizedBox(height: 22),
        DSectionHeader(
          title: 'رحلاتي المتكرّرة',
          subtitle: app.recentTrips.isEmpty
              ? 'تظهر هنا بعد أول رحلة'
              : 'انطلق بلمسة واحدة',
          icon: Icons.history,
        ),
        const SizedBox(height: 10),
        if (app.recentTrips.isEmpty)
          const _Empty(
            icon: Icons.route_outlined,
            text: 'ما في رحلات بعد. كل وجهة تروحها تُحفَظ هنا تلقائياً.',
          )
        else
          for (final t in app.recentTrips) ...[
            _TripRow(trip: t),
            const SizedBox(height: 8),
          ],

        const SizedBox(height: 22),
        const DSectionHeader(
            title: 'اختصارات سريعة', icon: Icons.bolt_rounded),
        const SizedBox(height: 10),
        const _ShortcutsRow(),
      ],
    );
  }
}

class _FavoritesRow extends StatelessWidget {
  final AppState app;
  const _FavoritesRow({required this.app});

  @override
  Widget build(BuildContext context) {
    final home = app.favoriteFor(FavoriteKind.home);
    final work = app.favoriteFor(FavoriteKind.work);

    return Row(
      children: [
        Expanded(
          child: _FavTile(
            icon: Icons.home_rounded,
            title: 'المنزل',
            subtitle: home?.title ?? 'أضفه',
            filled: home != null,
            onTap: () => _setOrGo(context, FavoriteKind.home, home),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _FavTile(
            icon: Icons.work_rounded,
            title: 'العمل',
            subtitle: work?.title ?? 'أضفه',
            filled: work != null,
            onTap: () => _setOrGo(context, FavoriteKind.work, work),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _FavTile(
            icon: Icons.add_rounded,
            title: 'الأماكن المحفوظة',
            subtitle: '${app.favorites.length} مكان',
            filled: false,
            onTap: () => _addFavorite(context),
          ),
        ),
      ],
    );
  }

  Future<void> _setOrGo(
      BuildContext context, FavoriteKind kind, Favorite? existing) async {
    final app = context.read<AppState>();

    if (existing != null) {
      await app.chooseDestination(Destination(existing.title, existing.pos));
      return;
    }

    final picked = await Navigator.of(context).push<Destination>(
        MaterialPageRoute(builder: (_) => const SearchScreen()));
    if (picked == null) return;
    await app.setFavorite(kind, picked.title, picked.pos);
  }

  Future<void> _addFavorite(BuildContext context) async {
    final app = context.read<AppState>();
    final picked = await Navigator.of(context).push<Destination>(
        MaterialPageRoute(builder: (_) => const SearchScreen()));
    if (picked == null) return;
    await app.setFavorite(FavoriteKind.other, picked.title, picked.pos);
  }
}

class _FavTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool filled;
  final VoidCallback onTap;

  const _FavTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.filled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return DCard(
      radius: D.rTile,
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
      onTap: onTap,
      child: Column(
        children: [
          DIconCircle(icon,
              size: 46,
              background: filled ? D.mint : D.mintLight,
              foreground: filled ? D.ink : D.greenDeep),
          const SizedBox(height: 9),
          Text(title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: D.h3.copyWith(fontSize: 13.5)),
          const SizedBox(height: 2),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Flexible(
                child: Text(subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: D.caption),
              ),
              if (filled) ...[
                const SizedBox(width: 3),
                const Icon(Icons.place, size: 11, color: D.textSoft),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _TripRow extends StatelessWidget {
  final Trip trip;
  const _TripRow({required this.trip});

  @override
  Widget build(BuildContext context) {
    final app = context.read<AppState>();

    return DCard(
      color: D.cardInner,
      shadow: const [],
      radius: D.rInner,
      padding: const EdgeInsets.fromLTRB(10, 10, 12, 10),
      child: Row(
        children: [
          DCard(
            radius: D.rPill,
            color: D.mint,
            shadow: const [],
            padding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
            onTap: () => app.chooseDestination(
                Destination(trip.title, trip.pos)),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('اذهب الآن',
                    style: D.h3.copyWith(
                        fontSize: 12.5, color: D.greenDeep)),
                const SizedBox(width: 6),
                const Icon(Icons.near_me, size: 14, color: D.greenDeep),
              ],
            ),
          ),
          const Spacer(),
          Expanded(
            flex: 5,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(trip.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: D.h3),
                Text(
                  trip.lastWentAt == null
                      ? 'محفوظة'
                      : 'آخر مرة ${_ago(trip.lastWentAt!)}',
                  style: D.caption,
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          DIconCircle(placeIcon(trip.category), size: 38),
        ],
      ),
    );
  }

  static String _ago(DateTime t) {
    final d = DateTime.now().difference(t);
    if (d.inMinutes < 60) return 'قبل ${d.inMinutes} دقيقة';
    if (d.inHours < 24) return 'قبل ${d.inHours} ساعة';
    return 'قبل ${d.inDays} يوم';
  }
}

class _ShortcutsRow extends StatelessWidget {
  const _ShortcutsRow();

  @override
  Widget build(BuildContext context) {
    final app = context.read<AppState>();

    return SizedBox(
      height: 92,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: _shortcuts.length,
        separatorBuilder: (_, _) => const SizedBox(width: 10),
        itemBuilder: (_, i) {
          final s = _shortcuts[i];
          return SizedBox(
            width: 86,
            child: DCard(
              radius: D.rTile,
              color: D.cardInner,
              shadow: const [],
              padding: const EdgeInsets.symmetric(vertical: 12),
              onTap: () => _openCategory(context, app, s.$1),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  DIconCircle(s.$3, size: 40, foreground: D.greenDeep),
                  const SizedBox(height: 7),
                  Text(s.$2,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: D.caption.copyWith(color: D.text)),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _openCategory(
      BuildContext context, AppState app, String category) async {
    final hits = await app.search.nearby(app.center,
        categories: [category], radiusM: 8000, limit: 20);
    if (!context.mounted || hits.isEmpty) return;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _NearbyList(places: hits, category: category),
    );
  }
}

class _NearbyList extends StatelessWidget {
  final List<Place> places;
  final String category;

  const _NearbyList({required this.places, required this.category});

  @override
  Widget build(BuildContext context) {
    final app = context.read<AppState>();

    return Container(
      constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.7),
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
            title: categoryLabels[category] ?? category,
            subtitle: '${places.length} قريبة منك',
            icon: placeIcon(category),
          ),
          const SizedBox(height: 10),
          Flexible(
            child: ListView.separated(
              shrinkWrap: true,
              itemCount: places.length,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (_, i) {
                final p = places[i];
                return DCard(
                  color: D.cardInner,
                  shadow: const [],
                  radius: D.rInner,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 11),
                  onTap: () {
                    Navigator.of(context).pop();
                    app.chooseDestination(Destination(p.title, p.pos));
                  },
                  child: Row(
                    children: [
                      if (p.distanceM != null)
                        Text(distanceLabel(p.distanceM!),
                            style: D.caption.copyWith(color: D.greenDeep)),
                      const Spacer(),
                      Expanded(
                        flex: 5,
                        child: Text(p.title,
                            textAlign: TextAlign.right,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: D.body
                                .copyWith(fontWeight: FontWeight.w600)),
                      ),
                      const SizedBox(width: 10),
                      DIconCircle(placeIcon(p.category), size: 36),
                    ],
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

class _Empty extends StatelessWidget {
  final IconData icon;
  final String text;

  const _Empty({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) => DCard(
        color: D.cardInner,
        shadow: const [],
        radius: D.rInner,
        padding: const EdgeInsets.symmetric(vertical: 22, horizontal: 16),
        child: Column(
          children: [
            DIconCircle(icon, size: 44, foreground: D.textSoft),
            const SizedBox(height: 10),
            Text(text, textAlign: TextAlign.center, style: D.bodySoft),
          ],
        ),
      );
}

// ── هيكل مشترك لتبويبات الورقة ─────────────────────────────────────────────

/// ورقة تغطّي الخريطة جزئياً، بعنوان ثابت ومحتوى يمرّر.
///
/// مشتركة بين المحفوظة والمجتمع والحركة وحسابي: الأربعة بنفس الشكل في
/// التصميم — خريطة أعلى وورقة بيضاء تحتها.
class _SheetScaffold extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final List<Widget> children;

  const _SheetScaffold({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.children,
  });

  @override
  Widget build(BuildContext context) =>
      SheetScaffold(title: title, subtitle: subtitle, icon: icon,
          children: children);
}

class SheetScaffold extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final List<Widget> children;

  const SheetScaffold({
    super.key,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    final pad = MediaQuery.of(context).padding;

    return Column(
      children: [
        // نافذة الخريطة أعلى الورقة — تُترك شفافة ليُرى ما تحتها
        SizedBox(height: pad.top + 96),

        Expanded(
          child: Container(
            decoration: const BoxDecoration(
              color: D.card,
              borderRadius:
                  BorderRadius.vertical(top: Radius.circular(D.rSheet)),
              boxShadow: [
                BoxShadow(color: Color(0x1A000000), blurRadius: 28,
                    offset: Offset(0, -6)),
              ],
            ),
            child: Column(
              children: [
                const Padding(
                  padding: EdgeInsets.only(top: 12),
                  child: DGrabber(),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                  child: DSectionHeader(
                      title: title, subtitle: subtitle, icon: icon),
                ),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 110),
                    children: children,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
