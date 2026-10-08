// تمثيل المسار والمناورات كما يرجّعها Valhalla، بشكل تستهلكه الواجهة.

import 'package:maplibre_gl/maplibre_gl.dart';

import '../core/geo.dart';

/// أنواع المناورات عند Valhalla. أرقام لا أسماء في الـJSON، فنسمّيها هنا
/// مرة واحدة — رقم 15 مبثوث في شرط منطقي لا يقول شيئاً لمن يقرأ بعد سنة.
class Mnv {
  Mnv._();

  static const none = 0;
  static const start = 1;
  static const startRight = 2;
  static const startLeft = 3;
  static const destination = 4;
  static const destinationRight = 5;
  static const destinationLeft = 6;
  static const becomes = 7;
  static const continueOn = 8;
  static const slightRight = 9;
  static const right = 10;
  static const sharpRight = 11;
  static const uturnRight = 12;
  static const uturnLeft = 13;
  static const sharpLeft = 14;
  static const left = 15;
  static const slightLeft = 16;
  static const rampStraight = 17;
  static const rampRight = 18;
  static const rampLeft = 19;
  static const exitRight = 20;
  static const exitLeft = 21;
  static const stayStraight = 22;
  static const stayRight = 23;
  static const stayLeft = 24;
  static const merge = 25;
  static const roundaboutEnter = 26;
  static const roundaboutExit = 27;
  static const ferryEnter = 28;
  static const ferryExit = 29;
  static const mergeRight = 38;
  static const mergeLeft = 39;

  /// المناورات التي تنتهي عندها الرحلة.
  static const arrival = {destination, destinationRight, destinationLeft};
}

class Maneuver {
  final int type;
  final List<String> streetNames;

  /// أسماء الشارع الذي ستدخله بعد المناورة — Valhalla يسمّيها
  /// begin_street_names حين يختلف اسم بداية القطعة عن اسمها الغالب.
  final List<String> beginStreetNames;

  /// فهرس بداية ونهاية هذه المناورة في خط المسار.
  final int beginShapeIndex;
  final int endShapeIndex;

  /// طول المناورة بالكيلومترات والزمن بالثواني (بلا زحام).
  final double lengthKm;
  final double timeS;

  /// عدد مخارج الدوّار حتى مخرجنا. يُستخدم في الجملة: «ثالث مخرج».
  final int? roundaboutExitCount;

  /// لوحات الطريق: رقم المخرج والجهة المكتوبة عليه.
  final String? exitNumber;
  final List<String> exitToward;

  /// الاتجاه قبل المناورة وبعدها بالدرجات. نحتاجه لرسم سهم المناورة
  /// بزاويته الحقيقية لا بأيقونة عامة.
  final double? bearingBefore;
  final double? bearingAfter;

  /// حالة الزحام على هذه المناورة إن عرفها الباكند.
  final String? trafficLevel;

  /// حدّ السرعة كم/س إن كان في OSM. غائب عن أكثر طرق العراق — نعرضه
  /// حين يوجد ولا نخمّنه، لأن حدّاً خاطئاً معروضاً أسوأ من لا حدّ.
  final double? speedLimitKmh;

  /// نقاط هذه المناورة من خط المسار — تُحسب مرة عند البناء.
  final List<LatLng> shape;

  /// المسافة من بداية المسار إلى بداية هذه المناورة بالأمتار.
  final double startOffsetM;

  const Maneuver({
    required this.type,
    required this.streetNames,
    required this.beginStreetNames,
    required this.beginShapeIndex,
    required this.endShapeIndex,
    required this.lengthKm,
    required this.timeS,
    required this.roundaboutExitCount,
    required this.exitNumber,
    required this.exitToward,
    required this.bearingBefore,
    required this.bearingAfter,
    required this.trafficLevel,
    required this.shape,
    required this.startOffsetM,
    this.speedLimitKmh,
  });

  double get lengthM => lengthKm * 1000.0;

  bool get isArrival => Mnv.arrival.contains(type);

  /// اسم الشارع الذي نعلنه. begin أولاً: حين تنعطف في شارع، الاسم الذي
  /// يهمّ السائق هو اسم ما سيدخله لا اسم ما كان فيه.
  String? get announceStreet {
    if (beginStreetNames.isNotEmpty) return beginStreetNames.first;
    if (streetNames.isNotEmpty) return streetNames.first;
    return null;
  }

  factory Maneuver.fromJson(Map<String, dynamic> j, List<LatLng> routeShape,
      double startOffsetM) {
    final sign = j['sign'] as Map<String, dynamic>?;

    List<String> signText(String key) {
      final list = sign?[key] as List?;
      if (list == null) return const [];
      return list
          .map((e) => '${(e as Map)['text']}')
          .where((s) => s.isNotEmpty && s != 'null')
          .toList();
    }

    final i0 = (j['begin_shape_index'] as num?)?.toInt() ?? 0;
    final i1 = (j['end_shape_index'] as num?)?.toInt() ?? i0;

    final exitNums = signText('exit_number_elements');

    return Maneuver(
      type: (j['type'] as num?)?.toInt() ?? Mnv.none,
      streetNames: ((j['street_names'] as List?) ?? const [])
          .map((e) => '$e')
          .toList(),
      beginStreetNames: ((j['begin_street_names'] as List?) ?? const [])
          .map((e) => '$e')
          .toList(),
      beginShapeIndex: i0,
      endShapeIndex: i1,
      lengthKm: (j['length'] as num?)?.toDouble() ?? 0.0,
      timeS: (j['time'] as num?)?.toDouble() ?? 0.0,
      roundaboutExitCount: (j['roundabout_exit_count'] as num?)?.toInt(),
      exitNumber: exitNums.isEmpty ? null : exitNums.first,
      exitToward: signText('exit_toward_elements'),
      bearingBefore: (j['bearing_before'] as num?)?.toDouble(),
      bearingAfter: (j['bearing_after'] as num?)?.toDouble(),
      trafficLevel: j['traffic_level'] as String?,
      speedLimitKmh: (j['speed_limit'] as num?)?.toDouble(),
      shape: routeShape.isEmpty
          ? const []
          : routeShape.sublist(
              i0.clamp(0, routeShape.length - 1),
              (i1 + 1).clamp(1, routeShape.length),
            ),
      startOffsetM: startOffsetM,
    );
  }
}

class NavRoute {
  final List<LatLng> shape;
  final List<Maneuver> maneuvers;

  /// الطول بالكيلومترات والزمن بالثواني بلا زحام.
  final double lengthKm;
  final double timeS;

  /// الزمن مع الزحام إن عرفه الباكند. null يعني «ما عندنا قراءات».
  final double? timeWithTrafficS;

  /// نسبة المسار التي عندنا عليها قراءات زحام (0–1). تُعرض للمستخدم:
  /// ETA بتغطية 10% لا يُقدَّم بنفس ثقة ETA بتغطية 90%.
  final double trafficCoverage;

  final int closuresAvoided;

  /// الطول الفعلي محسوباً من الخط. نحفظه لأن مطابقة الموقع تحتاجه كثيراً،
  /// وإعادة حسابه في كل قراءة GPS تمرّ على آلاف النقاط.
  final double totalLengthM;

  NavRoute({
    required this.shape,
    required this.maneuvers,
    required this.lengthKm,
    required this.timeS,
    required this.timeWithTrafficS,
    required this.trafficCoverage,
    required this.closuresAvoided,
  }) : totalLengthM = lineLength(shape);

  double get effectiveTimeS => timeWithTrafficS ?? timeS;

  /// الثواني التي أضافها الزحام. صفر يعني مساراً سالكاً أو بلا قراءات —
  /// ترتيب المسارات بها يميّز «أقل ازدحاماً» عن «الأسرع».
  double get trafficPenaltyS =>
      timeWithTrafficS == null ? 0 : (timeWithTrafficS! - timeS);

  LatLng get destination => shape.isEmpty
      ? const LatLng(0, 0)
      : shape.last;

  /// يبني المسار من رد الباكند (الذي يغلّف رد Valhalla).
  ///
  /// Valhalla يرمّز الخط بـpolyline6 لا polyline5 — القاسم 1e6. خلط
  /// القاسمين يعطي خطاً صحيح الشكل ومضروباً بعشرة في الموقع، وهو أسوأ من
  /// خطأ صريح لأنه يبدو كأنه يشتغل.
  factory NavRoute.fromTrip(Map<String, dynamic> trip,
      {int closuresAvoided = 0}) {
    final legs = (trip['legs'] as List?) ?? const [];

    final shape = <LatLng>[];
    final maneuvers = <Maneuver>[];

    for (final legRaw in legs) {
      final leg = legRaw as Map<String, dynamic>;
      final legShape = decodePolyline6('${leg['shape']}');

      // فهارس المناورات نسبية لخط رحلتها، فنزيحها بطول ما سبقها
      final offset = shape.isEmpty ? 0 : shape.length;
      // ما نكرّر نقطة الوصل بين رحلتين: تظهر قطعة منعدمة الطول تُربك
      // الإسقاط على الخط
      shape.addAll(offset == 0 ? legShape : legShape.skip(1));

      var traveled = offset == 0 ? 0.0 : lineLength(shape.sublist(0, offset));

      for (final mRaw in (leg['maneuvers'] as List?) ?? const []) {
        final m = mRaw as Map<String, dynamic>;
        final shifted = Map<String, dynamic>.of(m);
        final adj = offset == 0 ? 0 : offset - 1;
        shifted['begin_shape_index'] =
            ((m['begin_shape_index'] as num?)?.toInt() ?? 0) + adj;
        shifted['end_shape_index'] =
            ((m['end_shape_index'] as num?)?.toInt() ?? 0) + adj;

        final mv = Maneuver.fromJson(shifted, shape, traveled);
        maneuvers.add(mv);
        traveled += mv.lengthM;
      }
    }

    final summary = (trip['summary'] as Map<String, dynamic>?) ?? const {};
    final traffic = (trip['traffic'] as Map<String, dynamic>?) ?? const {};

    return NavRoute(
      shape: shape,
      maneuvers: maneuvers,
      lengthKm: (summary['length'] as num?)?.toDouble() ?? 0.0,
      timeS: (summary['time'] as num?)?.toDouble() ?? 0.0,
      timeWithTrafficS: (summary['time_with_traffic'] as num?)?.toDouble(),
      trafficCoverage: (traffic['coverage'] as num?)?.toDouble() ?? 0.0,
      closuresAvoided: closuresAvoided,
    );
  }
}
