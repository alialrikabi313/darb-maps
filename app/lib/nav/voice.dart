// التوجيه الصوتي العربي.
//
// صياغة الجمل في phrases.dart (قرار صاحب المشروع)؛ هذا الملف يشغّلها فقط.
//
// مشكلة واقعية: محرّك النطق العربي مو موجود على كل جهاز أندرويد. نفحصه
// عند الإقلاع ونخبر المستخدم بصراحة إن كان ناقصاً، بدل ما يبقى التطبيق
// صامتاً وهو يظن أنه عطّل الصوت بالغلط.

import 'package:flutter_tts/flutter_tts.dart';
import 'package:vibration/vibration.dart';

class Voice {
  final _tts = FlutterTts();

  bool _ready = false;
  bool _arabicAvailable = false;
  bool muted = false;
  bool vibrateOnAlert = true;

  /// آخر جملة نُطقت ووقتها — نمنع بها التكرار.
  String _lastSpoken = '';
  DateTime _lastAt = DateTime.fromMillisecondsSinceEpoch(0);

  bool get arabicAvailable => _arabicAvailable;

  /// رسالة للمستخدم إن كان الصوت العربي ناقصاً، أو null إذا كل شيء تمام.
  String? get warning => _arabicAvailable
      ? null
      : 'محرّك النطق العربي مو منصّب على جهازك — التوجيه راح يكون مكتوباً '
          'فقط. نصّبه من إعدادات الجهاز ← اللغة ← تحويل النص لكلام';

  Future<void> init() async {
    final langs = await _tts.getLanguages;
    final list = (langs as List?)?.map((e) => '$e'.toLowerCase()) ?? const [];

    // نقبل أي عربية: ar-SA و ar-EG و ar موجودة حسب الجهاز، وأي منها
    // ينطق العربية الفصحى المكتوبة عندنا
    final arabic = list.firstWhere((l) => l.startsWith('ar'),
        orElse: () => '');
    _arabicAvailable = arabic.isNotEmpty;

    if (_arabicAvailable) {
      await _tts.setLanguage(arabic);
      // 0.45 لا الافتراضي: محرّكات النطق العربية تقرأ بسرعة تُفقد الوضوح
      // في السيارة مع ضجيج الطريق. جرّبنا 0.6 فكان «انعطف يمين» يُسمع
      // كلمة واحدة
      await _tts.setSpeechRate(0.45);
      await _tts.setVolume(1.0);
      await _tts.setPitch(1.0);
    }

    // الصوت يقطع موسيقى المستخدم بدل ما يختلط بها: جملة ملاحة تُسمع
    // تحت أغنية لا تُفهم، وتفويت مناورة أسوأ من تقطيع ثانيتين
    await _tts.setIosAudioCategory(
      IosTextToSpeechAudioCategory.playback,
      [
        IosTextToSpeechAudioCategoryOptions.duckOthers,
        IosTextToSpeechAudioCategoryOptions.mixWithOthers,
      ],
    );

    _ready = true;
  }

  /// ينطق الجملة. يتجاهلها إذا كانت نفس آخر جملة خلال cooldown.
  ///
  /// التكرار مشكلة حقيقية لا احتياط: المسافة تتأرجح حول عتبة الإعلان عند
  /// الوقوف في زحام، فيكرّر التطبيق «انعطف يمين» عشر مرات في دقيقة.
  Future<void> say(String text,
      {Duration cooldown = const Duration(seconds: 12),
      bool interrupt = false}) async {
    if (!_ready || muted || text.isEmpty) return;

    final now = DateTime.now();
    if (text == _lastSpoken && now.difference(_lastAt) < cooldown) return;

    _lastSpoken = text;
    _lastAt = now;

    if (interrupt) await _tts.stop();
    if (_arabicAvailable) await _tts.speak(text);
  }

  /// تنبيه بلاغ: صوت + اهتزاز. الاهتزاز مهم لمن يسوق بصوت مكتوم.
  Future<void> alert(String text) async {
    if (vibrateOnAlert && (await Vibration.hasVibrator())) {
      // نبضتان قصيرتان: نبضة واحدة تُخلط مع إشعار واتساب
      await Vibration.vibrate(pattern: [0, 120, 90, 120]);
    }
    await say(text, interrupt: true);
  }

  Future<void> stop() => _tts.stop();

  /// ينسى آخر جملة. نناديها عند حساب مسار جديد كي تُنطق التعليمة الأولى
  /// حتى لو كانت نفس نصّ آخر تعليمة في المسار القديم.
  void resetHistory() {
    _lastSpoken = '';
    _lastAt = DateTime.fromMillisecondsSinceEpoch(0);
  }
}
