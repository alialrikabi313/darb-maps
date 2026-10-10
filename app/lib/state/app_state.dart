// الحالة المركزية: تشغيل كل القطع وربطها، وما تعرضه الشاشات.
//
// ChangeNotifier واحد لا أربعة: الشاشات كلها تقرأ من نفس الحالة (الموقع،
// المسار، البلاغات)، وتفريقها يعني تزامناً يدوياً بينها.

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:maplibre_gl/maplibre_gl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../config.dart';
import '../core/api_client.dart';
import '../core/favorites.dart';
import '../core/location_service.dart';
import '../core/packs.dart';
import '../core/search.dart' show PoiSearch, Place;
import '../core/tile_server.dart';
import '../nav/nav_engine.dart';
import '../nav/nav_service.dart';
import '../nav/phrases.dart';
import '../nav/route_model.dart';
import '../nav/voice.dart';
import '../reports/reports.dart';

/// كيف تتبع الكاميرا المستخدم.
enum CameraMode {
  /// حرّة: المستخدم حرّك الخريطة بنفسه فما نسحبها منه.
  free,

  /// تتبع الموقع من أعلى بلا ميل.
  follow,

  /// ملاحة: مائلة وقريبة وتدور مع اتجاه السيارة.
  navigate,
}

/// وجهة مختارة قبل بدء الملاحة.
class Destination {
  final String title;
  final LatLng pos;
  const Destination(this.title, this.pos);
}

class AppState extends ChangeNotifier {
  final tileServer = TileServer();
  final search = PoiSearch();
  final location = LocationService();
  final voice = Voice();
  final api = ApiClient();
  final navService = NavService();

  late final ReportsRepo reports = ReportsRepo(api);
  late final NavEngine nav = NavEngine(
      location: location, voice: voice, api: api, search: search);

  // ── حالة الإقلاع ─────────────────────────────────────────────────────────

  bool ready = false;
  String? fatalError;

  /// تقدّم تهيئة الحزمة. حزمة العراق 203MB تُلصَق من الأصول في أول تشغيل
  /// فتأخذ عشرات الثواني على تخزين بطيء — بلا رقم تبدو الشاشة معلّقة.
  PackProgress? packProgress;

  /// رسالة غير قاتلة تُعرض شريطاً: صلاحية مرفوضة، باكند واقف، نطق ناقص.
  String? notice;

  // ── الحالة الجارية ───────────────────────────────────────────────────────

  Fix? fix;
  CameraMode cameraMode = CameraMode.follow;

  Destination? destination;

  /// المسار الأساسي والبدائل بعد الحساب، قبل أن يختار المستخدم.
  NavRoute? proposed;
  List<NavRoute> alternates = const [];
  bool routing = false;
  String? routeError;

  NavState navState = const NavState();

  List<Report> visibleReports = const [];

  // ── الاستكشاف ────────────────────────────────────────────────────────────

  /// التصنيف المختار من الشرائح العلوية، أو null إذا لا شيء مختار.
  String? activeCategory;

  /// دبابيس التصنيف المعروضة على الخريطة.
  List<Place> categoryPins = const [];

  /// المكان الذي لمسه المستخدم — تُعرض بطاقته قبل اختياره وجهةً.
  Place? previewedPlace;

  bool showReportsLayer = true;
  bool showTrafficLayer = true;

  /// يبدّل تصنيف الشرائح: اختياره يعرض دبابيسه، وإعادة ضغطه تخفيها.
  Future<void> toggleCategory(String category) async {
    if (activeCategory == category) {
      activeCategory = null;
      categoryPins = const [];
      notifyListeners();
      return;
    }

    activeCategory = category;
    previewedPlace = null;
    notifyListeners();

    // 25 دبّوساً سقف: أكثر منها يغطّي الخريطة نفسها فيصير التصنيف ضرراً
    categoryPins = await search.nearby(center,
        categories: [category], radiusM: 6000, limit: 25);
    notifyListeners();
  }

  void previewPlace(Place? p) {
    previewedPlace = p;
    notifyListeners();
  }

  void setShowReportsLayer(bool v) {
    showReportsLayer = v;
    if (!v) visibleReports = const [];
    notifyListeners();
  }

  void setShowTrafficLayer(bool v) {
    showTrafficLayer = v;
    notifyListeners();
  }

  // ── المفضّلة والرحلات ────────────────────────────────────────────────────

  final _favStore = FavoritesStore();

  List<Favorite> get favorites => _favStore.favorites;
  List<Trip> get recentTrips => _favStore.trips;

  Favorite? favoriteFor(FavoriteKind kind) => _favStore.of(kind);

  Future<void> setFavorite(
      FavoriteKind kind, String title, LatLng pos) async {
    await _favStore.setFavorite(kind, title, pos);
    notifyListeners();
  }

  Future<void> removeFavorite(Favorite fav) async {
    await _favStore.removeFavorite(fav);
    notifyListeners();
  }

  // ── الإعدادات ────────────────────────────────────────────────────────────

  bool get muted => voice.muted;
  bool get traceEnabled => nav.traceEnabled;
  bool backendUp = false;

  StreamSubscription<Fix>? _fixSub;
  StreamSubscription<NavState>? _navSub;
  Timer? _reportsTimer;

  static const _kMuted = 'darb.muted';
  static const _kTrace = 'darb.trace';

  // ── الإقلاع ──────────────────────────────────────────────────────────────

  Future<void> init() async {
    try {
      final bundled = await ensureBundledPack(onProgress: (p) {
        packProgress = p;
        notifyListeners();
      });

      if (!bundled.isReady) {
        fatalError = 'حزمة الخريطة ما انتسخت — تأكد أن ملفات assets/data '
            'موجودة في التطبيق';
        notifyListeners();
        return;
      }

      packProgress = null;
      final packs = await installedPacks();
      await tileServer.start(packs);
      await search.open(packs);
    } on Object catch (e) {
      // الفشل هنا قاتل فعلاً: بلا بلاطات ولا بحث ما في تطبيق. نعرضه
      // بنصّه لأن سببه الغالب ملف ناقص، والنصّ يسمّيه
      fatalError = 'ما قدرنا نشغّل الخريطة: $e';
      notifyListeners();
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    voice.muted = prefs.getBool(_kMuted) ?? false;
    nav.traceEnabled = prefs.getBool(_kTrace) ?? Cfg.traceEnabledByDefault;
    await _favStore.load();

    await voice.init();
    if (voice.warning != null) notice = voice.warning;

    // الباكند اختياري: الخريطة والبحث والتوجيه الأساسي محلية. فشله يُعرض
    // ولا يمنع الإقلاع
    await api.init();
    backendUp = await api.ping();
    if (backendUp) await reports.loadTypes();

    ready = true;
    notifyListeners();

    await _startLocation();
    _navSub = nav.stream.listen(_onNav);
    _reportsTimer =
        Timer.periodic(const Duration(seconds: 25), (_) => _pullReports());
  }

  Future<void> _startLocation() async {
    final err = await location.requestPermission();
    if (err != null) {
      notice = err;
      notifyListeners();
      return;
    }

    await location.start();
    _fixSub = location.stream.listen((f) {
      fix = f;
      notifyListeners();
      _pullReports();
    });

    // قراءة واحدة فوراً كي تفتح الخريطة على موقع المستخدم لا على ساحة
    // التحرير — الانتظار حتى أول قراءة من التدفّق يأخذ ثواني
    try {
      final once = await location.currentOnce();
      if (once != null) {
        fix = once;
        notifyListeners();
      }
    } on Object {
      // لا قراءة سريعة: نبقى على المركز الافتراضي والتدفّق يصحّحه
    }
  }

  void _onNav(NavState s) {
    navState = s;

    if (s.isActive) {
      cameraMode = CameraMode.navigate;
      // الشاشة تبقى شغّالة أثناء الملاحة. بلاها تنطفئ بعد 30 ثانية
      // ويفوت السائق كل مناورة
      WakelockPlus.enable();
      _updateServiceNotification(s);
    } else {
      WakelockPlus.disable();
      navService.stop();
      if (s.phase == NavPhase.arrived) {
        destination = null;
        proposed = null;
        alternates = const [];
        cameraMode = CameraMode.follow;
      }
    }

    notifyListeners();
  }

  /// يضع التعليمة القادمة في إشعار الخدمة.
  ///
  /// السائق اللي قفل شاشته أو فتح واتساب يشوف «بعد 300م — انعطف يمين»
  /// في شريط الإشعارات بلا ما يرجع للتطبيق. هذا نصف قيمة الخدمة.
  void _updateServiceNotification(NavState s) {
    final m = s.next ?? s.current;
    if (m == null) return;

    final eta = s.eta == null ? '' : ' · الوصول ${arrivalLabel(s.eta!)}';

    navService.update(
      title: '${distanceLabel(s.distanceToManeuverM)} — ${maneuverTitle(m)}',
      text: '${durationLabel(s.remainingS)} · '
          '${distanceLabel(s.remainingM)}$eta',
    );
  }

  Future<void> _pullReports() async {
    if (!backendUp || !showReportsLayer) return;
    final center = fix?.pos ?? _fallbackCenter;

    final list = await reports.refresh(center,
        heading: navState.isActive ? fix?.rawHeading : null);

    visibleReports = list;
    nav.setReports(list);
    notifyListeners();
  }

  static const _fallbackCenter = LatLng(Cfg.startLat, Cfg.startLon);

  LatLng get center => fix?.pos ?? _fallbackCenter;

  /// عدّاد السرعة في وضع الاستكشاف يُعرض فقط إذا كان المستخدم يتحرك:
  /// «0 كم/س» دائماً على الشاشة ضجيج بصري بلا معنى.
  bool get speedBadgeVisible => (fix?.speedKmh ?? 0) > 5;

  // ── الوجهة والمسار ───────────────────────────────────────────────────────

  /// يُنادى حين تختار شاشة وجهةً من خارج تبويب الخريطة، كي يُعرض
  /// المسار المحسوب. بلاه كان «اذهب الآن» في المحفوظة يحسب مساراً
  /// (ونداء شبكة) ويبقى المستخدم في تبويبه وكأن الزرّ معطوب.
  VoidCallback? onDestinationChosen;

  Future<void> chooseDestination(Destination d) async {
    onDestinationChosen?.call();
    destination = d;
    stops = const [];
    previewedPlace = null;
    cameraMode = CameraMode.free;
    await recomputeRoute();
  }

  /// يعيد الحساب بالوجهة والمحطات والتفضيلات الحالية.
  ///
  /// طلب واحد يغطّي كل ما يغيّر المسار: تبديل نمط المركبة، إضافة محطة،
  /// تجنّب طريق سريع. بلاه كان كل واحد منها ينسخ نفس العشرين سطراً.
  Future<void> recomputeRoute() async {
    final d = destination;
    if (d == null) return;

    proposed = null;
    alternates = const [];
    routeError = null;
    routing = true;
    notifyListeners();

    final from = fix?.pos;
    if (from == null) {
      routing = false;
      routeError = 'ما نعرف موقعك — تأكد أن GPS شغّال';
      notifyListeners();
      return;
    }

    // رمز الطلب: المستخدم يقدر يبدّل النمط مرتين قبل ما يرجع الأول،
    // فردّ الطلب القديم كان يدهس نتيجة الجديد
    final token = ++_routeToken;

    try {
      final j = await api.route(
        points: [from, ...stops.map((s) => s.pos), d.pos],
        costing: costing,
        avoidHighways: avoidHighways,
        avoidTolls: avoidTolls,
        avoidFerries: avoidFerries,
      );
      if (token != _routeToken) return;

      proposed = NavRoute.fromTrip(
        j['trip'] as Map<String, dynamic>,
        closuresAvoided: (j['closures_avoided'] as num?)?.toInt() ?? 0,
      );
      alternates = ((j['alternates'] as List?) ?? const [])
          .map((a) => NavRoute.fromTrip(a as Map<String, dynamic>))
          .toList();
    } on ApiDown catch (e) {
      if (token != _routeToken) return;
      // التوجيه يحتاج السيرفر. نقولها صريحة بدل ما نعرض شاشة فارغة —
      // والخريطة والبحث يبقون شغّالين أوفلاين
      routeError = '${e.message} — التوجيه يحتاج اتصالاً، والخريطة والبحث '
          'يشتغلون بلاه';
    } on ApiRejected catch (e) {
      if (token != _routeToken) return;
      routeError = e.message;
    }

    if (token != _routeToken) return;
    routing = false;
    notifyListeners();
  }

  void clearDestination() {
    destination = null;
    stops = const [];
    proposed = null;
    alternates = const [];
    routeError = null;
    cameraMode = CameraMode.follow;
    // إبطال أي طلب طائر: رجوعه بعد الإلغاء كان يرجّع ورقة المسار لوجهة
    // المستخدم ألغاها
    _routeToken++;
    notifyListeners();
  }

  // ── المحطات وتفضيلات المسار ──────────────────────────────────────────────

  int _routeToken = 0;

  /// محطات بين الموقع والوجهة، بترتيب المرور.
  List<Destination> stops = const [];

  /// نمط المركبة. ڤالهالا يسمّيه costing — نُبقي اسمه كما هو كي لا يفترق
  /// الاسم بين الطبقات
  String costing = 'auto';

  bool avoidHighways = false;
  bool avoidTolls = false;
  bool avoidFerries = false;

  /// سقف المحطات: السيرفر يقبل عشر نقاط، منها البداية والوجهة
  static const int maxStops = 8;

  Future<void> setCosting(String c) async {
    if (costing == c) return;
    costing = c;
    notifyListeners();
    await recomputeRoute();
  }

  Future<void> setAvoid({bool? highways, bool? tolls, bool? ferries}) async {
    avoidHighways = highways ?? avoidHighways;
    avoidTolls = tolls ?? avoidTolls;
    avoidFerries = ferries ?? avoidFerries;
    notifyListeners();
    await recomputeRoute();
  }

  Future<void> addStop(Destination s) async {
    if (stops.length >= maxStops) {
      notice = 'أقصى عدد محطات $maxStops';
      notifyListeners();
      return;
    }
    stops = [...stops, s];
    notifyListeners();
    await recomputeRoute();
  }

  Future<void> removeStop(int index) async {
    if (index < 0 || index >= stops.length) return;
    stops = [...stops]..removeAt(index);
    notifyListeners();
    await recomputeRoute();
  }

  Future<void> reorderStops(int oldIndex, int newIndex) async {
    if (oldIndex < 0 || oldIndex >= stops.length) return;
    final list = [...stops];
    final item = list.removeAt(oldIndex);
    // onReorderItem يسلّم الفهرس مصحَّحاً بعد الحذف، فلا تصحيح هنا
    list.insert(newIndex.clamp(0, list.length), item);
    stops = list;
    notifyListeners();
    await recomputeRoute();
  }

  /// يختار بديلاً فيصير هو الأساسي.
  void pickAlternate(int index) {
    if (index < 0 || index >= alternates.length) return;
    final picked = alternates[index];
    final rest = [...alternates]..removeAt(index);
    if (proposed != null) rest.insert(0, proposed!);
    proposed = picked;
    alternates = rest;
    notifyListeners();
  }

  Future<void> startNavigation() async {
    final route = proposed;
    final dest = destination;
    if (route == null || dest == null) return;

    // الخدمة قبل الملاحة: بدؤها بعدها يعني نافذة ثوانٍ يقدر النظام يقتل
    // فيها العملية إن كان المستخدم صغّر التطبيق فوراً
    final warning = await navService.requestPermissions();
    if (warning != null) {
      notice = warning;
      notifyListeners();
    }

    final started = await navService.start(
      title: 'الملاحة شغّالة',
      text: 'نحضّر الطريق إلى ${dest.title}',
    );

    // الخدمة ما اشتغلت: نكمل الملاحة على كل حال ونقول للمستخدم إنها
    // راح تتوقّف لو صغّر التطبيق. منعه من الملاحة أسوأ
    if (!started) {
      notice = 'ما قدرنا نشغّل خدمة الخلفية — الملاحة راح تتوقّف إذا '
          'صغّرت التطبيق أو قفلت الشاشة';
      notifyListeners();
    }

    // الرحلة تُسجَّل عند الانطلاق لا عند الوصول: السائق قد يغيّر رأيه
    // في الطريق، والوجهة التي قصدها تبقى مفيدة اختصاراً
    await _favStore.recordTrip(
        dest.title, previewedPlace?.category ?? 'place', dest.pos);

    await nav.start(route, dest.pos);
  }

  Future<void> stopNavigation() async {
    await nav.stop();
    await navService.stop();
    clearDestination();
  }

  // ── البلاغات ─────────────────────────────────────────────────────────────

  /// يرسل بلاغاً عند موقع المستخدم. يرجّع رسالة خطأ أو null عند النجاح.
  Future<String?> sendReport(String kind, {String? note}) async {
    final here = fix;
    if (here == null) return 'ما نعرف موقعك — تأكد أن GPS شغّال';

    try {
      await reports.send(
        kind: kind,
        pos: here.pos,
        // اتجاه المُبلِّغ من GPS الخام لا المنعَّم: المنعَّم متأخّر عن
        // الحقيقة بثانية، والبلاغ الموجّه يُفلتر باتجاهه
        heading: here.speedKmh >= Cfg.headingFromGpsMinSpeedKmh
            ? here.rawHeading
            : null,
        note: note,
      );
      visibleReports = reports.nearby;
      nav.setReports(visibleReports);
      notifyListeners();
      return null;
    } on ApiDown catch (e) {
      return e.message;
    } on ApiRejected catch (e) {
      return e.message;
    }
  }

  Future<String?> voteReport(int id, {required bool isUp}) async {
    try {
      await reports.vote(id, isUp: isUp);
      visibleReports = reports.nearby;
      nav.setReports(visibleReports);
      notifyListeners();
      return null;
    } on ApiDown catch (e) {
      return e.message;
    } on ApiRejected catch (e) {
      return e.message;
    }
  }

  // ── الإعدادات ────────────────────────────────────────────────────────────

  Future<void> setMuted(bool v) async {
    voice.muted = v;
    if (v) await voice.stop();
    (await SharedPreferences.getInstance()).setBool(_kMuted, v);
    notifyListeners();
  }

  Future<void> setTraceEnabled(bool v) async {
    nav.traceEnabled = v;
    (await SharedPreferences.getInstance()).setBool(_kTrace, v);
    notifyListeners();
  }

  void setCameraMode(CameraMode m) {
    cameraMode = m;
    notifyListeners();
  }

  void dismissNotice() {
    notice = null;
    notifyListeners();
  }

  @override
  Future<void> dispose() async {
    _reportsTimer?.cancel();
    await _fixSub?.cancel();
    await _navSub?.cancel();
    await nav.dispose();
    await location.dispose();
    await search.close();
    await tileServer.stop();
    api.dispose();
    await WakelockPlus.disable();
    super.dispose();
  }
}
