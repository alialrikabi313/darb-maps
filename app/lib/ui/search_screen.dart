// البحث عن وجهة.
//
// محلي بالكامل — يشتغل بلا شبكة. يبدأ بعد حرفين وبتأخير قصير: استعلام
// FTS على كل حرف يُحسّ تأخّراً في الكتابة على جهاز متوسط.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../config.dart';
import '../core/favorites.dart';
import '../core/search.dart';
import '../nav/phrases.dart';
import '../state/app_state.dart';
import 'place_card.dart';
import 'theme.dart';

const _quickCategories = <(String, String, IconData)>[
  ('fuel', 'وقود', Icons.local_gas_station),
  ('hospital', 'مستشفى', Icons.local_hospital),
  ('pharmacy', 'صيدلية', Icons.local_pharmacy),
  ('restaurant', 'مطعم ومقهى', Icons.restaurant),
  ('market', 'سوق', Icons.shopping_bag),
  ('mosque', 'جامع', Icons.mosque),
];

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _controller = TextEditingController();
  Timer? _debounce;

  List<Place> _results = const [];
  bool _searching = false;
  String? _activeCategory;

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    _activeCategory = null;

    if (value.trim().length < Cfg.searchMinChars) {
      setState(() {
        _results = const [];
        _searching = false;
      });
      return;
    }

    setState(() => _searching = true);
    _debounce = Timer(Cfg.searchDebounce, () => _run(value));
  }

  Future<void> _run(String query) async {
    final app = context.read<AppState>();
    final hits = await app.search.search(query, near: app.fix?.pos);
    if (!mounted) return;
    setState(() {
      _results = hits;
      _searching = false;
    });
  }

  Future<void> _runCategory(String category) async {
    final app = context.read<AppState>();
    setState(() {
      _searching = true;
      _activeCategory = category;
      _controller.clear();
    });

    final hits = await app.search.nearby(app.center,
        categories: [category], radiusM: 8000, limit: 30);
    if (!mounted) return;
    setState(() {
      _results = hits;
      _searching = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final pad = MediaQuery.of(context).padding;

    return Scaffold(
      backgroundColor: D.bg,
      body: Column(
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(14, pad.top + 10, 14, 10),
            child: Row(
              children: [
                DMapButton(
                  icon: Icons.arrow_forward,
                  tooltip: 'رجوع',
                  onTap: () => Navigator.of(context).pop(),
                  size: 44,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: DCard(
                    radius: D.rPill,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 4),
                    child: Row(
                      children: [
                        if (_controller.text.isNotEmpty)
                          IconButton(
                            icon: const Icon(Icons.close,
                                size: 18, color: D.textSoft),
                            onPressed: () {
                              _controller.clear();
                              _onChanged('');
                            },
                            visualDensity: VisualDensity.compact,
                          ),
                        Expanded(
                          child: TextField(
                            controller: _controller,
                            autofocus: true,
                            textInputAction: TextInputAction.search,
                            onChanged: _onChanged,
                            textAlign: TextAlign.right,
                            style: D.body.copyWith(fontSize: 15),
                            decoration: const InputDecoration(
                              hintText: 'ابحث عن مكان أو شارع',
                              hintStyle: TextStyle(
                                  color: D.textSoft, fontSize: 15),
                              border: InputBorder.none,
                              isDense: true,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        const Icon(Icons.search,
                            color: D.textSoft, size: 21),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),

          SizedBox(
            height: 46,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              itemCount: _quickCategories.length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (_, i) {
                final c = _quickCategories[i];
                return DChip(
                  label: c.$2,
                  icon: c.$3,
                  selected: _activeCategory == c.$1,
                  onTap: () => _runCategory(c.$1),
                );
              },
            ),
          ),

          const SizedBox(height: 8),
          Expanded(child: _body()),
        ],
      ),
    );
  }

  Widget _body() {
    if (_searching) {
      return const Center(child: CircularProgressIndicator(color: D.green));
    }

    if (_results.isEmpty) {
      final typed = _controller.text.trim().length >= Cfg.searchMinChars;
      return typed ? const _NoResults() : const _SearchIdle();
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(14, 6, 14, 24),
      itemCount: _results.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (_, i) => _ResultRow(place: _results[i]),
    );
  }
}

class _ResultRow extends StatelessWidget {
  final Place place;
  const _ResultRow({required this.place});

  @override
  Widget build(BuildContext context) {
    final subtitle = [
      categoryLabels[place.category] ?? place.category,
      if (place.distanceM != null) distanceLabel(place.distanceM!),
      if (place.tags['addr:street'] != null) '${place.tags['addr:street']}',
    ].join(' · ');

    return DCard(
      radius: D.rInner,
      shadow: D.shadowSoft,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      onTap: () =>
          Navigator.of(context).pop(Destination(place.title, place.pos)),
      child: Row(
        children: [
          const Icon(Icons.chevron_left, color: D.textFaint),
          const Spacer(),
          Expanded(
            flex: 6,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(place.title,
                    textAlign: TextAlign.right,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: D.h3),
                Text(subtitle,
                    textAlign: TextAlign.right,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: D.caption),
                // الاسم المستنتَج معلَّم: المستخدم يصحّحه بنظرة، وإخفاء
                // أنه تخمين يجعله يثق به أكثر مما يستحق
                if (place.isInferred)
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Text(place.sourceLabel,
                          style: D.caption.copyWith(color: D.warn)),
                      const SizedBox(width: 3),
                      const Icon(Icons.help_outline,
                          size: 11, color: D.warn),
                    ],
                  ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          DIconCircle(placeIcon(place.category),
              size: 42, foreground: D.greenDeep),
        ],
      ),
    );
  }
}

/// ما قبل الكتابة: المفضّلة والرحلات الأخيرة — اختصار لأغلب البحث.
class _SearchIdle extends StatelessWidget {
  const _SearchIdle();

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final home = app.favoriteFor(FavoriteKind.home);
    final work = app.favoriteFor(FavoriteKind.work);

    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 6, 14, 24),
      children: [
        if (home != null || work != null) ...[
          const DSectionHeader(
              title: 'أماكني', icon: Icons.star_rounded),
          const SizedBox(height: 8),
          if (home != null)
            _QuickRow(
                icon: Icons.home_rounded,
                title: 'المنزل',
                subtitle: home.title,
                pos: home.pos),
          if (work != null) ...[
            const SizedBox(height: 8),
            _QuickRow(
                icon: Icons.work_rounded,
                title: 'العمل',
                subtitle: work.title,
                pos: work.pos),
          ],
          const SizedBox(height: 20),
        ],

        if (app.recentTrips.isNotEmpty) ...[
          const DSectionHeader(
              title: 'وجهات أخيرة', icon: Icons.history),
          const SizedBox(height: 8),
          for (final t in app.recentTrips.take(5)) ...[
            _QuickRow(
                icon: placeIcon(t.category),
                title: t.title,
                subtitle: 'ذهبت إليها سابقاً',
                pos: t.pos),
            const SizedBox(height: 8),
          ],
        ] else
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 40, horizontal: 20),
            child: Text(
              'اكتب اسم مكان، أو اختر تصنيفاً من الأعلى',
              textAlign: TextAlign.center,
              style: D.bodySoft,
            ),
          ),
      ],
    );
  }
}

class _QuickRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final dynamic pos;

  const _QuickRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.pos,
  });

  @override
  Widget build(BuildContext context) => DCard(
        radius: D.rInner,
        shadow: D.shadowSoft,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
        onTap: () => Navigator.of(context).pop(Destination(title, pos)),
        child: Row(
          children: [
            const Icon(Icons.chevron_left, color: D.textFaint),
            const Spacer(),
            Expanded(
              flex: 6,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(title, style: D.h3),
                  Text(subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: D.caption),
                ],
              ),
            ),
            const SizedBox(width: 10),
            DIconCircle(icon, size: 42, foreground: D.greenDeep),
          ],
        ),
      );
}

class _NoResults extends StatelessWidget {
  const _NoResults();

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(30),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const DIconCircle(Icons.search_off,
                  size: 56, foreground: D.textSoft),
              const SizedBox(height: 14),
              const Text('ما لقينا شي بهذا الاسم', style: D.h3),
              const SizedBox(height: 8),
              // نقول السبب المحتمل لا «لا نتائج» وبس: 8% فقط من طرق
              // العراق مسمّاة في OSM، وهذا أرجح سبب الفشل
              const Text(
                'جرّب اسم المنطقة أو معلماً قريباً — أسماء الشوارع ناقصة '
                'في خريطة العراق المفتوحة.',
                textAlign: TextAlign.center,
                style: D.bodySoft,
              ),
            ],
          ),
        ),
      );
}
