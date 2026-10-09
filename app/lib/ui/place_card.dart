// بطاقة المكان المعاين فوق الخريطة.
//
// لا صور للأماكن: OSM ما يحمل صوراً، وجلبها من خدمة خارجية يكسر
// الأوفلاين. فنضع دائرة أيقونة التصنيف مكان الصورة بنفس حجمها وشكلها في
// التصميم، ونملأ المساحة بما نملكه فعلاً: التصنيف والمسافة والعنوان.

import 'package:flutter/material.dart';

import '../core/search.dart';
import '../nav/phrases.dart';
import 'icon_images.dart' show poiImageName;
import 'theme.dart';

/// أيقونة لكل تصنيف — نفس خريطة الدبابيس كي لا تختلف البطاقة عن الخريطة.
IconData placeIcon(String category) => switch (category) {
      'restaurant' => Icons.restaurant,
      'cafe' => Icons.local_cafe,
      'pharmacy' => Icons.local_pharmacy,
      'fuel' => Icons.local_gas_station,
      'hospital' => Icons.local_hospital,
      'mosque' => Icons.mosque,
      'market' => Icons.shopping_bag,
      'school' || 'university' => Icons.school,
      'bank' => Icons.account_balance,
      'hotel' => Icons.hotel,
      'park' => Icons.park,
      'car_service' => Icons.car_repair,
      'government' => Icons.account_balance_outlined,
      'transport' => Icons.directions_bus,
      'place' => Icons.location_city,
      'street' => Icons.add_road,
      _ => Icons.place,
    };

class PlaceCard extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final tags = place.tags;
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
                onTap: onClose,
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
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: D.mintLight,
                  borderRadius: BorderRadius.circular(D.rInner),
                ),
                child: Icon(placeIcon(place.category),
                    color: D.greenDeep, size: 26),
              ),
            ],
          ),

          const SizedBox(height: 12),

          Row(
            children: [
              Expanded(
                child: DBigButton(
                  label: 'اتجاهات',
                  icon: Icons.near_me,
                  onTap: onDirections,
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
                      const Icon(Icons.directions_car,
                          size: 18, color: D.greenDeep),
                    ],
                  ),
                ),
            ],
          ),

          if (tags['phone'] != null || tags['opening_hours'] != null) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                if (tags['opening_hours'] != null)
                  Expanded(
                    child: _Detail(
                      icon: Icons.schedule,
                      text: '${tags['opening_hours']}',
                    ),
                  ),
                if (tags['phone'] != null)
                  Expanded(
                    child: _Detail(
                      icon: Icons.phone,
                      text: '${tags['phone']}',
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
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
