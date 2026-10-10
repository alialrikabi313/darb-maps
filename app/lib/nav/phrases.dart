// صياغة الجمل العربية للملاحة.
//
// ═══ قرارك ═══
// كل نصّ في هذا الملف قرار مجال يرجع لصاحب المشروع. كُتب باللهجة العراقية
// المحيَّدة — مفهوم في بغداد والبصرة والموصل — وما أجتهد فيه. عدّل هنا
// وبس؛ لا نصّ عربي معروض للمستخدم في أي ملف آخر إلا تسميات التصنيفات.
//
// ليش ما نستخدم narrative ڤالهالا الجاهز: ما فيه عربية مضمونة، وحتى لو
// كانت فهي فصحى مترجمة حرفياً («استمر على الطريق الحالي») لا الطريقة التي
// يتكلّم بها السائق العراقي. ونحن نبي صياغتنا على كل حال.
//
// قواعد الصياغة التي اتبعتها:
//   - الجملة الصوتية أقصر من المكتوبة: السائق يسمع وهو يسوق
//   - المسافة قبل الفعل في التمهيد («بعد 500 متر، انعطف يمين») وبعد الفعل
//     في التنفيذ («انعطف يمين») — البعيد يحتاج المسافة أولاً كي يعرف أنه
//     ليس الآن
//   - لا «يميناً» بالتنوين: تُقرأ «يمينَن» في بعض محرّكات النطق

import 'route_model.dart';

/// فعل المناورة مكتوباً — يُعرض في الشريط الأعلى.
String maneuverTitle(Maneuver m) {
  switch (m.type) {
    case Mnv.start:
    case Mnv.startRight:
    case Mnv.startLeft:
      return 'ابدأ السير';

    case Mnv.destination:
      return 'وصلت';
    case Mnv.destinationRight:
      return 'وصلت — على يمينك';
    case Mnv.destinationLeft:
      return 'وصلت — على يسارك';

    case Mnv.becomes:
    case Mnv.continueOn:
      return 'كمّل مستقيم';

    case Mnv.slightRight:
      return 'مِل يمين';
    case Mnv.right:
      return 'انعطف يمين';
    case Mnv.sharpRight:
      return 'انعطف يمين حاد';

    case Mnv.slightLeft:
      return 'مِل يسار';
    case Mnv.left:
      return 'انعطف يسار';
    case Mnv.sharpLeft:
      return 'انعطف يسار حاد';

    case Mnv.uturnRight:
    case Mnv.uturnLeft:
      return 'استدر بالعكس';

    case Mnv.rampRight:
      return 'اطلع على المنحدر يمين';
    case Mnv.rampLeft:
      return 'اطلع على المنحدر يسار';
    case Mnv.rampStraight:
      return 'كمّل على المنحدر';

    case Mnv.exitRight:
      return 'اخرج يمين';
    case Mnv.exitLeft:
      return 'اخرج يسار';

    case Mnv.stayRight:
      return 'ابقَ يمين';
    case Mnv.stayLeft:
      return 'ابقَ يسار';
    case Mnv.stayStraight:
      return 'ابقَ مستقيم';

    case Mnv.merge:
      return 'اندمج';
    case Mnv.mergeRight:
      return 'اندمج يمين';
    case Mnv.mergeLeft:
      return 'اندمج يسار';

    case Mnv.roundaboutEnter:
      final n = m.roundaboutExitCount;
      if (n == null) return 'ادخل الدوّار';
      return 'ادخل الدوّار واخرج من ${_ordinal(n)} مخرج';
    case Mnv.roundaboutExit:
      return 'اخرج من الدوّار';

    case Mnv.ferryEnter:
      return 'اركب المعدية';
    case Mnv.ferryExit:
      return 'انزل من المعدية';

    default:
      return 'كمّل';
  }
}

/// معلم قرب المناورة، يُستعمل حين لا اسم للشارع.
///
/// ═══ قرارك ═══
/// 9% فقط من طرق العراق مسمّاة. وقِسنا على خمسة مسارات في خمس مدن:
/// التعليمات التي فيها اسم شارع 46%، وبإضافة المعالم 83%. فالمعلم نصف
/// التعليمات لا زينة.
///
/// وهو أقرب لطريقة العراقي في الدلالة أصلاً: «لفّ يمين عند الجامع»
/// أوضح من «انعطف يميناً إلى الشارع 60» حتى لو عرفنا اسم الشارع.
/// موضع المعلم من نقطة المناورة على المسار.
enum LandmarkWhere {
  /// يمرّ به السائق ثم ينعطف — «بعد الجامع، انعطف يمين»
  before,

  /// المناورة عنده — «انعطف يمين عند الجامع»
  at,

  /// المناورة قبل الوصول إليه — «انعطف يمين قبل الجامع»
  after,
}

class Landmark {
  final String name;
  final LandmarkWhere where;

  const Landmark(this.name, {this.where = LandmarkWhere.at});

  /// حرف الجرّ المناسب لموضعه.
  ///
  /// الثلاثة ضرورية لا تجميلية: «انعطف عند الجامع» والجامع بعد التقاطع
  /// بمئة متر تجعل السائق يتجاوز التقاطع وهو يبحث عنه.
  String get preposition => switch (where) {
        LandmarkWhere.before => 'بعد',
        LandmarkWhere.at => 'عند',
        LandmarkWhere.after => 'قبل',
      };
}

/// الجملة الكاملة المكتوبة: الفعل + الشارع أو المعلم أو اللوحة.
String maneuverDetail(Maneuver m, {Landmark? landmark}) {
  final title = maneuverTitle(m);
  final street = m.announceStreet;

  if (m.isArrival) {
    // الوصول بمعلم يطمئن السائق أنه في المكان الصحيح
    if (street == null && landmark != null) {
      return '$title — وجهتك عند ${landmark.name}';
    }
    return title;
  }

  // رقم المخرج أهم من اسم الشارع على الطرق السريعة: اللوحة تحمل الرقم
  // والسائق يبحث عنه بعينه
  if (m.exitNumber != null) {
    final toward = m.exitToward.isEmpty ? '' : ' باتجاه ${m.exitToward.first}';
    return '$title — مخرج ${m.exitNumber}$toward';
  }

  if (street != null) {
    // «كمّل مستقيم على شارع فلان» لا «إلى»: أنت فيه أصلاً ولا تدخله
    final prep = (m.type == Mnv.continueOn || m.type == Mnv.becomes ||
            m.type == Mnv.stayStraight)
        ? 'على'
        : 'إلى';
    return '$title $prep $street';
  }

  // لا اسم شارع: المعلم يحلّ محلّه
  if (landmark != null) {
    return '$title ${landmark.preposition} ${landmark.name}';
  }

  return title;
}

/// الجملة الصوتية. المرحلة تحدّد الإسهاب:
///   0 = تمهيد بعيد، 1 = تأكيد، 2 = تنفيذ الآن
String maneuverVoice(Maneuver m, double distanceM, int stage,
    {Landmark? landmark}) {
  if (m.isArrival) {
    if (stage == 2) {
      return landmark == null
          ? 'وصلت وجهتك'
          : 'وصلت وجهتك عند ${landmark.name}';
    }
    return 'وجهتك بعد ${distanceText(distanceM)}';
  }

  final title = maneuverTitle(m);
  final street = m.announceStreet;

  // الشارع أولاً، والمعلم بديله حين يغيب. ما نجمعهما: جملة فيها اسم
  // شارع واسم معلم أطول من أن تُسمع قبل التقاطع
  final where = street != null
      ? ' إلى $street'
      : landmark != null
          ? ' ${landmark.preposition} ${landmark.name}'
          : '';

  switch (stage) {
    case 0:
      // التمهيد: المسافة أولاً كي يعرف السائق أن المناورة ليست الآن
      return 'بعد ${distanceText(distanceM)}، $title$where';

    case 1:
      if (m.exitNumber != null) {
        return 'بعد ${distanceText(distanceM)}، $title من مخرج ${m.exitNumber}';
      }
      // المعلم في التأكيد مفيد: السائق يبحث عنه بعينه الآن
      return 'بعد ${distanceText(distanceM)}، $title'
          '${street != null ? '' : where}';

    default:
      // التنفيذ: أقصر ما يمكن. السائق عند التقاطع ولا وقت لجملة طويلة
      if (m.type == Mnv.roundaboutEnter && m.roundaboutExitCount != null) {
        return '${_ordinal(m.roundaboutExitCount!)} مخرج';
      }
      // المعلم يبقى في التنفيذ حين لا اسم شارع: «انعطف يمين» وحدها عند
      // تقاطع مزدوج تترك السائق يحزر أيّهما
      if (street == null && landmark != null) {
        return '$title ${landmark.preposition} ${landmark.name}';
      }
      return title;
  }
}

/// جملة تنبيه بلاغ أمام السائق.
String reportAlertVoice(String kind, String label, double distanceM) {
  switch (kind) {
    case 'speed_camera':
      return 'انتبه، رادار بعد ${distanceText(distanceM)}';
    case 'police':
    case 'checkpoint':
      return '$label بعد ${distanceText(distanceM)}';
    case 'crash':
      return 'حادث على طريقك بعد ${distanceText(distanceM)}';
    case 'jam':
      return 'زحام قدّامك بعد ${distanceText(distanceM)}';
    case 'road_closed':
      return 'الطريق مغلق بعد ${distanceText(distanceM)}';
    case 'pothole':
      return 'حفرة قدّامك';
    case 'flood':
      return 'ماء على الطريق بعد ${distanceText(distanceM)}';
    case 'fuel_queue':
      return 'طابور وقود بعد ${distanceText(distanceM)}';
    default:
      return '$label بعد ${distanceText(distanceM)}';
  }
}

/// المسافة منطوقة. نقرّبها بقصد: «بعد 487 متر» دقة زائفة ومربكة، و«بعد
/// 500 متر» هي ما يقوله إنسان.
String distanceText(double meters) {
  if (meters < 30) return 'الآن';
  if (meters < 1000) {
    final rounded = meters < 150
        ? (meters / 10).round() * 10
        : (meters / 50).round() * 50;
    return '$rounded متر';
  }
  final km = meters / 1000.0;
  if (km < 10) {
    final s = km.toStringAsFixed(1).replaceAll('.0', '');
    return '$s كيلومتر';
  }
  return '${km.round()} كيلومتر';
}

/// المسافة مكتوبة — أقصر من المنطوقة لأن المساحة على الشاشة ضيقة.
String distanceLabel(double meters) {
  if (meters < 1000) return '${(meters / 10).round() * 10} م';
  final km = meters / 1000.0;
  return km < 10 ? '${km.toStringAsFixed(1)} كم' : '${km.round()} كم';
}

/// الزمن المتبقّي مكتوباً.
String durationLabel(double seconds) {
  // الفحص على الثواني لا على الدقائق المقرَّبة: 30 ثانية تُقرَّب لدقيقة
  // (التقريب يرفع النصف) فكانت تُعرض «1 دقيقة» وأنت على بعد نصفها
  if (seconds < 45) return 'أقل من دقيقة';

  final mins = (seconds / 60).round();
  if (mins < 60) return '$mins دقيقة';

  final h = mins ~/ 60;
  final m = mins % 60;
  if (m == 0) return h == 1 ? 'ساعة' : '$h ساعات';
  return h == 1 ? 'ساعة و$m دقيقة' : '$h ساعات و$m دقيقة';
}

/// وقت الوصول المتوقّع بصيغة 12 ساعة عربية.
String arrivalLabel(DateTime at) {
  final h24 = at.hour;
  final period = h24 < 12 ? 'ص' : 'م';
  var h = h24 % 12;
  if (h == 0) h = 12;
  final mm = at.minute.toString().padLeft(2, '0');
  return '$h:$mm $period';
}

/// الترتيب العربي حتى العاشر — مخارج الدوّارات ما تزيد عليه عملياً.
String _ordinal(int n) {
  const words = [
    '', 'أول', 'ثاني', 'ثالث', 'رابع', 'خامس',
    'سادس', 'سابع', 'ثامن', 'تاسع', 'عاشر',
  ];
  return n >= 1 && n < words.length ? words[n] : '$n';
}

/// جمل حالة الملاحة.
const String msgRerouting = 'نعيد حساب الطريق';
const String msgOffRoute = 'طلعت عن الطريق';
const String msgNoRoute = 'ما لقينا طريقاً لهذي الوجهة';
const String msgOffline = 'لا إنترنت — الملاحة تشتغل، بس بلا زحام ولا بلاغات';
const String msgGpsWeak = 'إشارة GPS ضعيفة';
const String msgArrived = 'وصلت';
