// خدمة الموقع: الصلاحيات، وتدفّق القراءات، وتنعيمها.
//
// geolocator لا location: يعطي سرعة واتجاه GPS مباشرة من الجهاز، وهما
// أدقّ بكثير من حسابهما بتفاضل موقعين مضطربين — سرعة GPS من إزاحة دوبلر
// لا من الموقع.

import 'dart:async';

import 'package:geolocator/geolocator.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

import '../config.dart';
import 'geo.dart';

/// قراءة موقع بعد التنعيم، بكل ما تحتاجه الملاحة.
class Fix {
  final LatLng pos;
  final double accuracyM;

  /// كم/س. صفر عند الوقوف.
  final double speedKmh;

  /// الاتجاه المنعَّم بالدرجات — هذا ما تدور به الكاميرا.
  final double heading;

  /// الاتجاه الخام من GPS قبل التنعيم. نحتاجه لفلترة البلاغات الموجّهة.
  final double rawHeading;

  final DateTime at;

  const Fix({
    required this.pos,
    required this.accuracyM,
    required this.speedKmh,
    required this.heading,
    required this.rawHeading,
    required this.at,
  });
}

class LocationService {
  final _out = StreamController<Fix>.broadcast();
  StreamSubscription<Position>? _sub;

  double _smoothed = 0.0;
  bool _hasHeading = false;
  Fix? _last;

  Stream<Fix> get stream => _out.stream;
  Fix? get last => _last;

  /// يطلب الصلاحية. يرجّع سبب الرفض بالعربي، أو null إذا نجح.
  ///
  /// نفرّق بين الرفض المؤقّت والدائم: المؤقّت نعيد الطلب عنده، والدائم
  /// لازم نرسل المستخدم للإعدادات — الطلب مرة ثانية لا يُظهر أي حوار
  /// فيبدو التطبيق معطّلاً بلا سبب.
  Future<String?> requestPermission() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      return 'خدمة الموقع مغلقة في الجهاز — شغّلها من الإعدادات';
    }

    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
    }

    if (perm == LocationPermission.deniedForever) {
      return 'صلاحية الموقع مرفوضة نهائياً — افتح إعدادات التطبيق وفعّلها';
    }
    if (perm == LocationPermission.denied) {
      return 'التطبيق يحتاج صلاحية الموقع ليعرف وين أنت';
    }
    return null;
  }

  Future<void> start() async {
    if (_sub != null) return;

    const settings = LocationSettings(
      accuracy: LocationAccuracy.bestForNavigation,
      distanceFilter: Cfg.locationDistanceFilterM,
    );

    _sub = Geolocator.getPositionStream(locationSettings: settings)
        .listen(_onPosition, onError: _out.addError);
  }

  void _onPosition(Position p) {
    // قراءة بدقة أسوأ من العتبة تُهمل: في أنفاق بغداد ومواقف المولات
    // يرمي GPS مواقع بدقة 200 متر، ورسمها يطوّح السهم لحيٍّ مجاور
    if (p.accuracy > Cfg.locationMaxAccuracyM) return;

    final speedKmh = (p.speed.isNaN ? 0.0 : p.speed) * 3.6;
    final raw = p.heading.isNaN ? 0.0 : p.heading;

    // تحت عتبة السرعة ما نثق باتجاه GPS: وأنت واقف يعطي آخر اتجاه حركة
    // أو قيمة عشوائية، فتدور الخريطة حول نفسها عند كل إشارة مرور
    final trustHeading = speedKmh >= Cfg.headingFromGpsMinSpeedKmh;

    if (trustHeading) {
      _smoothed = _hasHeading
          ? smoothHeading(_smoothed, raw, Cfg.headingSmoothing)
          : raw;
      _hasHeading = true;
    }

    final fix = Fix(
      pos: LatLng(p.latitude, p.longitude),
      accuracyM: p.accuracy,
      speedKmh: speedKmh,
      heading: _smoothed,
      rawHeading: raw,
      at: p.timestamp,
    );

    _last = fix;
    _out.add(fix);
  }

  /// قراءة واحدة الآن — لفتح الخريطة على موقع المستخدم قبل بدء التدفّق.
  Future<Fix?> currentOnce() async {
    final p = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        timeLimit: Duration(seconds: 10),
      ),
    );
    final fix = Fix(
      pos: LatLng(p.latitude, p.longitude),
      accuracyM: p.accuracy,
      speedKmh: (p.speed.isNaN ? 0.0 : p.speed) * 3.6,
      heading: p.heading.isNaN ? 0.0 : p.heading,
      rawHeading: p.heading.isNaN ? 0.0 : p.heading,
      at: p.timestamp,
    );
    _last = fix;
    return fix;
  }

  Future<void> stop() async {
    await _sub?.cancel();
    _sub = null;
    _hasHeading = false;
  }

  Future<void> dispose() async {
    await stop();
    await _out.close();
  }
}
