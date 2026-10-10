// محرّك الملاحة: يستقبل قراءات الموقع، ويُخرج حالة تعرضها الواجهة وتنطقها.
//
// كل القرارات الزمنية هنا: متى نعلن مناورة، متى ننبّه على بلاغ، متى نعلن
// الخروج عن المسار ونعيد الحساب، متى وصلنا.
//
// ما في شيء من الواجهة في هذا الملف بقصد: المحرّك قابل للاختبار بسلسلة
// قراءات GPS مسجّلة، والاختبار عبر الواجهة ما ينفع لهذا المنطق.

import 'dart:async';

import 'package:maplibre_gl/maplibre_gl.dart';

import '../config.dart';
import '../core/api_client.dart';
import '../core/geo.dart';
import '../core/location_service.dart';
import '../core/search.dart';
import '../reports/reports.dart';
import 'map_matcher.dart';
import 'phrases.dart';
import 'route_model.dart';
import 'voice.dart';

enum NavPhase { idle, navigating, rerouting, arrived }

/// حالة الملاحة الحالية — كل ما تحتاجه الواجهة في كائن واحد.
class NavState {
  final NavPhase phase;
  final NavRoute? route;

  /// الموقع مثبَّتاً على المسار. نرسمه لا قراءة GPS الخام: السهم على
  /// الرصيف يبدو كخطأ في التطبيق حتى لو كانت القراءة هي الخاطئة.
  final LatLng? snapped;
  final double headingDeg;
  final double speedKmh;

  final Maneuver? current;
  final Maneuver? next;
  final double distanceToManeuverM;

  /// معلم المناورة القادمة، حين لا اسم لشارعها. 9% فقط من طرق العراق
  /// مسمّاة، فهذا نصف التعليمات لا زينة.
  final Landmark? nextLandmark;

  final double remainingM;
  final double remainingS;
  final DateTime? eta;

  /// البلاغ الذي ينبّه عليه الآن، إن وُجد.
  final Report? activeAlert;
  final double? activeAlertDistanceM;

  final bool offRoute;
  final String? notice;

  /// حدّ السرعة على المناورة التي نحن فيها. null يعني أن OSM ما يحمله —
  /// والواجهة تخفي اللوحة بدل ما تعرض رقماً مخمَّناً
  double? get speedLimitKmh => current?.speedLimitKmh;

  const NavState({
    this.phase = NavPhase.idle,
    this.route,
    this.snapped,
    this.headingDeg = 0,
    this.speedKmh = 0,
    this.current,
    this.next,
    this.distanceToManeuverM = 0,
    this.nextLandmark,
    this.remainingM = 0,
    this.remainingS = 0,
    this.eta,
    this.activeAlert,
    this.activeAlertDistanceM,
    this.offRoute = false,
    this.notice,
  });

  bool get isActive =>
      phase == NavPhase.navigating || phase == NavPhase.rerouting;
}

class NavEngine {
  final LocationService location;
  final Voice voice;
  final ApiClient api;

  /// قاعدة البحث المحلية — نستخرج منها معالم المناورات.
  final PoiSearch search;

  NavEngine({
    required this.location,
    required this.voice,
    required this.api,
    required this.search,
  });

  final _out = StreamController<NavState>.broadcast();
  Stream<NavState> get stream => _out.stream;

  NavState _state = const NavState();
  NavState get state => _state;

  MapMatcher? _matcher;
  LatLng? _destination;
  StreamSubscription<Fix>? _sub;

  /// آخر مرحلة إعلان نُطقت لكل مناورة. نخزّنها بفهرس المناورة لا بنصّها:
  /// مسار فيه انعطافان يمين متتاليان بنفس الجملة، والتمييز بالنصّ يسكت
  /// الثاني.
  final Map<int, int> _announcedStage = {};

  /// البلاغات التي نبّهنا عليها — لا ننبّه مرتين على نفس الحادث.
  final Set<int> _alertedReports = {};

  /// معلم كل مناورة، محسوب مرة عند بدء المسار. حسابه في كل قراءة GPS
  /// يعني استعلاماً مكانياً كل خمسة أمتار بلا أي فائدة — المعالم ثابتة.
  List<Landmark?> _landmarks = const [];

  List<Report> _reports = const [];

  /// نقاط الرحلة المجمّعة لإرسالها مجهولة للزحام.
  final List<Map<String, dynamic>> _traceBuffer = [];
  bool traceEnabled = Cfg.traceEnabledByDefault;

  int _rerouteAttempts = 0;
  // بعد ثلاث محاولات فاشلة نكفّ: السائق في منطقة ما تغطّيها الخريطة أو
  // الشبكة مقطوعة، وإعادة المحاولة كل ثانية تحرق البطارية بلا فائدة
  static const int _maxRerouteAttempts = 3;

  // ── التحكّم ──────────────────────────────────────────────────────────────

  Future<void> start(NavRoute route, LatLng destination) async {
    _matcher = MapMatcher(route);
    _destination = destination;
    _announcedStage.clear();
    _alertedReports.clear();
    _rerouteAttempts = 0;
    voice.resetHistory();

    _landmarks = await _resolveLandmarks(route);

    _emit(NavState(
      phase: NavPhase.navigating,
      route: route,
      remainingM: route.totalLengthM,
      remainingS: route.effectiveTimeS,
      eta: DateTime.now()
          .add(Duration(seconds: route.effectiveTimeS.round())),
      current: route.maneuvers.isEmpty ? null : route.maneuvers.first,
      next: route.maneuvers.length > 1 ? route.maneuvers[1] : null,
    ));

    await location.start();
    _sub = location.stream.listen(_onFix);

    // التعليمة الأولى تُنطق فوراً: السائق واقف ويبي يعرف من وين يبدأ
    if (route.maneuvers.isNotEmpty) {
      await voice.say(maneuverVoice(route.maneuvers.first, 0, 2,
          landmark: _landmarkAt(0)));
    }
  }

  /// يستخرج معلماً لكل مناورة بلا اسم شارع.
  ///
  /// مرة واحدة عند بدء المسار: المعالم ثابتة، واستعلام مكاني لكل قراءة
  /// GPS يعني واحداً كل خمسة أمتار بلا فائدة.
  ///
  /// نحسب أيضاً هل المعلم قبل نقطة المناورة أو عندها — الفرق بين
  /// «بعد محطة الوقود، انعطف» و«انعطف عند محطة الوقود»، وهو فرق يهمّ
  /// السائق فعلاً.
  Future<List<Landmark?>> _resolveLandmarks(NavRoute route) async {
    final out = <Landmark?>[];

    for (final m in route.maneuvers) {
      // المناورة المسمّاة ما تحتاج معلماً — الاسم أدقّ منه
      if (m.announceStreet != null || m.exitNumber != null) {
        out.add(null);
        continue;
      }

      final at = m.shape.isEmpty ? null : m.shape.first;
      if (at == null) {
        out.add(null);
        continue;
      }

      // 180م لا 110: شخّصنا التعليمات العارية على ثمانية مسارات فوجدنا
      // أن أكثرها لها معلم بين 110 و200م. والبعد ما يضرّ ما دام حرف
      // الجرّ يصحّح الموضع
      final place = await search.landmarkNear(at, radiusM: 180);
      if (place == null) {
        out.add(null);
        continue;
      }

      // نفس المعلم مرتين يربك: «انعطف يمين عند أسواق حمودي» ثم بعد
      // تعليمتين «انعطف يمين عند أسواق حمودي» — السائق يظن أنه رجع
      // لنفس المكان. نقارن بآخر معلم استُعمل لا بآخر مدخل، لأن تعليمة
      // عارية بينهما كانت تكسر المقارنة
      final lastUsed = out.lastWhere((l) => l != null, orElse: () => null);
      if (lastUsed?.name == place.title) {
        out.add(null);
        continue;
      }

      // موضع المعلم من المناورة: نُسقط الاثنين على المسار ونقارن
      // المسافة المقطوعة. الهامش 35م — المعلم على نفس التقاطع «عنده»
      final atOnRoute = projectOnLine(at, route.shape);
      final lmOnRoute = projectOnLine(place.pos, route.shape);
      final delta = lmOnRoute.traveledM - atOnRoute.traveledM;

      final where = delta < -35
          ? LandmarkWhere.before
          : delta > 35
              ? LandmarkWhere.after
              : LandmarkWhere.at;

      out.add(Landmark(place.title, where: where));
    }

    return out;
  }

  Landmark? _landmarkAt(int index) =>
      index >= 0 && index < _landmarks.length ? _landmarks[index] : null;

  Future<void> stop() async {
    await _sub?.cancel();
    _sub = null;
    _matcher = null;
    _destination = null;
    await voice.stop();
    await _flushTrace();
    _emit(const NavState());
  }

  void setReports(List<Report> reports) => _reports = reports;

  // ── القلب ────────────────────────────────────────────────────────────────

  Future<void> _onFix(Fix fix) async {
    final matcher = _matcher;
    if (matcher == null) return;

    _bufferTrace(fix);

    final m = matcher.update(fix.pos);
    final route = matcher.route;

    // الوصول: المسافة المتبقّية صغيرة. ما نشترط دخول دائرة حول الوجهة
    // لأن الوجهة قد تكون على الجهة الثانية من شارع مزدوج، فما يدخلها
    // السائق أبداً وتبقى الملاحة شغّالة بعد ما وصل
    if (m.remainingM < 40) {
      await _arrive();
      return;
    }

    if (m.offRoute && _state.phase != NavPhase.rerouting) {
      await _reroute(fix);
      return;
    }

    final idx = m.maneuverIndex;
    final nextIdx = idx + 1 < route.maneuvers.length ? idx + 1 : idx;
    final nextManeuver = route.maneuvers[nextIdx];

    await _maybeAnnounce(nextIdx, nextManeuver, m.distanceToManeuverM,
        fix.speedKmh, _landmarkAt(nextIdx));

    final alert = _pickAlert(fix, route);
    if (alert != null) await _maybeAlert(alert.$1, alert.$2);

    final remainingS = matcher.remainingTimeS(m);

    _emit(NavState(
      phase: NavPhase.navigating,
      route: route,
      snapped: m.snapped,
      headingDeg: fix.heading,
      speedKmh: fix.speedKmh,
      current: route.maneuvers[idx],
      next: nextManeuver,
      distanceToManeuverM: m.distanceToManeuverM,
      nextLandmark: _landmarkAt(nextIdx),
      remainingM: m.remainingM,
      remainingS: remainingS,
      eta: DateTime.now().add(Duration(seconds: remainingS.round())),
      activeAlert: alert?.$1,
      activeAlertDistanceM: alert?.$2,
      offRoute: false,
    ));
  }

  // ── الإعلان الصوتي ───────────────────────────────────────────────────────

  /// يقرّر إن كان الوقت حان لإعلان المناورة، وبأي إسهاب.
  ///
  /// ثلاث مراحل من البعيد للقريب: تمهيد، تأكيد، تنفيذ. وعلى الطرق
  /// السريعة تُضاعَف المسافات: 300 متر بسرعة 100 كم/س هي عشر ثوان، وهي
  /// متأخّرة جداً لمن يبي يغيّر مساراً.
  Future<void> _maybeAnnounce(int idx, Maneuver m, double distanceM,
      double speedKmh, Landmark? landmark) async {
    final scale = speedKmh >= Cfg.highwaySpeedKmh
        ? Cfg.highwayAnnounceMultiplier
        : 1.0;

    final done = _announcedStage[idx] ?? -1;

    // من الأقرب للأبعد: لو قطع السائق مسافة بلا قراءات (نفق) نعلن
    // المرحلة الصحيحة لا نعيد كل المراحل
    for (var stage = Cfg.announceDistancesM.length - 1; stage >= 0; stage--) {
      if (stage <= done) continue;
      final threshold = Cfg.announceDistancesM[stage] * scale;
      if (distanceM > threshold) continue;

      // المناورة القصيرة لا تستحق ثلاث إعلانات: شارع طوله 120 متراً
      // ينتهي قبل ما نكمل التمهيد. نتخطّى المراحل البعيدة عنها
      if (stage == 0 && m.startOffsetM > 0 && distanceM < threshold * 0.4) {
        _announcedStage[idx] = 0;
        continue;
      }

      _announcedStage[idx] = stage;
      await voice.say(maneuverVoice(m, distanceM, stage, landmark: landmark),
          cooldown: Cfg.announceCooldown, interrupt: stage == 2);
      return;
    }
  }

  // ── تنبيهات البلاغات ─────────────────────────────────────────────────────

  /// يختار البلاغ الأجدر بالتنبيه: الأقرب الذي على مسارنا وأمامنا.
  (Report, double)? _pickAlert(Fix fix, NavRoute route) {
    if (_reports.isEmpty) return null;

    Report? best;
    var bestDist = double.infinity;

    for (final r in _reports) {
      final limit = Cfg.alertDistanceM[r.kind];
      if (limit == null) continue;

      // على المسار؟ نُسقط البلاغ على الخط ونقيس بعده عنه. البلاغ على
      // الطريق الموازي يُعرض على الخريطة ولا يُنطق — تنبيه خاطئ يفقد
      // السائق ثقته بكل التنبيهات
      final proj = projectOnLine(r.pos, route.shape);
      if (proj.distanceM > Cfg.alertCorridorM) continue;

      // أمامنا؟ نقارن المسافة المقطوعة لا المسافة الهوائية: بلاغ وراءنا
      // بعشرين متراً أقرب هوائياً من بلاغ أمامنا بمئة
      final me = projectOnLine(fix.pos, route.shape);
      final ahead = proj.traveledM - me.traveledM;
      if (ahead <= 0 || ahead > limit) continue;

      if (ahead < bestDist) {
        bestDist = ahead;
        best = r;
      }
    }

    return best == null ? null : (best, bestDist);
  }

  Future<void> _maybeAlert(Report r, double distanceM) async {
    if (_alertedReports.contains(r.id)) return;
    _alertedReports.add(r.id);
    await voice.alert(reportAlertVoice(r.kind, r.label, distanceM));
  }

  // ── إعادة الحساب ─────────────────────────────────────────────────────────

  Future<void> _reroute(Fix fix) async {
    final dest = _destination;
    if (dest == null) return;

    if (_rerouteAttempts >= _maxRerouteAttempts) {
      _emit(NavState(
        phase: NavPhase.navigating,
        route: _state.route,
        snapped: fix.pos,
        headingDeg: fix.heading,
        speedKmh: fix.speedKmh,
        offRoute: true,
        notice: msgNoRoute,
      ));
      return;
    }

    _rerouteAttempts++;
    _emit(NavState(
      phase: NavPhase.rerouting,
      route: _state.route,
      snapped: fix.pos,
      headingDeg: fix.heading,
      speedKmh: fix.speedKmh,
      offRoute: true,
      notice: msgRerouting,
    ));

    await voice.say(msgRerouting, interrupt: true);

    try {
      final j = await api.route(points: [fix.pos, dest], alternates: 0);
      final route = NavRoute.fromTrip(
        j['trip'] as Map<String, dynamic>,
        closuresAvoided: (j['closures_avoided'] as num?)?.toInt() ?? 0,
      );
      await start(route, dest);
      _rerouteAttempts = 0;
    } on ApiDown {
      // الشبكة مقطوعة: نُبقي المسار القديم معروضاً ونقول للسائق صراحةً.
      // مسار قديم يرى منه موقعه أنفع من شاشة فارغة
      _emit(NavState(
        phase: NavPhase.navigating,
        route: _state.route,
        snapped: fix.pos,
        headingDeg: fix.heading,
        speedKmh: fix.speedKmh,
        offRoute: true,
        notice: msgOffline,
      ));
    } on ApiRejected catch (e) {
      _emit(NavState(
        phase: NavPhase.navigating,
        route: _state.route,
        snapped: fix.pos,
        offRoute: true,
        notice: e.message,
      ));
    }
  }

  Future<void> _arrive() async {
    await _sub?.cancel();
    _sub = null;
    await voice.say(msgArrived, interrupt: true);
    await _flushTrace();
    _emit(NavState(phase: NavPhase.arrived, route: _state.route,
        notice: msgArrived));
  }

  // ── قراءات السرعة للزحام ─────────────────────────────────────────────────

  void _bufferTrace(Fix fix) {
    if (!traceEnabled) return;

    _traceBuffer.add({
      'lat': fix.pos.latitude,
      'lon': fix.pos.longitude,
      'time': fix.at.millisecondsSinceEpoch / 1000.0,
      'speed_kmh': fix.speedKmh,
    });

    if (_traceBuffer.length >= Cfg.tracePointsPerChunk) _flushTrace();
  }

  /// يرسل القطعة المجمّعة. الفشل يُهمل عن قصد مكتوب: قراءة سرعة ضائعة
  /// ما تضرّ أحداً، ومحاولة إعادة إرسالها تكبّر القطعة فتضرّ الخصوصية.
  Future<void> _flushTrace() async {
    if (_traceBuffer.length < 4) return;
    final chunk = List<Map<String, dynamic>>.of(_traceBuffer);
    _traceBuffer.clear();

    try {
      await api.submitTrace(chunk);
    } on ApiDown {
      return;
    } on ApiRejected {
      return;
    }
  }

  void _emit(NavState s) {
    _state = s;
    _out.add(s);
  }

  Future<void> dispose() async {
    await stop();
    await _out.close();
  }
}
