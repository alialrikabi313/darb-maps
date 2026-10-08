// تبويب المجتمع: الإبلاغ عن حالة، وما بلّغ به السائقون حولك.
//
// التغذية من بلاغات حقيقية في الباكند لا بيانات عرض: إذا كان السيرفر
// واقفاً تظهر الحالة الفارغة صريحة بسببها، لا قائمة مزيّفة.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../nav/phrases.dart';
import '../reports/reports.dart';
import '../state/app_state.dart';
import 'nav_overlay.dart' show ReportTypeTile, showDarbSnack;
import 'saved_screen.dart' show SheetScaffold;
import 'theme.dart';

class CommunityScreen extends StatefulWidget {
  const CommunityScreen({super.key});

  @override
  State<CommunityScreen> createState() => _CommunityScreenState();
}

class _CommunityScreenState extends State<CommunityScreen> {
  bool _newestFirst = true;

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final feed = _sorted(app.visibleReports);

    return SheetScaffold(
      title: 'الإبلاغ عن حادث أو حالة',
      subtitle: 'ساعد المجتمع بتنبيه الآخرين',
      icon: Icons.campaign_rounded,
      children: [
        if (app.reports.types.isEmpty)
          _Offline(message: app.reports.lastError)
        else
          GridView.count(
            shrinkWrap: true,
            crossAxisCount: 4,
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: 0.84,
            physics: const NeverScrollableScrollPhysics(),
            children: [
              for (final t in app.reports.types)
                ReportTypeTile(
                  type: t,
                  onTap: () => _send(context, t),
                ),
            ],
          ),

        const SizedBox(height: 22),
        const Divider(),
        const SizedBox(height: 12),

        Row(
          children: [
            // ترتيب التغذية: الأحدث أو الأقرب. الأقرب أنفع وأنت تسوق،
            // والأحدث أنفع وأنت تخطّط
            DCard(
              radius: D.rPill,
              color: D.cardInner,
              shadow: const [],
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              onTap: () => setState(() => _newestFirst = !_newestFirst),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.keyboard_arrow_down,
                      size: 18, color: D.textSoft),
                  const SizedBox(width: 5),
                  Text(_newestFirst ? 'الأحدث أولاً' : 'الأقرب أولاً',
                      style: D.bodySoft),
                ],
              ),
            ),
            const Spacer(),
            const Expanded(
              flex: 4,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text('نشاط المجتمع', style: D.h2),
                  Text('تنبيهات مباشرة من السائقين حولك',
                      style: D.caption),
                ],
              ),
            ),
          ],
        ),

        const SizedBox(height: 12),

        if (feed.isEmpty)
          _EmptyFeed(backendUp: app.backendUp)
        else
          for (final r in feed) ...[
            _FeedCard(report: r),
            const SizedBox(height: 8),
          ],
      ],
    );
  }

  List<Report> _sorted(List<Report> list) {
    final out = [...list];
    if (_newestFirst) {
      out.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    } else {
      out.sort((a, b) =>
          (a.distanceM ?? 1e9).compareTo(b.distanceM ?? 1e9));
    }
    return out;
  }

  Future<void> _send(BuildContext context, ReportType t) async {
    final app = context.read<AppState>();
    final err = await app.sendReport(t.kind);
    if (!context.mounted) return;
    showDarbSnack(context, err ?? 'شكراً — وصل بلاغك وصار يشوفه غيرك',
        isError: err != null);
  }
}

class _FeedCard extends StatelessWidget {
  final Report report;
  const _FeedCard({required this.report});

  @override
  Widget build(BuildContext context) {
    final app = context.read<AppState>();
    final look = lookFor(report.kind);

    return DCard(
      color: D.cardInner,
      shadow: const [],
      radius: D.rInner,
      padding: const EdgeInsets.fromLTRB(10, 10, 12, 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // زرّ التأييد بعدّاده — مثل التصميم
          Column(
            children: [
              DCard(
                radius: D.rPill,
                color: D.card,
                shadow: const [],
                padding: const EdgeInsets.symmetric(
                    horizontal: 10, vertical: 7),
                onTap: () async {
                  final err = await app.voteReport(report.id, isUp: true);
                  if (err != null && context.mounted) {
                    showDarbSnack(context, err, isError: true);
                  }
                },
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('${report.upVotes}',
                        style: D.caption.copyWith(
                            fontWeight: FontWeight.w700, color: D.text)),
                    const SizedBox(width: 5),
                    const Icon(Icons.thumb_up_alt_outlined,
                        size: 14, color: D.textSoft),
                  ],
                ),
              ),
            ],
          ),

          const Spacer(),

          Expanded(
            flex: 6,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(report.label, style: D.h3),
                if (report.note != null && report.note!.isNotEmpty)
                  Text(report.note!,
                      textAlign: TextAlign.right,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: D.bodySoft),
                const SizedBox(height: 3),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    if (!report.confirmed) ...[
                      Text('غير مؤكّد',
                          style: D.caption.copyWith(color: D.warn)),
                      const SizedBox(width: 8),
                    ],
                    if (report.distanceM != null) ...[
                      Text(distanceLabel(report.distanceM!),
                          style: D.caption),
                      const SizedBox(width: 3),
                      const Icon(Icons.place, size: 11, color: D.textSoft),
                      const SizedBox(width: 8),
                    ],
                    Text(report.ageLabel, style: D.caption),
                    const SizedBox(width: 3),
                    const Icon(Icons.schedule, size: 11, color: D.textSoft),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(width: 10),
          Container(
            width: 44, height: 44,
            decoration: BoxDecoration(
              color: look.color.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(look.icon, color: look.color, size: 22),
          ),
        ],
      ),
    );
  }
}

class _EmptyFeed extends StatelessWidget {
  final bool backendUp;
  const _EmptyFeed({required this.backendUp});

  @override
  Widget build(BuildContext context) => DCard(
        color: D.cardInner,
        shadow: const [],
        radius: D.rInner,
        padding: const EdgeInsets.symmetric(vertical: 26, horizontal: 16),
        child: Column(
          children: [
            DIconCircle(
                backendUp ? Icons.check_circle_outline : Icons.cloud_off,
                size: 46,
                foreground: backendUp ? D.green : D.textSoft),
            const SizedBox(height: 10),
            Text(
              backendUp
                  ? 'ما في بلاغات حولك الآن — الطريق سالك.\nكن أول من '
                      'يبلّغ إذا شفت شي.'
                  : 'ما نقدر نجيب البلاغات بلا اتصال بالسيرفر.\nالخريطة '
                      'والملاحة يشتغلون على كل حال.',
              textAlign: TextAlign.center,
              style: D.bodySoft,
            ),
          ],
        ),
      );
}

class _Offline extends StatelessWidget {
  final String? message;
  const _Offline({this.message});

  @override
  Widget build(BuildContext context) => DCard(
        color: const Color(0xFFFFF6E2),
        shadow: const [],
        radius: D.rInner,
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Expanded(
              child: Text(
                message ??
                    'ما قدرنا نجيب أنواع البلاغات من السيرفر. الإبلاغ '
                        'يحتاج اتصالاً.',
                textAlign: TextAlign.right,
                style: const TextStyle(
                    color: Color(0xFF7A5A14), height: 1.4, fontSize: 13),
              ),
            ),
            const SizedBox(width: 10),
            const Icon(Icons.cloud_off, color: Color(0xFF8A6418)),
          ],
        ),
      );
}
