// شاشة الإبلاغ الكاملة من وضع الاستكشاف: اختيار النوع وملاحظة اختيارية.
//
// الإبلاغ السريع أثناء الملاحة شبكة لمسة واحدة في nav_overlay — هذي
// للحالة التي يكون فيها المستخدم واقفاً ويبي يكتب تفصيلاً.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../reports/reports.dart';
import '../state/app_state.dart';

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
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(err ?? 'شكراً — وصل بلاغك وصار يشوفه غيرك'),
      backgroundColor:
          err == null ? const Color(0xFF2BB673) : const Color(0xFFD6333F),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final types = app.reports.types;

    return Padding(
      // الإزاحة بارتفاع لوحة المفاتيح: بلاها تغطّي حقل الملاحظة
      padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 44, height: 4,
                  decoration: BoxDecoration(
                    color: const Color(0xFFD1D5DB),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              const Text('أبلِغ عن شي على الطريق',
                  style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              Text(
                'بلاغك يصل للسائقين اللي وراك. موقعك يُرسَل مع البلاغ، '
                'وبلا هويتك.',
                style: const TextStyle(
                    fontSize: 12, color: Color(0xFF6B7280), height: 1.4),
              ),
              const SizedBox(height: 16),

              if (types.isEmpty)
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFEF3C7),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    app.reports.lastError ??
                        'ما قدرنا نجيب أنواع البلاغات من السيرفر',
                    style: const TextStyle(color: Color(0xFF78350F)),
                  ),
                )
              else
                GridView.count(
                  shrinkWrap: true,
                  crossAxisCount: 4,
                  mainAxisSpacing: 10,
                  crossAxisSpacing: 10,
                  childAspectRatio: 0.82,
                  physics: const NeverScrollableScrollPhysics(),
                  children: [
                    for (final t in types)
                      _TypeTile(
                        type: t,
                        selected: _kind == t.kind,
                        onTap: () => setState(() => _kind = t.kind),
                      ),
                  ],
                ),

              if (_kind != null) ...[
                const SizedBox(height: 14),
                TextField(
                  controller: _note,
                  maxLength: 280,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: 'ملاحظة (اختيارية)',
                    hintText: 'مثلاً: الحادث على المسار الأيمن',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                _TtlNote(type: types.firstWhere((t) => t.kind == _kind)),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: _sending ? null : _send,
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 15),
                      backgroundColor: const Color(0xFFF2A33C),
                    ),
                    child: _sending
                        ? const SizedBox(
                            width: 20, height: 20,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white))
                        : const Text('أرسل البلاغ',
                            style: TextStyle(
                                fontSize: 17, fontWeight: FontWeight.bold)),
                  ),
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
/// ليش نعرضها: المستخدم اللي يعرف أن بلاغ الرادار يعيش أسبوعاً وبلاغ
/// الزحام 45 دقيقة يبلّغ بدقة أكثر، ويفهم ليش اختفى بلاغه.
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
      children: [
        const Icon(Icons.schedule, size: 14, color: Color(0xFF6B7280)),
        const SizedBox(width: 5),
        Expanded(
          child: Text(
            'يعيش $life، ويصير «مؤكّداً» بعد ${type.votesToConfirm} '
            'تأكيدات من سائقين غيرك',
            style: const TextStyle(fontSize: 11, color: Color(0xFF6B7280)),
          ),
        ),
      ],
    );
  }
}

class _TypeTile extends StatelessWidget {
  final ReportType type;
  final bool selected;
  final VoidCallback onTap;

  const _TypeTile({
    required this.type,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final look = type.look;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: look.color,
              shape: BoxShape.circle,
              border: selected
                  ? Border.all(color: const Color(0xFF111827), width: 3)
                  : null,
            ),
            child: Icon(look.icon, color: Colors.white, size: 26),
          ),
          const SizedBox(height: 6),
          Text(type.label,
              textAlign: TextAlign.center,
              maxLines: 2,
              style: TextStyle(
                fontSize: 11,
                height: 1.15,
                fontWeight: selected ? FontWeight.bold : FontWeight.normal,
              )),
        ],
      ),
    );
  }
}
