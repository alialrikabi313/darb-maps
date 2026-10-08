// تبويب حسابي: الإعدادات والخرائط الأوفلاين والخصوصية.
//
// «حساب» بلا تسجيل: التطبيق يشتغل بلا بريد ولا كلمة مرور. ما يُعرض هنا
// هو ما يخصّ هذا الجهاز — صوته وخصوصيته وخرائطه.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../config.dart';
import '../state/app_state.dart';
import 'offline_screen.dart';
import 'saved_screen.dart' show SheetScaffold;
import 'theme.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();

    return SheetScaffold(
      title: 'حسابي',
      subtitle: 'هذا الجهاز — بلا تسجيل ولا بريد',
      icon: Icons.person_rounded,
      children: [
        _StatusCard(app: app),

        const SizedBox(height: 20),
        const DSectionHeader(title: 'الصوت', icon: Icons.volume_up_rounded),
        const SizedBox(height: 8),
        _SwitchRow(
          icon: Icons.record_voice_over_outlined,
          title: 'التوجيه الصوتي',
          subtitle: app.voice.arabicAvailable
              ? 'ينطق التعليمات والتنبيهات بالعربية'
              : 'محرّك النطق العربي مو منصّب على جهازك',
          value: !app.muted && app.voice.arabicAvailable,
          onChanged:
              app.voice.arabicAvailable ? (v) => app.setMuted(!v) : null,
        ),

        const SizedBox(height: 20),
        const DSectionHeader(
            title: 'الخصوصية', icon: Icons.shield_outlined),
        const SizedBox(height: 8),
        _SwitchRow(
          icon: Icons.speed_outlined,
          title: 'المشاركة في بيانات الزحام',
          subtitle: 'سرعتك على كل قطعة طريق، بلا هويتك وبلا مسارك الكامل',
          value: app.traceEnabled,
          onChanged: app.setTraceEnabled,
        ),
        const SizedBox(height: 8),
        _InfoRow(
          icon: Icons.lock_outline,
          title: 'شنو نرسل بالضبط',
          subtitle: 'قطعة طريق + سرعة + وقت. لا معرّف جهاز، ولا معرّف '
              'رحلة، ولا ترتيب القطع. ونحذف نقاط أول وآخر 300 متر من كل '
              'رحلة — أولها البيت وآخرها الوجهة، وهما أخطر نقطتين.',
        ),

        const SizedBox(height: 20),
        const DSectionHeader(
            title: 'الخرائط', icon: Icons.map_outlined),
        const SizedBox(height: 8),
        _InfoRow(
          icon: Icons.download_done_outlined,
          title: 'خرائط أوفلاين',
          subtitle: 'الخريطة والبحث يشتغلون بلا إنترنت',
          onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const OfflineScreen())),
        ),

        const SizedBox(height: 20),
        const DSectionHeader(
            title: 'عن التطبيق', icon: Icons.info_outline),
        const SizedBox(height: 8),
        const _InfoRow(
          icon: Icons.public,
          title: 'بيانات الخريطة',
          subtitle: '© OpenStreetMap contributors — ترخيص ODbL.\n'
              'التوجيه بـValhalla، والبلاطات ببناء Planetiler.',
        ),
        const SizedBox(height: 8),
        const _InfoRow(
          icon: Icons.edit_location_alt_outlined,
          title: 'اسم ناقص أو غلط في الخريطة؟',
          subtitle: '8% فقط من طرق العراق مسمّاة في الخريطة المفتوحة. '
              'تحريرها من داخل التطبيق قادم.',
        ),
      ],
    );
  }
}

class _StatusCard extends StatelessWidget {
  final AppState app;
  const _StatusCard({required this.app});

  @override
  Widget build(BuildContext context) {
    final up = app.backendUp;

    return DCard(
      color: up ? D.mintPale : D.cardInner,
      shadow: const [],
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(up ? 'متصل بالسيرفر' : 'بلا سيرفر',
                    style: D.h3.copyWith(
                        color: up ? D.greenDeep : D.text)),
                const SizedBox(height: 3),
                Text(
                  up
                      ? 'البلاغات والزحام والتوجيه شغّالة'
                      // نفصّل ما يشتغل وما لا يشتغل: «بلا اتصال» وحدها
                      // تخلّي المستخدم يظن أن التطبيق معطّل كلياً
                      : 'الخريطة والبحث يشتغلون.\nالبلاغات والزحام '
                          'والتوجيه يحتاجون اتصالاً.',
                  style: D.caption,
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          DIconCircle(up ? Icons.cloud_done : Icons.cloud_off,
              size: 48,
              background: up ? D.mint : D.divider,
              foreground: up ? D.greenDeep : D.textSoft),
        ],
      ),
    );
  }
}

class _SwitchRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool>? onChanged;

  const _SwitchRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return DCard(
      color: D.cardInner,
      shadow: const [],
      radius: D.rInner,
      padding: const EdgeInsets.fromLTRB(8, 10, 12, 10),
      child: Row(
        children: [
          Switch(
            value: value,
            onChanged: onChanged,
            activeThumbColor: Colors.white,
            activeTrackColor: D.green,
          ),
          const Spacer(),
          Expanded(
            flex: 5,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(title, style: D.h3),
                Text(subtitle,
                    textAlign: TextAlign.right, style: D.caption),
              ],
            ),
          ),
          const SizedBox(width: 10),
          DIconCircle(icon, size: 40, foreground: D.greenDeep),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;

  const _InfoRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return DCard(
      color: D.cardInner,
      shadow: const [],
      radius: D.rInner,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      onTap: onTap,
      child: Row(
        children: [
          if (onTap != null)
            const Icon(Icons.chevron_left, color: D.textSoft),
          const Spacer(),
          Expanded(
            flex: 6,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(title, style: D.h3),
                const SizedBox(height: 2),
                Text(subtitle,
                    textAlign: TextAlign.right, style: D.caption),
              ],
            ),
          ),
          const SizedBox(width: 10),
          DIconCircle(icon, size: 40, foreground: D.greenDeep),
        ],
      ),
    );
  }
}

/// عنوان الباكند — يُعرض في شاشة الأوفلاين وشاشة الحالة.
String get backendLabel => Cfg.apiBase;
