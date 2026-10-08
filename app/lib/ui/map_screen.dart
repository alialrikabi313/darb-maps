// لوحة الخريطة وما يُرسم عليها، وطبقة الاستكشاف فوقها.
//
// MapCanvas مفصولة عن MapOverlay بقصد: اللوحة تبقى في الشجرة عبر كل
// التبويبات، والطبقة تتبدّل. بناء MapLibreMap من جديد يعني ثانية شاشةً
// رمادية في كل تبديل.

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:maplibre_gl/maplibre_gl.dart';
import 'package:provider/provider.dart';

import '../config.dart';
import '../core/packs.dart';
import '../core/search.dart';
import '../nav/phrases.dart';
import '../nav/route_model.dart';
import '../state/app_state.dart';
import 'icon_images.dart';
import 'place_card.dart';
import 'route_sheet.dart';
import 'search_screen.dart';
import 'theme.dart';

// ── لوحة الخريطة ───────────────────────────────────────────────────────────

class MapCanvas extends StatefulWidget {
  const MapCanvas({super.key});

  @override
  State<MapCanvas> createState() => _MapCanvasState();
}

class _MapCanvasState extends State<MapCanvas> {
  MapLibreMapController? _map;
  bool _styleReady = false;

  final List<Line> _routeLines = [];
  final Map<int, Symbol> _reportSymbols = {};
  final List<Symbol> _poiSymbols = [];
  Symbol? _carSymbol;
  Symbol? _destSymbol;

  /// آخر حالة رُسمت. نقارن بها بدل ما نعيد الرسم في كل notifyListeners —
  /// قراءة GPS تجي كل 5 أمتار، وإعادة رسم المسار عندها تذبح الأداء.
  NavRoute? _drawnRoute;
  int _drawnReportsHash = 0;
  int _drawnPoisHash = 0;

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    if (!app.ready) return const ColoredBox(color: D.bg);

    WidgetsBinding.instance.addPostFrameCallback((_) => _sync(app));
    final navigating = app.navState.isActive;

    return MapLibreMap(
      styleString: app.tileServer.styleUrl,
      initialCameraPosition: CameraPosition(
        target: app.center,
        zoom: Cfg.startZoom,
      ),
      onMapCreated: (c) => _map = c,
      onStyleLoadedCallback: () => _onStyleLoaded(app),
      // سهم الموقع من MapLibre في الاستكشاف؛ أثناء الملاحة نخفيه ونرسم
      // سهمنا على المسار المثبَّت
      myLocationEnabled: !navigating,
      myLocationRenderMode: MyLocationRenderMode.compass,
      myLocationTrackingMode: MyLocationTrackingMode.none,
      trackCameraPosition: true,
      compassEnabled: false,
      logoEnabled: false,
      attributionButtonPosition: AttributionButtonPosition.bottomLeft,
      attributionButtonMargins: const math.Point(12, 150),
      tiltGesturesEnabled: !navigating,
      rotateGesturesEnabled: !navigating,
      onCameraTrackingDismissed: () => app.setCameraMode(CameraMode.free),
      onMapClick: (_, latLng) => _onMapTap(app, latLng),
    );
  }

  Future<void> _onMapTap(AppState app, LatLng tapped) async {
    if (app.navState.isActive) return;

    // نبحث في نصف قطر صغير: لمسة على فراغ ما تختار معلماً على بعد
    // كيلومتر، وهو سلوك يبدو عشوائياً للمستخدم
    final hits = await app.search.nearby(tapped,
        categories: categoryLabels.keys.where((k) => k != 'street').toList(),
        radiusM: 140,
        limit: 1);

    if (!mounted) return;
    if (hits.isEmpty) {
      app.previewPlace(null);
      await app.chooseDestination(
          Destination('نقطة على الخريطة', tapped));
    } else {
      app.previewPlace(hits.first);
    }
  }

  // ── تهيئة النمط ──────────────────────────────────────────────────────────

  Future<void> _onStyleLoaded(AppState app) async {
    final c = _map;
    if (c == null) return;

    final kinds = app.reports.types.isEmpty
        ? Cfg.alertDistanceM.keys.toList()
        : app.reports.types.map((t) => t.kind).toList();

    // الصور قبل أي symbol: الرمز الذي يشير لصورة غير مسجّلة لا يُرسم
    // ولا يرمي خطأ، فتختفي العلامات بصمت
    await registerMapImages(
        c, kinds, MediaQuery.of(context).devicePixelRatio);

    _styleReady = true;
    _drawnRoute = null;
    _drawnReportsHash = 0;
    _drawnPoisHash = 0;
    if (mounted) _sync(app);
  }

  // ── المزامنة ─────────────────────────────────────────────────────────────

  Future<void> _sync(AppState app) async {
    final c = _map;
    if (c == null || !_styleReady) return;

    await _syncRoute(c, app);
    await _syncReports(c, app);
    await _syncPois(c, app);
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
    if (_destSymbol != null) {
      await c.removeSymbol(_destSymbol!);
      _destSymbol = null;
    }
    if (route == null || route.shape.length < 2) return;

    // البدائل أولاً ورمادية تحت الأساسي — كما في التصميم
    for (final alt in app.alternates) {
      if (alt.shape.length < 2) continue;
      _routeLines.add(await c.addLine(LineOptions(
        geometry: alt.shape,
        lineColor: '#B9C7C1',
        lineWidth: 7.0,
        lineOpacity: 0.9,
        lineJoin: 'round',
      )));
    }

    // حاشية بيضاء ثم متن نعناعي: الخط الأخضر وحده يختفي على الحدائق،
    // والحاشية البيضاء هي ما يفصله في التصميم
    _routeLines.add(await c.addLine(LineOptions(
      geometry: route.shape,
      lineColor: '#FFFFFF',
      lineWidth: 13.0,
      lineJoin: 'round',
    )));

    final colored = route.maneuvers
        .where((m) => m.trafficLevel != null && m.shape.length > 1);

    _routeLines.add(await c.addLine(LineOptions(
      geometry: route.shape,
      lineColor: '#35C28E',
      lineWidth: 8.0,
      lineJoin: 'round',
    )));

    // ما نلوّن بتخمين: خط أحمر خاطئ أسوأ من خط بلا لون
    for (final m in colored) {
      final argb = Cfg.trafficColors[m.trafficLevel!];
      if (argb == null) continue;
      _routeLines.add(await c.addLine(LineOptions(
        geometry: m.shape,
        lineColor: '#${(argb & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}',
        lineWidth: 8.0,
        lineJoin: 'round',
      )));
    }

    _destSymbol = await c.addSymbol(SymbolOptions(
      geometry: route.shape.last,
      iconImage: destImageName,
      iconAnchor: 'bottom',
    ));
  }

  Future<void> _syncReports(MapLibreMapController c, AppState app) async {
    final hash = Object.hashAll(
        app.visibleReports.map((r) => '${r.id}:${r.clusterSize}'));
    if (hash == _drawnReportsHash) return;
    _drawnReportsHash = hash;

    if (_reportSymbols.isNotEmpty) {
      await c.removeSymbols(_reportSymbols.values);
      _reportSymbols.clear();
    }

    for (final r in app.visibleReports) {
      _reportSymbols[r.id] = await c.addSymbol(
        SymbolOptions(
          geometry: r.pos,
          iconImage: reportImageName(r.kind),
          iconAnchor: 'bottom',
          iconSize: 1.0,
          // غير المؤكّد شفاف جزئياً: يُعرض ومعه علامة، لأن إخفاءه حتى
          // التأكيد يعني أن أول مُبلِّغ لا يفيد أحداً
          iconOpacity: r.confirmed ? 1.0 : 0.62,
          textField: r.clusterSize > 1 ? '${r.clusterSize}' : null,
          textColor: '#FFFFFF',
          textSize: 11.0,
          textOffset: const Offset(0, -2.2),
          fontNames: const ['Noto Sans Bold'],
        ),
        {'reportId': r.id},
      );
    }
  }

  /// دبابيس نقاط الاهتمام حين يختار المستخدم تصنيفاً من الشرائح.
  Future<void> _syncPois(MapLibreMapController c, AppState app) async {
    final hash = Object.hashAll(app.categoryPins.map((p) => p.id));
    if (hash == _drawnPoisHash) return;
    _drawnPoisHash = hash;

    if (_poiSymbols.isNotEmpty) {
      await c.removeSymbols(_poiSymbols);
      _poiSymbols.clear();
    }

    for (final p in app.categoryPins) {
      _poiSymbols.add(await c.addSymbol(
        SymbolOptions(
          geometry: p.pos,
          iconImage: poiImageName(p.category),
          iconAnchor: 'bottom',
        ),
        {'poiId': p.id},
      ));
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

    // الدوران نسبةً للشاشة: SymbolOptions ما يكشف icon-rotation-alignment،
    // والافتراضي للرموز النقطية viewport. يناسبنا — الخريطة مُدارة لاتجاه
    // السير فالسهم يشير لأعلى الشاشة. الفرق يصحّح تأخّر الكاميرا
    final bearing =
        app.cameraMode == CameraMode.navigate ? nav.headingDeg : 0.0;

    final opts = SymbolOptions(
      geometry: nav.snapped,
      iconImage: carImageName,
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
        // أمامه. contentInsets تزيح مركز الكاميرا فعلياً — أنظف من إزاحة
        // الهدف حساباً، لأن الحساب يغلط مع تغيّر الميل والزوم
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
          // 700ms: أطول من فاصل قراءات GPS فتتصل الحركة بلا تقطيع،
          // وأقصر منه بما يكفي كي لا تتراكم الحركات
          duration: const Duration(milliseconds: 700),
        );
    }
  }
}

// ── طبقة الاستكشاف ─────────────────────────────────────────────────────────

/// تصنيفات الشرائح العلوية — نفس ترتيب التصميم.
const _categories = <(String, String, IconData)>[
  ('restaurant', 'مطاعم', Icons.restaurant),
  ('cafe', 'مقاهي', Icons.local_cafe),
  ('pharmacy', 'صيدليات', Icons.local_pharmacy),
  ('fuel', 'وقود', Icons.local_gas_station),
  ('hospital', 'مستشفيات', Icons.local_hospital),
  ('mosque', 'جوامع', Icons.mosque),
  ('market', 'أسواق', Icons.shopping_bag),
];

class MapOverlay extends StatelessWidget {
  const MapOverlay({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final pad = MediaQuery.of(context).padding;

    return Stack(
      children: [
        Positioned(
          top: pad.top + 10,
          right: 14,
          left: 14,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  DMapButton(
                    icon: Icons.my_location,
                    tooltip: 'موقعي',
                    onTap: () => app.setCameraMode(CameraMode.follow),
                    size: 44,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: DSearchBar(
                      hint: 'أين تريد الذهاب؟',
                      onTap: () => _openSearch(context, app),
                      trailing: const _Brand(),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              const _CategoryStrip(),
            ],
          ),
        ),

        if (app.notice != null)
          Positioned(
            left: 14, right: 14,
            top: pad.top + 124,
            child: _NoticeBar(
              text: app.notice!,
              onDismiss: app.dismissNotice,
            ),
          ),

        // الأزرار العائمة يمين الشاشة
        Positioned(
          right: 14,
          bottom: _rightStackBottom(app),
          child: Column(
            children: [
              DMapButton(
                icon: app.cameraMode == CameraMode.free
                    ? Icons.near_me_outlined
                    : Icons.near_me,
                tooltip: 'رجّعني لموقعي',
                onTap: () => app.setCameraMode(CameraMode.follow),
              ),
              const SizedBox(height: 10),
              DMapButton(
                icon: Icons.layers_outlined,
                tooltip: 'طبقات الخريطة',
                onTap: () => _showLayers(context),
              ),
            ],
          ),
        ),

        if (app.speedBadgeVisible)
          Positioned(
            left: 14,
            bottom: _rightStackBottom(app),
            child: _SpeedPill(kmh: app.fix!.speedKmh),
          ),

        // بطاقة المكان المعاين، أو ورقة المسار إن اختار وجهة
        if (app.destination != null)
          Positioned(
            left: 0, right: 0, bottom: 0,
            child: RouteSheet(
              onStart: app.startNavigation,
              onCancel: app.clearDestination,
            ),
          )
        else if (app.previewedPlace != null)
          Positioned(
            left: 10, right: 10, bottom: 86,
            child: PlaceCard(
              place: app.previewedPlace!,
              onDirections: () => app.chooseDestination(Destination(
                  app.previewedPlace!.title, app.previewedPlace!.pos)),
              onClose: () => app.previewPlace(null),
            ),
          ),
      ],
    );
  }

  /// ارتفاع الأزرار العائمة: فوق شريط التنقّل، وأعلى إذا كانت هناك بطاقة
  double _rightStackBottom(AppState app) {
    if (app.destination != null) return 300;
    if (app.previewedPlace != null) return 230;
    return 96;
  }

  Future<void> _openSearch(BuildContext context, AppState app) async {
    final chosen = await Navigator.of(context).push<Destination>(
        MaterialPageRoute(builder: (_) => const SearchScreen()));
    if (chosen != null) await app.chooseDestination(chosen);
  }

  void _showLayers(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => const _LayersSheet(),
    );
  }
}

class _Brand extends StatelessWidget {
  const _Brand();

  @override
  Widget build(BuildContext context) => Container(
        width: 34,
        height: 34,
        decoration: const BoxDecoration(
          color: D.ink,
          shape: BoxShape.circle,
        ),
        child: const Icon(Icons.park, color: D.mint, size: 19),
      );
}

class _CategoryStrip extends StatelessWidget {
  const _CategoryStrip();

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();

    return SizedBox(
      height: 46,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.zero,
        itemCount: _categories.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final c = _categories[i];
          return DChip(
            label: c.$2,
            icon: c.$3,
            selected: app.activeCategory == c.$1,
            onTap: () => app.toggleCategory(c.$1),
          );
        },
      ),
    );
  }
}

class _SpeedPill extends StatelessWidget {
  final double kmh;
  const _SpeedPill({required this.kmh});

  @override
  Widget build(BuildContext context) {
    return DCard(
      radius: D.rPill,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('${kmh.round()}',
              style: D.num2.copyWith(fontSize: 22, height: 1)),
          const Text('كم/س', style: TextStyle(fontSize: 10, color: D.textSoft)),
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
    return DCard(
      color: const Color(0xFFFFF6E2),
      padding: const EdgeInsets.fromLTRB(6, 6, 12, 6),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.close, size: 17),
            color: const Color(0xFF8A6418),
            onPressed: onDismiss,
            visualDensity: VisualDensity.compact,
          ),
          Expanded(
            child: Text(text,
                style: const TextStyle(
                    fontSize: 12.5, color: Color(0xFF7A5A14), height: 1.35)),
          ),
        ],
      ),
    );
  }
}

class _LayersSheet extends StatelessWidget {
  const _LayersSheet();

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();

    return Container(
      decoration: const BoxDecoration(
        color: D.card,
        borderRadius: BorderRadius.vertical(top: Radius.circular(D.rSheet)),
      ),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const DGrabber(),
          const DSectionHeader(
              title: 'طبقات الخريطة', icon: Icons.layers_outlined),
          const SizedBox(height: 12),
          SwitchListTile(
            value: app.showReportsLayer,
            onChanged: app.setShowReportsLayer,
            activeThumbColor: D.green,
            title: const Text('بلاغات السائقين', style: D.h3),
            subtitle: Text('${app.visibleReports.length} بلاغ حولك الآن',
                style: D.caption),
            contentPadding: EdgeInsets.zero,
          ),
          SwitchListTile(
            value: app.showTrafficLayer,
            onChanged: app.setShowTrafficLayer,
            activeThumbColor: D.green,
            title: const Text('حالة المرور', style: D.h3),
            subtitle: const Text('تلوين الطرق حسب الزحام', style: D.caption),
            contentPadding: EdgeInsets.zero,
          ),
          const SizedBox(height: 8),
          const _TrafficLegend(),
        ],
      ),
    );
  }
}

class _TrafficLegend extends StatelessWidget {
  const _TrafficLegend();

  @override
  Widget build(BuildContext context) {
    const items = [
      (D.trafficFree, 'سهل'),
      (D.trafficMid, 'متوسط'),
      (D.trafficJam, 'ازدحام شديد'),
    ];

    return DCard(
      color: D.cardInner,
      shadow: const [],
      radius: D.rPill,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          for (final it in items)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 10, height: 10,
                  decoration:
                      BoxDecoration(color: it.$1, shape: BoxShape.circle),
                ),
                const SizedBox(width: 6),
                Text(it.$2, style: D.bodySoft),
              ],
            ),
        ],
      ),
    );
  }
}

// ── شاشات الحالة ───────────────────────────────────────────────────────────

class SplashScreen extends StatelessWidget {
  final PackProgress? progress;
  const SplashScreen({super.key, this.progress});

  @override
  Widget build(BuildContext context) {
    final p = progress;

    return Scaffold(
      backgroundColor: D.bg,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 44),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 76, height: 76,
                decoration: const BoxDecoration(
                    color: D.ink, shape: BoxShape.circle),
                child: const Icon(Icons.park, color: D.mint, size: 40),
              ),
              const SizedBox(height: 18),
              const Text('دربنا',
                  style: TextStyle(
                      fontSize: 34,
                      fontWeight: FontWeight.w800,
                      color: D.text)),
              const SizedBox(height: 4),
              const Text('معاً لطرق أكثر أماناً', style: D.bodySoft),
              const SizedBox(height: 30),

              // شريط بنسبة لا دوّار: حزمة العراق 203MB تُلصَق في أول
              // تشغيل وتأخذ عشرات الثواني، ودوّار بلا رقم يبدو كتعليق
              if (p != null) ...[
                ClipRRect(
                  borderRadius: BorderRadius.circular(5),
                  child: LinearProgressIndicator(
                    value: p.fraction.clamp(0.0, 1.0),
                    minHeight: 8,
                    backgroundColor: D.mintLight,
                    valueColor: const AlwaysStoppedAnimation(D.green),
                  ),
                ),
                const SizedBox(height: 14),
                Text('${p.label} — ${(p.fraction * 100).round()}%',
                    style: D.bodySoft),
                const SizedBox(height: 4),
                const Text('مرة واحدة فقط، وبعدها تفتح فوراً',
                    style: D.caption),
              ] else
                const CircularProgressIndicator(color: D.green),
            ],
          ),
        ),
      ),
    );
  }
}

class FatalScreen extends StatelessWidget {
  final String message;
  const FatalScreen({super.key, required this.message});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: D.bg,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: DCard(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const DIconCircle(Icons.error_outline,
                    size: 56, background: Color(0xFFFDE7E7),
                    foreground: D.danger),
                const SizedBox(height: 16),
                const Text('ما قدرنا نشغّل التطبيق', style: D.h2),
                const SizedBox(height: 10),
                Text(message, textAlign: TextAlign.center, style: D.bodySoft),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// نصّ المدة مختصراً — تستعمله البطاقات الصغيرة.
String shortDuration(double seconds) => durationLabel(seconds);
