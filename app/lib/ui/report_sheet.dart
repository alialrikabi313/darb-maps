// ورقة الإبلاغ الكاملة: اختيار النوع وملاحظة اختيارية.
//
// الإبلاغ السريع أثناء الملاحة شبكة لمسة واحدة في nav_overlay. هذي
// للحالة التي يكون فيها المستخدم واقفاً ويبي يكتب تفصيلاً.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../reports/reports.dart';
import '../state/app_state.dart';
import 'nav_overlay.dart' show ReportTypeTile, showDarbSnack;
import 'theme.dart';

class ReportSheet extends StatefulWidget {
  const ReportSheet({super.key});

  @override
  State<ReportSheet> createState() => _ReportSheetState();
}

class _ReportSheetState extends State<ReportSheet> {
  String? _kind;
  final _note = TextEditingController();
  bool _sending = false;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final app = context.read<AppState>();
    final kind = _kind;
    if (kind == null) return;

    setState(() => _sending = true);
    final err = await app.sendReport(kind, note: _note.text.trim());
    if (!mounted) return;

    setState(() => _sending = false);
    Navigator.of(context).pop();
    showDarbSnack(context, err ?? 'شكراً — وصل بلاغك وصار يشوفه غيرك',
        isError: err != null);
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final types = app.reports.types;

    return Padding(
      // الإزاحة بارتفاع لوحة المفاتيح: بلاها تغطّي حقل الملاحظة
      padding:
          EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        decoration: const BoxDecoration(
          color: D.card,
          borderRadius: BorderRadius.vertical(top: Radius.circular(D.rSheet)),
        ),
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 26),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const DGrabber(),
              const DSectionHeader(
                title: 'الإبلاغ عن حادث أو حالة',
                subtitle: 'موقعك يُرسَل مع البلاغ، وبلا هويتك',
                icon: Icons.campaign_rounded,
              ),
              const SizedBox(height: 16),

              if (types.isEmpty)
                DCard(
                  color: D.noticeBg,
                  shadow: const [],
                  radius: D.rInner,
                  padding: const EdgeInsets.all(14),
                  child: Text(
                    app.reports.lastError ??
                        'ما قدرنا نجيب أنواع البلاغات من السيرفر',
                    textAlign: TextAlign.right,
                    style: const TextStyle(
                        color: D.noticeInk, height: 1.4, fontSize: 13),
                  ),
                )
              else
                GridView.count(
                  shrinkWrap: true,
                  crossAxisCount: 4,
                  mainAxisSpacing: 10,
                  crossAxisSpacing: 10,
                  childAspectRatio: 0.84,
                  physics: const NeverScrollableScrollPhysics(),
                  children: [
                    for (final t in types)
                      ReportTypeTile(
                        type: t,
                        selected: _kind == t.kind,
                        onTap: () => setState(() => _kind = t.kind),
                      ),
                  ],
                ),

              if (_kind != null) ...[
                const SizedBox(height: 16),
                DCard(
                  color: D.cardInner,
                  shadow: const [],
                  radius: D.rInner,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 4),
                  child: TextField(
                    controller: _note,
                    maxLength: 280,
                    maxLines: 2,
                    textAlign: TextAlign.right,
                    style: D.body,
                    decoration: const InputDecoration(
                      hintText: 'ملاحظة اختيارية — مثلاً: على المسار الأيمن',
                      hintStyle: TextStyle(color: D.textSoft, fontSize: 13),
                      border: InputBorder.none,
                      counterText: '',
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                _TtlNote(type: types.firstWhere((t) => t.kind == _kind)),
                const SizedBox(height: 14),
                DBigButton(
                  label: _sending ? 'نرسل…' : 'أرسل البلاغ',
                  icon: _sending ? null : Icons.send,
                  onTap: _sending ? null : _send,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// يقول للمستخدم كم يعيش بلاغه وكم صوتاً يحتاج.
///
/// ليش نعرضها: من يعرف أن بلاغ الرادار يعيش أسبوعاً وبلاغ الزحام 45
/// دقيقة يبلّغ بدقة أكثر، ويفهم ليش اختفى بلاغه.
class _TtlNote extends StatelessWidget {
  final ReportType type;
  const _TtlNote({required this.type});

  @override
  Widget build(BuildContext context) {
    final ttl = type.ttlMin;
    final life = ttl >= 1440
        ? '${(ttl / 1440).round()} يوم'
        : ttl >= 60
            ? '${(ttl / 60).round()} ساعة'
            : '$ttl دقيقة';

    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        Flexible(
          child: Text(
            'يعيش $life، ويصير «مؤكّداً» بعد ${type.votesToConfirm} '
            'تأكيدات من سائقين غيرك',
            textAlign: TextAlign.right,
            style: D.caption,
          ),
        ),
        const SizedBox(width: 5),
        const Icon(Icons.schedule, size: 13, color: D.textSoft),
      ],
    );
  }
}
