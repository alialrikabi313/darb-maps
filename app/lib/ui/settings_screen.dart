// الإعدادات.
//
// قليلة بقصد: كل خيار زائد قرار يُفرض على المستخدم. هنا ما يؤثّر فعلاً
// على تجربته — الصوت، والخصوصية، وحالة الاتصال.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../config.dart';
import '../state/app_state.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();

    return Scaffold(
      appBar: AppBar(title: const Text('الإعدادات')),
      body: ListView(
        children: [
          const _SectionTitle('الصوت'),
          SwitchListTile(
            title: const Text('التوجيه الصوتي'),
            subtitle: Text(app.voice.arabicAvailable
                ? 'ينطق التعليمات والتنبيهات'
                : 'محرّك النطق العربي مو منصّب على جهازك'),
            value: !app.muted && app.voice.arabicAvailable,
            onChanged: app.voice.arabicAvailable
                ? (v) => app.setMuted(!v)
                : null,
          ),

          const _SectionTitle('الخصوصية'),
          SwitchListTile(
            title: const Text('المشاركة في بيانات الزحام'),
            subtitle: const Text(
              'نرسل سرعتك على كل قطعة طريق بلا هويتك وبلا مسارك الكامل، '
              'ونحذف بداية رحلتك ونهايتها قبل الإرسال. هذا ما يجعل الزحام '
              'الحيّ ممكناً.',
            ),
            isThreeLine: true,
            value: app.traceEnabled,
            onChanged: app.setTraceEnabled,
          ),
          ListTile(
            leading: const Icon(Icons.shield_outlined),
            title: const Text('شنو نرسل بالضبط'),
            subtitle: Text(
              'قطعة طريق + سرعة + وقت. لا معرّف جهاز، ولا معرّف رحلة، '
              'ولا ترتيب القطع. أول ${Cfg.tracePointsPerChunk} نقطة '
              'تُرسل دفعة، وتُحذف نقاط أول وآخر 300 متر.',
              style: const TextStyle(height: 1.4),
            ),
          ),

          const _SectionTitle('الاتصال'),
          ListTile(
            leading: Icon(
              app.backendUp ? Icons.cloud_done : Icons.cloud_off,
              color: app.backendUp
                  ? const Color(0xFF2BB673)
                  : const Color(0xFF6B7280),
            ),
            title: Text(app.backendUp ? 'متصل بالسيرفر' : 'بلا سيرفر'),
            subtitle: Text(app.backendUp
                ? 'البلاغات والزحام والتوجيه شغّالة'
                // نفصّل ما يشتغل وما لا يشتغل: «بلا اتصال» وحدها تخلّي
                // المستخدم يظن أن التطبيق معطّل كلياً
                : 'الخريطة والبحث يشتغلون. البلاغات والزحام والتوجيه '
                    'يحتاجون اتصالاً.\n${Cfg.apiBase}'),
            isThreeLine: !app.backendUp,
          ),

          const _SectionTitle('عن التطبيق'),
          const ListTile(
            leading: Icon(Icons.map_outlined),
            title: Text('بيانات الخريطة'),
            subtitle: Text(
              '© OpenStreetMap contributors — ترخيص ODbL.\n'
              'التوجيه بـValhalla، والبلاطات ببناء Planetiler.',
              style: TextStyle(height: 1.4),
            ),
            isThreeLine: true,
          ),
          const ListTile(
            leading: Icon(Icons.edit_location_alt_outlined),
            title: Text('اسم ناقص أو غلط في الخريطة؟'),
            subtitle: Text(
              'الخريطة يحرّرها المجتمع. تعديلك يفيد كل من يستخدمها — '
              'تحرير الخريطة من داخل التطبيق قادم.',
              style: TextStyle(height: 1.4),
            ),
            isThreeLine: true,
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 16, left: 16, top: 20, bottom: 6),
      child: Text(text,
          style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: Color(0xFF2D7FF9))),
    );
  }
}
