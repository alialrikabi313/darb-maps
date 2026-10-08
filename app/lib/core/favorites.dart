// الأماكن المفضّلة والرحلات الأخيرة.
//
// محلية على الجهاز في SharedPreferences، بلا حساب ولا مزامنة: التطبيق
// يشتغل بلا تسجيل، وربط المنزل والعمل بحساب على سيرفرنا يعني أننا نعرف
// وين يسكن المستخدم ووين يشتغل — وهي أخطر معلومة في تطبيق ملاحة.

import 'dart:convert';

import 'package:maplibre_gl/maplibre_gl.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum FavoriteKind { home, work, other }

class Favorite {
  final FavoriteKind kind;
  final String title;
  final LatLng pos;

  const Favorite({
    required this.kind,
    required this.title,
    required this.pos,
  });

  Map<String, dynamic> toJson() => {
        'kind': kind.name,
        'title': title,
        'lat': pos.latitude,
        'lon': pos.longitude,
      };

  factory Favorite.fromJson(Map<String, dynamic> j) => Favorite(
        kind: FavoriteKind.values.firstWhere(
            (k) => k.name == j['kind'],
            orElse: () => FavoriteKind.other),
        title: j['title'] as String,
        pos: LatLng((j['lat'] as num).toDouble(),
            (j['lon'] as num).toDouble()),
      );
}

/// وجهة ذهب إليها المستخدم سابقاً.
class Trip {
  final String title;
  final String category;
  final LatLng pos;
  final DateTime? lastWentAt;

  const Trip({
    required this.title,
    required this.category,
    required this.pos,
    this.lastWentAt,
  });

  Map<String, dynamic> toJson() => {
        'title': title,
        'category': category,
        'lat': pos.latitude,
        'lon': pos.longitude,
        'at': lastWentAt?.toIso8601String(),
      };

  factory Trip.fromJson(Map<String, dynamic> j) => Trip(
        title: j['title'] as String,
        category: j['category'] as String? ?? 'place',
        pos: LatLng((j['lat'] as num).toDouble(),
            (j['lon'] as num).toDouble()),
        lastWentAt:
            j['at'] == null ? null : DateTime.tryParse(j['at'] as String),
      );
}

class FavoritesStore {
  static const _kFavorites = 'darb.favorites';
  static const _kTrips = 'darb.trips';

  /// سقف الرحلات المحفوظة. أكثر منها يصير تاريخاً لا اختصاراً، ويطيل
  /// قائمةً المفروض يُقرأ منها بنظرة
  static const _maxTrips = 8;

  List<Favorite> favorites = const [];
  List<Trip> trips = const [];

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();

    favorites = _decode(prefs.getString(_kFavorites))
        .map(Favorite.fromJson)
        .toList();
    trips = _decode(prefs.getString(_kTrips)).map(Trip.fromJson).toList();
  }

  List<Map<String, dynamic>> _decode(String? raw) {
    if (raw == null || raw.isEmpty) return const [];
    return (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
  }

  Favorite? of(FavoriteKind kind) {
    for (final f in favorites) {
      if (f.kind == kind) return f;
    }
    return null;
  }

  Future<void> setFavorite(
      FavoriteKind kind, String title, LatLng pos) async {
    final next = [
      // المنزل والعمل واحد لكل منهما: الثاني يستبدل الأول. «أماكن أخرى»
      // تتراكم لأنها قائمة فعلاً
      if (kind == FavoriteKind.other) ...favorites
      else ...favorites.where((f) => f.kind != kind),
      Favorite(kind: kind, title: title, pos: pos),
    ];

    favorites = next;
    await _save(_kFavorites, next.map((f) => f.toJson()).toList());
  }

  Future<void> removeFavorite(Favorite fav) async {
    favorites = favorites
        .where((f) => !(f.kind == fav.kind && f.title == fav.title))
        .toList();
    await _save(_kFavorites, favorites.map((f) => f.toJson()).toList());
  }

  /// يسجّل وجهة ذهب إليها المستخدم. الوجهة المكرّرة ترتفع لأعلى القائمة
  /// بدل ما تتكرّر فيها.
  Future<void> recordTrip(String title, String category, LatLng pos) async {
    final now = DateTime.now();
    final rest = trips.where((t) => t.title != title).take(_maxTrips - 1);

    trips = [
      Trip(title: title, category: category, pos: pos, lastWentAt: now),
      ...rest,
    ];
    await _save(_kTrips, trips.map((t) => t.toJson()).toList());
  }

  Future<void> _save(String key, List<Map<String, dynamic>> value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(key, jsonEncode(value));
  }
}
