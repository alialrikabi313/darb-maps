// الخدمة المقدّمة التي تُبقي الملاحة شغّالة.
//
// المشكلة الحقيقية: أندرويد يقتل التطبيق حين تُقفل الشاشة أو يُصغَّر،
// فينقطع تدفّق الموقع وتتوقّف الملاحة في منتصف الرحلة. الخدمة المقدّمة
// بإشعار دائم هي الطريقة الوحيدة التي يقبلها النظام لإبقاء العملية حيّة.
//
// الأهم: نضع التعليمة القادمة في نصّ الإشعار. السائق اللي قفل شاشته أو
// فتح واتساب يشوف «بعد 300م — انعطف يمين» في شريط الإشعارات بلا ما يرجع
// للتطبيق. هذا مو تجميلاً، هو نصف قيمة الخدمة.
//
// ملاحظة صريحة عن حدودنا: Xiaomi و Huawei و Oppo يقتلون الخدمات المقدّمة
// بسياسات خاصة فوق سلوك أندرويد القياسي، ولا يكفيها إعفاء البطارية.
// معالجتها تحتاج توجيه المستخدم لإعدادات كل شركة، وهو ما لم نسوّه بعد.

import 'dart:async';

import 'package:flutter_foreground_task/flutter_foreground_task.dart';

/// معالج يشتغل في عزلة منفصلة.
///
/// فارغ بقصد: ما نحتاج حساباً هناك. وجود الخدمة نفسه هو ما يمنع النظام
/// من قتل العملية، وتدفّق الموقع يكمل في العزلة الرئيسية. معالج يحسب
/// شيئاً هنا يعني نقل حالة الملاحة كلها بين عزلتين بلا مقابل.
@pragma('vm:entry-point')
void navServiceEntry() {
  FlutterForegroundTask.setTaskHandler(_KeepAliveHandler());
}

class _KeepAliveHandler extends TaskHandler {
  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {}

  @override
  void onRepeatEvent(DateTime timestamp) {}

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {}

  @override
  void onNotificationPressed() {
    // ضغط الإشعار يرجّع التطبيق للمقدّمة بدل ما يفتحه من جديد
    FlutterForegroundTask.launchApp();
  }
}

class NavService {
  bool _initialized = false;
  bool _running = false;

  bool get isRunning => _running;

  void init() {
    if (_initialized) return;

    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'darb_navigation',
        channelName: 'الملاحة',
        channelDescription:
            'إشعار دائم يُبقي الملاحة شغّالة والشاشة مقفلة، ويعرض '
            'التعليمة القادمة',
        // أهمية منخفضة: الإشعار لازم يظهر ولا يرنّ. صوت مع كل تحديث
        // تعليمة يعني رنّة كل بضع ثوان
        channelImportance: NotificationChannelImportance.LOW,
        priority: NotificationPriority.LOW,
        playSound: false,
        enableVibration: false,
        // onlyAlertOnce: التحديث ما يعيد التنبيه — نحدّث النصّ كثيراً
        onlyAlertOnce: true,
        showWhen: false,
      ),
      iosNotificationOptions: const IOSNotificationOptions(
        showNotification: true,
        playSound: false,
      ),
      foregroundTaskOptions: ForegroundTaskOptions(
        // ما نحتاج حدثاً دورياً: المعالج فارغ والعمل كله في العزلة
        // الرئيسية. حدث كل ثانية يستهلك بطارية بلا فائدة
        eventAction: ForegroundTaskEventAction.nothing(),
        // قفل الاستيقاظ ضروري: بلاه ينام المعالج بين قراءات GPS فتتأخّر
        // التعليمات ثوانٍ، وهي كافية لتفويت مخرج
        allowWakeLock: true,
        // قفل الواي-فاي لا نحتاجه: الملاحة على بيانات الجوّال غالباً،
        // والقفل يستهلك بطارية
        allowWifiLock: false,
        // الخدمة تموت مع التطبيق: ملاحة شغّالة بعد ما يقتل المستخدم
        // التطبيق سلوك مزعج يُبلَّغ عنه كخلل
        stopWithTask: true,
        autoRunOnBoot: false,
        allowAutoRestart: false,
      ),
    );

    _initialized = true;
  }

  /// يطلب الصلاحيات التي تحتاجها الخدمة.
  ///
  /// يرجّع رسالة عربية للمستخدم إن كان شيء ناقصاً، أو null إن كان تماماً.
  /// ما نفرض شيئاً: نشرح ونترك القرار له.
  Future<String?> requestPermissions() async {
    final notif = await FlutterForegroundTask.checkNotificationPermission();
    if (notif != NotificationPermission.granted) {
      final result =
          await FlutterForegroundTask.requestNotificationPermission();
      if (result != NotificationPermission.granted) {
        return 'بلا صلاحية الإشعارات ما نقدر نُبقي الملاحة شغّالة والشاشة '
            'مقفلة — راح تتوقّف إذا صغّرت التطبيق';
      }
    }

    // إعفاء البطارية: نطلبه ولا نُلزم به. رفضه يعني ملاحة تتوقّف على
    // بعض الأجهزة، فنقول ذلك صريحاً بدل ما نسكت
    final exempt = await FlutterForegroundTask.isIgnoringBatteryOptimizations;
    if (!exempt) {
      return 'جهازك يوفّر البطارية بإيقاف التطبيقات في الخلفية. إذا '
          'توقّفت الملاحة وأنت تسوق، اعفِ «درب» من توفير البطارية من '
          'الإعدادات.';
    }

    return null;
  }

  /// يفتح شاشة إعفاء البطارية — نناديها من زرّ لا تلقائياً.
  Future<void> openBatterySettings() =>
      FlutterForegroundTask.openIgnoreBatteryOptimizationSettings();

  Future<bool> start({required String title, required String text}) async {
    init();
    if (_running) return true;

    final result = await FlutterForegroundTask.startService(
      // النوع location مُعلَن في الـmanifest أيضاً: أندرويد 14+ يرفض
      // تشغيل الخدمة بـSecurityException إن لم يتطابقا
      serviceTypes: const [ForegroundServiceTypes.location],
      notificationTitle: title,
      notificationText: text,
      callback: navServiceEntry,
    );

    _running = result is ServiceRequestSuccess;
    return _running;
  }

  /// يحدّث نصّ الإشعار بالتعليمة القادمة.
  ///
  /// نُنادى كل قراءة GPS، فنتجاهل التحديث إن كان النصّ نفسه: تحديث
  /// الإشعار عملية نظام، وتكرارها بلا تغيير يستهلك بطارية ويثقّل الشريط.
  String _lastText = '';

  Future<void> update({required String title, required String text}) async {
    if (!_running || text == _lastText) return;
    _lastText = text;

    await FlutterForegroundTask.updateService(
      notificationTitle: title,
      notificationText: text,
    );
  }

  Future<void> stop() async {
    if (!_running) return;
    await FlutterForegroundTask.stopService();
    _running = false;
    _lastText = '';
  }
}
