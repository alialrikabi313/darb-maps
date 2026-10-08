// الشاشة الرئيسية: الخريطة وكل ما يُرسم عليها، والكاميرا.
//
// الخريطة تبقى في الشجرة دائماً وما تُبنى من جديد: بناء MapLibreMap ينشئ
// platform view ويحمّل النمط من الصفر — ثانية كاملة شاشةً رمادية في كل
// مرة. فالشاشات الأخرى تُدفع فوقها لا تبدّلها، والأوضاع تتبدّل طبقاتٍ
// فوقها.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:maplibre_gl/maplibre_gl.dart';
import 'package:provider/provider.dart';

import '../config.dart';
import '../core/search.dart';
import '../nav/route_model.dart';
import '../state/app_state.dart';
import 'icon_images.dart';
import 'nav_overlay.dart';
import 'offline_screen.dart';
import 'report_sheet.dart';
import 'route_sheet.dart';
import 'search_screen.dart';
import 'settings_screen.dart';

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  MapLibreMapController? _map;
  bool _styleReady = false;

  // ما نرسمه الآن، كي نعرف ما نحتاج نزيله عند التغيير
  final List<Line> _routeLines = [];
  final Map<int, Symbol> _reportSymbols = {};
  Symbol? _carSymbol;

  /// آخر حالة رُسمت. نقارن بها بدل ما نعيد الرسم في كل notifyListeners —
  /// قراءة GPS تجي كل 5 أمتار، وإعادة رسم المسار عندها تذبح الأداء.
  NavRoute? _drawnRoute;
  int _drawnReportsHash = 0;

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();

    if (app.fatalError != null) return _FatalScreen(message: app.fatalError!);
    if (!app.ready) return const _SplashScreen();

    // الرسم بعد اكتمال الإطار: التعديل على الخريطة أثناء build يرمي
    // استثناء setState-during-build
    WidgetsBinding.instance.addPostFrameCallback((_) => _sync(app));

    final navigating = app.navState.isActive;

    return Scaffold(
      body: Stack(
        children: [
          MapLibreMap(
            styleString: app.tileServer.styleUrl,
            initialCameraPosition: CameraPosition(
              target: app.center,
              zoom: Cfg.startZoom,
            ),
            onMapCreated: (c) => _map = c,
            onStyleLoadedCallback: () => _onStyleLoaded(app),
            // سهم الموقع من MapLibre في وضع الاستكشاف: دقيق ومحسّن
            // أصلاً. أثناء الملاحة نخفيه ونرسم سهمنا على المسار المثبَّت
            myLocationEnabled: !navigating,
            myLocationRenderMode: MyLocationRenderMode.compass,
            myLocationTrackingMode: MyLocationTrackingMode.none,
            trackCameraPosition: true,
            compassEnabled: !navigating,
            logoEnabled: false,
            attributionButtonPosition: AttributionButtonPosition.bottomLeft,
            tiltGesturesEnabled: !navigating,
            rotateGesturesEnabled: !navigating,
            // المستخدم حرّك الخريطة بيده: نكفّ عن سحبها منه حتى يضغط
            // «رجّعني». إجبار التتبّع يجعل استعراض الخريطة مستحيلاً
            onCameraTrackingDismissed: () =>
                app.setCameraMode(CameraMode.free),
            onMapClick: (_, latLng) => _onMapTap(app, latLng),
          ),

          if (navigating)
            NavOverlay(onStop: () => app.stopNavigation())
          else
            _IdleOverlay(
              onSearch: () => _openSearch(app),
              onRecenter: () => app.setCameraMode(CameraMode.follow),
              onReport: () => _openReportSheet(app),
              onSettings: () => _push(const SettingsScreen()),
              onOffline: () => _push(const OfflineScreen()),
              cameraMode: app.cameraMode,
            ),

          if (app.destination != null && !navigating)
            Positioned(
              left: 0, right: 0, bottom: 0,
              child: RouteSheet(
                onStart: () => app.startNavigation(),
                onCancel: () => app.clearDestination(),
              ),
            ),

          if (app.notice != null)
            Positioned(
              left: 12, right: 12,
              top: MediaQuery.of(context).padding.top + 8,
              child: _NoticeBar(
                text: app.notice!,
                onDismiss: app.dismissNotice,
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _push(Widget screen) => Navigator.of(context)
      .push(MaterialPageRoute(builder: (_) => screen));

  Future<void> _openSearch(AppState app) async {
    final chosen = await Navigator.of(context).push<Destination>(
        MaterialPageRoute(builder: (_) => const SearchScreen()));
    if (chosen != null) await app.chooseDestination(chosen);
  }

  Future<void> _openReportSheet(AppState app) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const ReportSheet(),
    );
  }

  /// لمس الخريطة يفتح أقرب نقطة اهتمام كوجهة محتملة.
  ///
  /// نبحث في نصف قطر صغير: لمسة على فراغ ما تختار معلماً على بعد
  /// كيلومتر، وهو سلوك يبدو عشوائياً للمستخدم.
  Future<void> _onMapTap(AppState app, LatLng tapped) async {
    if (app.navState.isActive) return;

    final hits = await app.search.nearby(tapped,
        categories: categoryLabels.keys.where((k) => k != 'street').toList(),
        radiusM: 120,
        limit: 1);

    if (!mounted) return;

    if (hits.isEmpty) {
      await app.chooseDestination(Destination('نقطة على الخريطة', tapped));
    } else {
      await app.chooseDestination(Destination(hits.first.title, hits.first.pos));
    }
  }

  // ── تهيئة النمط ──────────────────────────────────────────────────────────

  Future<void> _onStyleLoaded(AppState app) async {
    final c = _map;
    if (c == null) return;

    // الصور قبل أي symbol: الرمز الذي يشير لصورة غير مسجّلة لا يُرسم
    // ولا يرمي خطأ، فتختفي العلامات بصمت
    final kinds = app.reports.types.isEmpty
        ? Cfg.alertDistanceM.keys.toList()
        : app.reports.types.map((t) => t.kind).toList();

    await registerMapImages(
        c, kinds, MediaQuery.of(context).devicePixelRatio);

    _styleReady = true;
    _drawnRoute = null;
    _drawnReportsHash = 0;
    if (mounted) _sync(app);
  }

  // ── المزامنة مع الحالة ───────────────────────────────────────────────────

  Future<void> _sync(AppState app) async {
    final c = _map;
    if (c == null || !_styleReady) return;

    await _syncRoute(c, app);
    await _syncReports(c, app);
    await _syncCar(c, app);
    await _syncCamera(c, app);
  }

  Future<void> _syncRoute(MapLibreMapController c, AppState app) async {
    final route = app.navState.route ?? app.proposed;

    if (route == _drawnRoute) return;
    _drawnRoute = route;

    if (_routeLines.isNotEmpty) {
      await c.removeLines(_routeLines);
      _routeLines.clear();
    }
    if (route == null || route.shape.length < 2) return;

    // الحاشية أولاً ثم المتن فوقها: خط واحد عريض يختفي على الطرق
    // الصفراء، والحاشية تفصله عن الخريطة بأي لون كانت
    _routeLines.add(await c.addLine(LineOptions(
      geometry: route.shape,
      lineColor: '#1B4F9C',
      lineWidth: 11.0,
      lineOpacity: 0.95,
      lineJoin: 'round',
    )));

    // المتن مقطّعاً بالزحام إن عرفناه، وبلون واحد إن لم نعرف. ما نلوّن
    // بتخمين: خط أحمر خاطئ أسوأ من خط بلا لون
    final colored = route.maneuvers
        .where((m) => m.trafficLevel != null && m.shape.length > 1);

    if (colored.isEmpty) {
      _routeLines.add(await c.addLine(LineOptions(
        geometry: route.shape,
        lineColor: '#2D7FF9',
        lineWidth: 7.0,
        lineJoin: 'round',
      )));
    } else {
      _routeLines.add(await c.addLine(LineOptions(
        geometry: route.shape,
        lineColor: '#2D7FF9',
        lineWidth: 7.0,
        lineJoin: 'round',
      )));
      for (final m in colored) {
        final argb = Cfg.trafficColors[m.trafficLevel!];
        if (argb == null) continue;
        _routeLines.add(await c.addLine(LineOptions(
          geometry: m.shape,
          lineColor: '#${(argb & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}',
          lineWidth: 7.0,
          lineJoin: 'round',
        )));
      }
    }

    // علامة الوجهة: دائرة لا دبّوس — الدبّوس يحتاج صورة مسجّلة والوجهة
    // نقطة واحدة لا تستحق صورة
    _routeLines.add(await c.addLine(LineOptions(
      geometry: [route.shape.last, route.shape.last],
      lineColor: '#111827',
      lineWidth: 14.0,
    )));
  }

  Future<void> _syncReports(MapLibreMapController c, AppState app) async {
    // الهاش من المعرّفات وأحجام المجموعات: البلاغ الذي تغيّرت أصواته
    // يتغيّر حجم مجموعته فنعيد رسمه، والبقية تبقى
    final hash = Object.hashAll(
        app.visibleReports.map((r) => '${r.id}:${r.clusterSize}'));
    if (hash == _drawnReportsHash) return;
    _drawnReportsHash = hash;

    if (_reportSymbols.isNotEmpty) {
      await c.removeSymbols(_reportSymbols.values);
      _reportSymbols.clear();
    }

    for (final r in app.visibleReports) {
      final s = await c.addSymbol(
        SymbolOptions(
          geometry: r.pos,
          iconImage: reportImageName(r.kind),
          // المرساة عند الأسفل: ذيل الدبّوس يشير للموقع الفعلي
          iconAnchor: 'bottom',
          iconSize: 1.0,
          // غير المؤكّد شفاف جزئياً: يُعرض ومعه علامة أنه غير مؤكّد،
          // لأن إخفاءه حتى التأكيد يعني أن أول مُبلِّغ لا يفيد أحداً
          iconOpacity: r.confirmed ? 1.0 : 0.65,
          textField: r.clusterSize > 1 ? '${r.clusterSize}' : null,
          textColor: '#FFFFFF',
          textSize: 11.0,
          textOffset: const Offset(0, -2.2),
          // الاسم حرفياً كما في مجلد assets/fonts: MapLibre يطلب
          // /fonts/<هذا الاسم>/<نطاق>.pbf من سيرفرنا، فأي فرق حرف
          // يعني نصّاً لا يظهر
          fontNames: const ['Noto Sans Bold'],
        ),
        {'reportId': r.id},
      );
      _reportSymbols[r.id] = s;
    }
  }

  Future<void> _syncCar(MapLibreMapController c, AppState app) async {
    final nav = app.navState;

    if (!nav.isActive || nav.snapped == null) {
      if (_carSymbol != null) {
        await c.removeSymbol(_carSymbol!);
        _carSymbol = null;
      }
      return;
    }

    // دوران السهم نسبةً للشاشة لا للخريطة: SymbolOptions ما يكشف
    // icon-rotation-alignment، والافتراضي في MapLibre للرموز النقطية هو
    // viewport. وهذا يناسبنا فعلاً — الخريطة مُدارة لاتجاه السير أثناء
    // الملاحة، فالسهم لازم يشير لأعلى الشاشة دائماً.
    // الفرق يصحّح اللحظات التي تتأخّر فيها الكاميرا عن القراءة
    final bearing = app.cameraMode == CameraMode.navigate
        ? nav.headingDeg
        : 0.0;

    final opts = SymbolOptions(
      geometry: nav.snapped,
      iconImage: carImageName,
      iconSize: 1.0,
      iconRotate: (nav.headingDeg - bearing + 360) % 360,
    );

    if (_carSymbol == null) {
      _carSymbol = await c.addSymbol(opts);
    } else {
      await c.updateSymbol(_carSymbol!, opts);
    }
  }

  Future<void> _syncCamera(MapLibreMapController c, AppState app) async {
    switch (app.cameraMode) {
      case CameraMode.free:
        return;

      case CameraMode.follow:
        final here = app.fix?.pos;
        if (here == null) return;
        await c.updateContentInsets(EdgeInsets.zero);
        await c.animateCamera(
          CameraUpdate.newCameraPosition(CameraPosition(
            target: here,
            zoom: Cfg.overviewZoom,
            tilt: Cfg.overviewTilt,
            bearing: 0,
          )),
          duration: const Duration(milliseconds: 600),
        );

      case CameraMode.navigate:
        final nav = app.navState;
        final target = nav.snapped ?? app.fix?.pos;
        if (target == null) return;

        // الإرساء: السهم في الثلث الأسفل لا في الوسط، فيرى السائق ما
        // أمامه لا ما خلفه. contentInsets تزيح مركز الكاميرا فعلياً —
        // أنظف من إزاحة الهدف للأمام حساباً، لأن الإزاحة الحسابية تغلط
        // مع تغيّر الميل والزوم
        final h = MediaQuery.of(context).size.height;
        await c.updateContentInsets(
          EdgeInsets.only(bottom: h * (Cfg.navAnchorY - 0.5) * 2),
        );

        await c.animateCamera(
          CameraUpdate.newCameraPosition(CameraPosition(
            target: target,
            zoom: Cfg.navZoom,
            tilt: Cfg.navTilt,
            bearing: nav.headingDeg,
          )),
          // 700ms: أطول من فاصل قراءات GPS (ثانية تقريباً) فتتصل الحركة
          // بلا تقطيع، وأقصر منه بما يكفي كي لا تتراكم الحركات
          duration: const Duration(milliseconds: 700),
        );
    }
  }
}

// ── طبقة الاستكشاف ─────────────────────────────────────────────────────────

class _IdleOverlay extends StatelessWidget {
  final VoidCallback onSearch;
  final VoidCallback onRecenter;
  final VoidCallback onReport;
  final VoidCallback onSettings;
  final VoidCallback onOffline;
  final CameraMode cameraMode;

  const _IdleOverlay({
    required this.onSearch,
    required this.onRecenter,
    required this.onReport,
    required this.onSettings,
    required this.onOffline,
    required this.cameraMode,
  });

  @override
  Widget build(BuildContext context) {
    final pad = MediaQuery.of(context).padding;
    final app = context.watch<AppState>();

    return Stack(
      children: [
        Positioned(
          top: pad.top + (app.notice != null ? 64 : 12),
          left: 12,
          right: 12,
          child: _SearchBar(onTap: onSearch, onSettings: onSettings),
        ),

        Positioned(
          right: 12,
          bottom: app.destination != null ? 230 : 110,
          child: Column(
            children: [
              _RoundButton(
                icon: cameraMode == CameraMode.free
                    ? Icons.gps_not_fixed
                    : Icons.gps_fixed,
                onTap: onRecenter,
                tooltip: 'رجّعني لموقعي',
              ),
              const SizedBox(height: 10),
              _RoundButton(
                icon: Icons.download_for_offline_outlined,
                onTap: onOffline,
                tooltip: 'خرائط أوفلاين',
              ),
            ],
          ),
        ),

        if (app.destination == null)
          Positioned(
            right: 16,
            bottom: 28,
            child: FloatingActionButton.large(
              onPressed: app.backendUp ? onReport : null,
              backgroundColor:
                  app.backendUp ? const Color(0xFFF2A33C) : Colors.grey,
              tooltip: app.backendUp
                  ? 'أبلِغ عن شي على الطريق'
                  : 'الإبلاغ يحتاج اتصالاً بالسيرفر',
              child: const Icon(Icons.add_alert, size: 32,
                  color: Colors.white),
            ),
          ),

        if (app.speedBadgeVisible)
          Positioned(
            left: 16,
            bottom: 28,
            child: _SpeedBadge(kmh: app.fix!.speedKmh),
          ),
      ],
    );
  }
}

class _SearchBar extends StatelessWidget {
  final VoidCallback onTap;
  final VoidCallback onSettings;

  const _SearchBar({required this.onTap, required this.onSettings});

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 6,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
          child: Row(
            children: [
              const Icon(Icons.search, color: Color(0xFF6B7280)),
              const SizedBox(width: 10),
              const Expanded(
                child: Text('وين تريد تروح؟',
                    style: TextStyle(fontSize: 16, color: Color(0xFF6B7280))),
              ),
              IconButton(
                icon: const Icon(Icons.tune, color: Color(0xFF6B7280)),
                onPressed: onSettings,
                tooltip: 'الإعدادات',
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RoundButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final String tooltip;

  const _RoundButton(
      {required this.icon, required this.onTap, required this.tooltip});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        elevation: 4,
        shape: const CircleBorder(),
        color: Colors.white,
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Icon(icon, color: const Color(0xFF374151)),
          ),
        ),
      ),
    );
  }
}

class _SpeedBadge extends StatelessWidget {
  final double kmh;
  const _SpeedBadge({required this.kmh});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 64,
      height: 64,
      decoration: BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
        boxShadow: const [
          BoxShadow(color: Color(0x33000000), blurRadius: 6, offset: Offset(0, 2))
        ],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text('${kmh.round()}',
              style: const TextStyle(
                  fontSize: 22, fontWeight: FontWeight.bold,
                  color: Color(0xFF111827))),
          const Text('كم/س',
              style: TextStyle(fontSize: 10, color: Color(0xFF6B7280))),
        ],
      ),
    );
  }
}

class _NoticeBar extends StatelessWidget {
  final String text;
  final VoidCallback onDismiss;

  const _NoticeBar({required this.text, required this.onDismiss});

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 4,
      borderRadius: BorderRadius.circular(10),
      color: const Color(0xFFFEF3C7),
      child: Padding(
        padding: const EdgeInsets.only(left: 6, right: 12, top: 8, bottom: 8),
        child: Row(
          children: [
            IconButton(
              icon: const Icon(Icons.close, size: 18),
              onPressed: onDismiss,
              visualDensity: VisualDensity.compact,
            ),
            Expanded(
              child: Text(text,
                  style: const TextStyle(
                      fontSize: 13, color: Color(0xFF78350F))),
            ),
          ],
        ),
      ),
    );
  }
}

class _SplashScreen extends StatelessWidget {
  const _SplashScreen();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: Color(0xFFEDF0F2),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('درب',
                style: TextStyle(
                    fontSize: 44, fontWeight: FontWeight.bold,
                    color: Color(0xFF2D7FF9))),
            SizedBox(height: 20),
            CircularProgressIndicator(),
            SizedBox(height: 16),
            // التهيئة تنسخ ~15MB من الأصول في أول تشغيل، فتأخذ ثواني.
            // بلا رسالة يظن المستخدم أن التطبيق معلّق
            Text('نهيّئ الخريطة…',
                style: TextStyle(color: Color(0xFF6B7280))),
          ],
        ),
      ),
    );
  }
}

class _FatalScreen extends StatelessWidget {
  final String message;
  const _FatalScreen({required this.message});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(28),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, size: 56, color: Color(0xFFD6333F)),
              const SizedBox(height: 16),
              const Text('ما قدرنا نشغّل التطبيق',
                  style: TextStyle(
                      fontSize: 20, fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              Text(message, textAlign: TextAlign.center,
                  style: const TextStyle(color: Color(0xFF6B7280))),
            ],
          ),
        ),
      ),
    );
  }
}
