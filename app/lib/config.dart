// إعدادات darb كلها في مكان واحد.
//
// عدّل هنا فقط عند تغيير عنوان الباكند، أو سلوك الكاميرا والتنبيهات، أو
// مسافات التنبيه الصوتي. باقي الملفات تستورد من هنا ولا تحمل أرقاماً مبثوثة.
//
// القيم المعلّمة بـ«قرارك» قرارات مجال ترجع لصاحب المشروع — كُتبت مبدئية
// ليشتغل الكود، وتُراجَع كلها من هذا الملف.

library;

class Cfg {
  Cfg._();

  // ── الباكند ──────────────────────────────────────────────────────────────

  // 10.0.2.2 هو localhost الجهاز المضيف من داخل محاكي أندرويد. على جهاز
  // حقيقي بدّله لعنوان الشبكة المحلية — أو أبقِه فارغاً ليشتغل التطبيق
  // أوفلاين كاملاً بلا بلاغات ولا زحام
  static const String apiBase = 'http://10.0.2.2:8080';

  // التوجيه يمرّ بالباكند لا بـValhalla مباشرة: الباكند يحقن الإغلاقات
  // المبلَّغ عنها وحالة الزحام في نفس الطلب
  static const Duration apiTimeout = Duration(seconds: 20);
  static const Duration apiTimeoutLive = Duration(seconds: 5);

  // ── البلاطات والخريطة ────────────────────────────────────────────────────

  // سيرفر محلي داخل التطبيق يقدّم البلاطات لـMapLibre. المنفذ 0 يعني
  // «اختر أي منفذ حرّ» — منفذ ثابت يتضارب مع تطبيق آخر على نفس الجهاز
  static const int tileServerPort = 0;

  // الحزمة المشحونة مع التطبيق. يضبطها tools/07_pack_assets.py ويكتب
  // معها manifest.json يصف قطعها — الملفات مقطّعة لأن rootBundle.load
  // تحمّل الأصل كاملاً في الذاكرة، و178MB تعني انهياراً
  static const String bundledPack = 'iraq';
  static const String packManifestAsset = 'assets/data/manifest.json';

  static const double startLat = 33.3074; // ساحة التحرير
  static const double startLon = 44.4009;
  static const double startZoom = 13.0;

  // ── الكاميرا ─────────────────────────────────────────────────────────────

  // الكاميرا أثناء الملاحة: مائلة وقريبة وتدور مع اتجاه السيارة. هذا ما
  // يجعل الملاحة مقروءة بطرف العين لا شيئاً تحتاج أن تدقّق فيه
  static const double navZoom = 17.5;
  static const double navTilt = 60.0;
  // الكاميرا تسبق السيارة: السهم في الثلث الأسفل من الشاشة لا في وسطها،
  // فيرى السائق ما أمامه لا ما خلفه
  static const double navAnchorY = 0.72;

  static const double overviewZoom = 14.0;
  static const double overviewTilt = 0.0;

  // تنعيم دوران الكاميرا. GPS يرمي اتجاهاً مضطرباً عند السرعات الواطئة،
  // وبلا تنعيم تدور الخريطة حول نفسها في كل إشارة مرور
  static const double headingSmoothing = 0.25; // 0=لا يتحرك، 1=بلا تنعيم

  // تحت هذي السرعة نتجاهل اتجاه GPS ونستخدم البوصلة: GPS ما يعرف اتجاهك
  // وأنت واقف، يعطي آخر اتجاه حركة أو قيمة عشوائية
  static const double headingFromGpsMinSpeedKmh = 8.0;

  // ── الموقع ───────────────────────────────────────────────────────────────

  // كل 5 أمتار: أكثف من هذا يستهلك بطارية بلا دقة أفضل، وأخفّ يجعل السهم
  // ينط بين الموقعين
  static const int locationDistanceFilterM = 5;

  // قراءة بدقة أسوأ من هذا تُهمل: في أنفاق بغداد ومواقف المولات يرمي GPS
  // مواقع بدقة 200 متر، ورسمها يطوّح السهم لحيٍّ مجاور
  static const double locationMaxAccuracyM = 50.0;

  // ── مطابقة المسار ────────────────────────────────────────────────────────

  // أقصى بعد عن خط المسار قبل ما نعدّه خروجاً عنه. 40 متراً: طريق محمد
  // القاسم عريض وله خدمي موازٍ، وعتبة أضيق تعلن خروجاً وأنت على مسارك
  static const double offRouteThresholdM = 40.0;

  // لا نعلن الخروج من أول قراءة: قراءة GPS واحدة شاذة تحدث كل دقيقة،
  // وإعادة حساب المسار عندها تربك السائق أكثر مما تساعده
  static const int offRouteConsecutiveFixes = 3;

  // ── التنبيهات الصوتية ────────────────────────────────────────────────────

  // مسافات الإعلان قبل المناورة بالأمتار، من البعيد للقريب. ثلاث مراحل:
  // تمهيد، تأكيد، تنفيذ. على الطرق السريعة المسافات تُضاعَف تلقائياً لأن
  // 300 متر بسرعة 100 كم/س هي عشر ثوان
  // قرارك: المسافات مبدئية ومن منطق لا من قياس على طرق بغداد
  static const List<double> announceDistancesM = [800, 300, 80];
  static const double highwaySpeedKmh = 80.0;
  static const double highwayAnnounceMultiplier = 1.8;

  // لا نعيد نفس الجملة قبل مرور هذا الوقت: المسافة تتأرجح حول العتبة عند
  // الوقوف في زحام، فيكرّر التطبيق «انعطف يميناً» عشر مرات
  static const Duration announceCooldown = Duration(seconds: 12);

  // مسافة التنبيه على بلاغ أمامك. الرادار يحتاج مسافة أطول: التنبيه قبل
  // 200 متر بسرعة 100 كم/س متأخّر جداً
  static const Map<String, double> alertDistanceM = {
    'speed_camera': 600,
    'police': 500,
    'checkpoint': 500,
    'crash': 500,
    'road_closed': 800,
    'hazard': 300,
    'pothole': 150,
    'jam': 700,
    'flood': 400,
    'fuel_queue': 300,
  };

  // البلاغ على مسارك فقط ينبّه. 50 متراً عن الخط: البلاغ على الطريق
  // الموازي يُعرض على الخريطة ولا يُنطق
  static const double alertCorridorM = 50.0;

  // ── الزحام ───────────────────────────────────────────────────────────────

  static const Map<String, int> trafficColors = {
    'free': 0xFF2BB673,
    'moderate': 0xFFF2C037,
    'heavy': 0xFFF07B2B,
    'jam': 0xFFD6333F,
  };

  // ── إرسال قراءات السرعة ──────────────────────────────────────────────────

  // قرارك (خصوصية): نرسل الرحلة قطعاً لا كاملة، وكل قطعة بحد أقصى من
  // النقاط. قطعة أطول تعني مساراً أكمل في يد السيرفر، وهو ما نتجنّبه
  static const int tracePointsPerChunk = 60;
  static const bool traceEnabledByDefault = true;

  // ── البحث ────────────────────────────────────────────────────────────────

  static const int searchLimit = 12;
  // لا نبحث قبل حرفين: حرف واحد يطابق آلاف النتائج ويبطّئ الكتابة
  static const int searchMinChars = 2;
  static const Duration searchDebounce = Duration(milliseconds: 180);
}
