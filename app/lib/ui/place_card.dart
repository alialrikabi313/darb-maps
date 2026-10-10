// بطاقة المكان المعاين فوق الخريطة.
//
// الصورة: بياناتنا ما فيها صور — فحصنا 144,659 نقطة فما في واحدة تحمل
// وسم image. من يحمل wikimedia_commons أو wikidata نجيب له مصغّرة من
// كومنز (وهي قلّة: معالم مشهورة لا مطاعم)، والباقي يأخذ لوحة أيقونة
// بنفس حجم الصورة وشكلها كي لا تتبدّل هندسة البطاقة بين مكان وآخر.
//
// التقييم (٤٫٨ ★) في المرئي ما له مصدر عندنا إطلاقاً: OSM ما يقيّم،
// و Overture ما تعطي درجات. فلا نعرضه — رقم مخترع في بطاقة مطعم يوجّه
// قرار إنسان، وهذا أسوأ من خانة فاضية.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../core/api_client.dart' show ApiDown, ApiRejected;
import '../core/favorites.dart';
import '../core/search.dart';
import '../nav/phrases.dart';
import '../state/app_state.dart';
import 'icon_images.dart' show poiImageName;
import 'route_options_sheet.dart' show modeIcon;
import 'theme.dart';

/// أيقونة لكل تصنيف — نفس خريطة الدبابيس كي لا تختلف البطاقة عن الخريطة.
IconData placeIcon(String category) => switch (category) {
      'restaurant' => Icons.restaurant,
      'pharmacy' => Icons.local_pharmacy,
      'fuel' => Icons.local_gas_station,
      'hospital' => Icons.local_hospital,
      'mosque' => Icons.mosque,
      'market' => Icons.shopping_bag,
      'school' || 'university' => Icons.school,
      'bank' => Icons.account_balance,
      'hotel' => Icons.hotel,
      'park' => Icons.park,
      'parking' => Icons.local_parking,
      'car_service' => Icons.car_repair,
      'government' => Icons.account_balance_outlined,
      'transport' => Icons.directions_bus,
      'place' => Icons.location_city,
      'street' => Icons.add_road,
      _ => Icons.place,
    };

/// أنماط التنقّل المعروضة في البطاقة، بترتيب المرئي.
const _cardModes = <(String, String)>[
  ('auto', 'سيارة'),
  ('bus', 'حافلة'),
  ('pedestrian', 'مشياً'),
  ('bicycle', 'دراجة'),
];

class PlaceCard extends StatefulWidget {
  final Place place;
  final VoidCallback onDirections;
  final VoidCallback onClose;

  const PlaceCard({
    super.key,
    required this.place,
    required this.onDirections,
    required this.onClose,
  });

  @override
  State<PlaceCard> createState() => _PlaceCardState();
}

class _PlaceCardState extends State<PlaceCard> {
  /// زمن كل نمط. ما نحسبها كلها دفعة: أربعة طلبات توجيه على كل لمسة
  /// دبّوس تخنق السيرفر وتصرف بطارية بلا أن ينظر المستخدم لثلاثة منها.
  /// النمط الذي يضغطه يُحسب وحده
  final Map<String, double?> _eta = {};
  final Set<String> _pending = {};
  String _mode = 'auto';

  List<Place> _parking = const [];
  List<Place> _fuel = const [];

  @override
  void initState() {
    super.initState();
    _loadNearby();
    _fetchEta('auto');
  }

  @override
  void didUpdateWidget(PlaceCard old) {
    super.didUpdateWidget(old);
    if (old.place.pos != widget.place.pos) {
      _eta.clear();
      _pending.clear();
      _mode = 'auto';
      _loadNearby();
      _fetchEta('auto');
    }
  }

  Future<void> _loadNearby() async {
    final app = context.read<AppState>();
    // نصف كيلومتر للموقف: أبعد منه يُمشى لا يُركن. وكيلومتران للوقود
    // لأن من ينتهي بنزينه يقبل انحرافاً
    final p = await app.search
        .nearby(widget.place.pos, categories: ['parking'], radiusM: 700);
    final f = await app.search
        .nearby(widget.place.pos, categories: ['fuel'], radiusM: 2000);
    if (!mounted) return;
    setState(() {
      _parking = p;
      _fuel = f;
    });
  }

  Future<void> _fetchEta(String costing) async {
    if (_eta.containsKey(costing) || _pending.contains(costing)) return;
    final app = context.read<AppState>();
    final from = app.fix?.pos;
    if (from == null) return;

    setState(() => _pending.add(costing));
    double? seconds;
    try {
      final j = await app.api.route(
        points: [from, widget.place.pos],
        costing: costing,
        alternates: 0,
      );
      final s = ((j['trip'] as Map?)?['summary'] as Map?);
      seconds = (s?['time_with_traffic'] as num?)?.toDouble() ??
          (s?['time'] as num?)?.toDouble();
    } on ApiDown {
      // بلا اتصال ما في زمن. الخانة تبقى «—» ولا نكتب رسالة خطأ في بطاقة
      // بحجم كفّ اليد
      seconds = null;
    } on ApiRejected {
      seconds = null;
    }

    if (!mounted) return;
    setState(() {
      _eta[costing] = seconds;
      _pending.remove(costing);
    });
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final place = widget.place;
    final tags = place.tags;
    final saved = app.favorites.any((f) =>
        f.pos.latitude == place.pos.latitude &&
        f.pos.longitude == place.pos.longitude);

    final subtitle = [
      categoryLabels[place.category] ?? place.category,
      if (tags['addr:street'] != null) '${tags['addr:street']}',
    ].join(' · ');

    return DCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              DMapButton(
                icon: Icons.close,
                tooltip: 'إغلاق',
                onTap: widget.onClose,
                size: 34,
                background: D.cardInner,
              ),
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
                        style: D.h2),
                    const SizedBox(height: 2),
                    Text(subtitle,
                        textAlign: TextAlign.right,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: D.bodySoft),
                    Text(place.sourceLabel,
                        textAlign: TextAlign.right,
                        style: D.caption.copyWith(color: D.textFaint)),
                    if (place.subtitle != null)
                      Text(place.subtitle!,
                          textAlign: TextAlign.right,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: D.caption),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              _Thumb(place: place),
            ],
          ),

          const SizedBox(height: 12),

          Row(
            children: [
              Expanded(
                child: _ActionChip(
                  label: saved ? 'محفوظ' : 'حفظ',
                  icon: saved ? Icons.bookmark : Icons.bookmark_border,
                  filled: saved,
                  onTap: () => _toggleSave(app, saved),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _ActionChip(
                  label: 'مشاركة',
                  icon: Icons.ios_share,
                  onTap: () => _share(place),
                ),
              ),
              if (tags['phone'] != null) ...[
                const SizedBox(width: 8),
                Expanded(
                  child: _ActionChip(
                    label: 'اتصال',
                    icon: Icons.phone,
                    onTap: () => _share(place, phone: '${tags['phone']}'),
                  ),
                ),
              ],
            ],
          ),

          const SizedBox(height: 12),

          _ModeStrip(
            selected: _mode,
            eta: _eta,
            pending: _pending,
            onPick: (m) {
              setState(() => _mode = m);
              _fetchEta(m);
            },
          ),

          if (_parking.isNotEmpty || _fuel.isNotEmpty) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                if (_parking.isNotEmpty)
                  Expanded(
                    child: _NearbyCard(
                      title: 'مواقف قريبة',
                      icon: Icons.local_parking,
                      count: _parking.length,
                      nearestM: _parking.first.distanceM,
                      unit: 'موقف',
                    ),
                  ),
                if (_parking.isNotEmpty && _fuel.isNotEmpty)
                  const SizedBox(width: 8),
                if (_fuel.isNotEmpty)
                  Expanded(
                    child: _NearbyCard(
                      title: 'محطات وقود',
                      icon: Icons.local_gas_station,
                      count: _fuel.length,
                      nearestM: _fuel.first.distanceM,
                      unit: 'محطة',
                    ),
                  ),
              ],
            ),
          ],

          const SizedBox(height: 12),

          Row(
            children: [
              Expanded(
                child: DBigButton(
                  label: 'اتجاهات',
                  icon: Icons.near_me,
                  onTap: () {
                    // النمط المختار في البطاقة ينتقل للمسار: من ضغط
                    // «مشياً» ثم «اتجاهات» ما يبي مساراً بالسيارة
                    app.costing = _mode;
                    widget.onDirections();
                  },
                ),
              ),
              const SizedBox(width: 10),
              if (place.distanceM != null)
                DCard(
                  radius: D.rPill,
                  color: D.mintLight,
                  shadow: const [],
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 12),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(distanceLabel(place.distanceM!),
                          style: D.h3.copyWith(color: D.greenDeep)),
                      const SizedBox(width: 7),
                      Icon(modeIcon(_mode), size: 18, color: D.greenDeep),
                    ],
                  ),
                ),
            ],
          ),

          if (tags['opening_hours'] != null || tags['fee'] != null) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                if (tags['opening_hours'] != null)
                  Expanded(
                    child: _Detail(
                        icon: Icons.schedule,
                        text: '${tags['opening_hours']}'),
                  ),
                if (tags['fee'] != null)
                  Expanded(
                    child: _Detail(
                      icon: Icons.payments_outlined,
                      text: tags['fee'] == 'no' ? 'مجاني' : 'برسوم',
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _toggleSave(AppState app, bool saved) async {
    if (saved) {
      final fav = app.favorites.firstWhere((f) =>
          f.pos.latitude == widget.place.pos.latitude &&
          f.pos.longitude == widget.place.pos.longitude);
      await app.removeFavorite(fav);
    } else {
      await app.setFavorite(
          FavoriteKind.other, widget.place.title, widget.place.pos);
    }
  }

  Future<void> _share(Place p, {String? phone}) async {
    // geo: هو ما يفتحه أي تطبيق خرائط على أندرويد. والإحداثي بست منازل
    // دقّته ~0.1 متر، وأكثر منها ضجيج
    final geo = 'geo:${p.pos.latitude.toStringAsFixed(6)},'
        '${p.pos.longitude.toStringAsFixed(6)}';
    final text = [
      p.title,
      ?phone,
      geo,
    ].join('\n');
    await SharePlus.instance.share(ShareParams(text: text, subject: p.title));
  }
}

/// لوحة الصورة. صورة كومنز إن وُجد وسمها، وإلا أيقونة التصنيف.
class _Thumb extends StatelessWidget {
  final Place place;
  const _Thumb({required this.place});

  @override
  Widget build(BuildContext context) {
    final commons = place.tags['wikimedia_commons'] ?? place.tags['image'];
    final radius = BorderRadius.circular(D.rInner);

    if (commons != null && commons.startsWith('File:')) {
      final file = Uri.encodeComponent(commons.substring(5));
      final url =
          'https://commons.wikimedia.org/wiki/Special:FilePath/$file?width=160';
      return ClipRRect(
        borderRadius: radius,
        child: Image.network(
          url,
          width: 64,
          height: 64,
          fit: BoxFit.cover,
          // الفشل صامت بقصد: بطاقة مكان ما تعرض خطأ شبكة، تعرض الأيقونة
          errorBuilder: (_, _, _) => _IconTile(place: place),
          loadingBuilder: (_, child, progress) =>
              progress == null ? child : _IconTile(place: place),
        ),
      );
    }

    return _IconTile(place: place);
  }
}

class _IconTile extends StatelessWidget {
  final Place place;
  const _IconTile({required this.place});

  @override
  Widget build(BuildContext context) => Container(
        width: 64,
        height: 64,
        decoration: BoxDecoration(
          color: D.mintLight,
          borderRadius: BorderRadius.circular(D.rInner),
        ),
        child:
            Icon(placeIcon(place.category), color: D.greenDeep, size: 28),
      );
}

class _ActionChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool filled;
  final VoidCallback onTap;

  const _ActionChip({
    required this.label,
    required this.icon,
    required this.onTap,
    this.filled = false,
  });

  @override
  Widget build(BuildContext context) => DCard(
        radius: D.rPill,
        color: filled ? D.mint : D.cardInner,
        shadow: const [],
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        onTap: onTap,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(label,
                style: D.body.copyWith(
                    fontWeight: FontWeight.w700,
                    color: filled ? D.greenDeep : D.text)),
            const SizedBox(width: 6),
            Icon(icon, size: 17, color: filled ? D.greenDeep : D.text),
          ],
        ),
      );
}

/// شريط أنماط التنقّل مع زمن كل نمط.
class _ModeStrip extends StatelessWidget {
  final String selected;
  final Map<String, double?> eta;
  final Set<String> pending;
  final ValueChanged<String> onPick;

  const _ModeStrip({
    required this.selected,
    required this.eta,
    required this.pending,
    required this.onPick,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (final m in _cardModes) ...[
          if (m != _cardModes.first) const SizedBox(width: 6),
          Expanded(
            child: DCard(
              radius: D.rPill,
              color: selected == m.$1 ? D.mint : D.cardInner,
              shadow: const [],
              padding:
                  const EdgeInsets.symmetric(horizontal: 6, vertical: 9),
              onTap: () => onPick(m.$1),
              child: Column(
                children: [
                  Icon(modeIcon(m.$1),
                      size: 18,
                      color: selected == m.$1 ? D.greenDeep : D.text),
                  const SizedBox(height: 3),
                  Text(
                    pending.contains(m.$1)
                        ? '…'
                        : eta.containsKey(m.$1)
                            ? (eta[m.$1] == null
                                ? '—'
                                : durationLabel(eta[m.$1]!)
                                    .replaceAll(' دقيقة', ' د'))
                            : m.$2,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: D.caption.copyWith(
                        fontWeight: FontWeight.w700,
                        color: selected == m.$1 ? D.greenDeep : D.textSoft),
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _NearbyCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final int count;
  final double? nearestM;
  final String unit;

  const _NearbyCard({
    required this.title,
    required this.icon,
    required this.count,
    required this.nearestM,
    required this.unit,
  });

  @override
  Widget build(BuildContext context) => DCard(
        radius: D.rInner,
        color: D.cardInner,
        shadow: const [],
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(title,
                      style: D.caption
                          .copyWith(fontWeight: FontWeight.w700, color: D.text)),
                  Text('${hd('$count')} $unit', style: D.caption),
                  if (nearestM != null)
                    Text('أقربها ${distanceLabel(nearestM!)}',
                        style: D.caption.copyWith(color: D.textFaint)),
                ],
              ),
            ),
            const SizedBox(width: 8),
            DIconCircle(icon, size: 32, foreground: D.greenDeep),
          ],
        ),
      );
}

class _Detail extends StatelessWidget {
  final IconData icon;
  final String text;

  const _Detail({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: Text(text,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.right,
                style: D.caption),
          ),
          const SizedBox(width: 5),
          Icon(icon, size: 14, color: D.textSoft),
        ],
      );
}

/// تُستخدم في شاشة البحث أيضاً كي لا تختلف أيقونة النتيجة عن الدبّوس.
String pinImageFor(String category) => poiImageName(category);
