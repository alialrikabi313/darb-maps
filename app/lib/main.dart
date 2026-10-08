// نقطة الدخول.
//
// الواجهة عربية RTL بالكامل، فنفرض الاتجاه هنا مرة لا في كل شاشة.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'state/app_state.dart';
import 'ui/shell.dart';
import 'ui/theme.dart';

void main() {
  runApp(
    ChangeNotifierProvider(
      // lazy: false — التهيئة تلصق الحزمة وتشغّل سيرفر البلاطات، ونبيها
      // تبدأ مع الإقلاع لا عند أول قراءة للحالة
      create: (_) => AppState()..init(),
      lazy: false,
      child: const DarbApp(),
    ),
  );
}

class DarbApp extends StatelessWidget {
  const DarbApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'دربنا',
      debugShowCheckedModeBanner: false,
      locale: const Locale('ar'),
      theme: D.theme(),
      // RTL مفروض لا مستنتَج: Directionality المستنتَجة تتبع لغة الجهاز،
      // وجهاز بإنجليزية يعرض واجهتنا العربية معكوسة
      builder: (context, child) => Directionality(
        textDirection: TextDirection.rtl,
        child: child ?? const SizedBox.shrink(),
      ),
      home: const Shell(),
    );
  }
}
