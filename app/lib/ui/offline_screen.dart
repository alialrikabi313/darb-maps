// الخرائط الأوفلاين: الحِزَم المثبّتة وحجمها.
//
// حزمة بغداد مشحونة مع التطبيق فتظهر دائماً ولا تُحذف. المحافظات الأخرى
// تُنزَّل — والتنزيل يحتاج استضافة للحِزَم، وهي ما لم تُنصَب بعد. نعرض
// الحالة صريحة بدل زرّ يضغطه المستخدم ولا يصير شي.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../config.dart';
import '../core/packs.dart';
import '../state/app_state.dart';

class OfflineScreen extends StatefulWidget {
  const OfflineScreen({super.key});

  @override
  State<OfflineScreen> createState() => _OfflineScreenState();
}

class _OfflineScreenState extends State<OfflineScreen> {
  List<Pack> _packs = const [];
  int _totalBytes = 0;
  Map<String, String> _meta = const {};
  List<double>? _coverage;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final app = context.read<AppState>();
    final packs = await installedPacks();
    final size = await packsSizeBytes();
    final meta = await app.tileServer.packMetadata(Cfg.bundledPack);
    final cov = await app.tileServer.packCoverage(Cfg.bundledPack);

    if (!mounted) return;
    setState(() {
      _packs = packs;
      _totalBytes = size;
      _meta = meta;
      _coverage = cov;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('خرائط أوفلاين')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              children: [
                Container(
                  margin: const EdgeInsets.all(14),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE8F5EE),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.offline_bolt,
                          color: Color(0xFF2BB673), size: 28),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'الخريطة والبحث يشتغلون بلا إنترنت. التوجيه '
                          'والبلاغات والزحام يحتاجون اتصالاً.',
                          style: const TextStyle(height: 1.4),
                        ),
                      ),
                    ],
                  ),
                ),

                const _Header('المثبّت على الجهاز'),
                for (final p in _packs)
                  ListTile(
                    leading: const Icon(Icons.map, color: Color(0xFF2D7FF9)),
                    title: Text(_packLabel(p.name)),
                    subtitle: Text(_packSubtitle(p)),
                    trailing: p.name == Cfg.bundledPack
                        // المشحونة ما تُحذف: حذفها يترك التطبيق بلا
                        // خريطة وما عنده من وين يرجّعها
                        ? const Chip(label: Text('مشحونة',
                            style: TextStyle(fontSize: 11)))
                        : IconButton(
                            icon: const Icon(Icons.delete_outline),
                            onPressed: () => _confirmDelete(p),
                          ),
                  ),

                ListTile(
                  leading: const Icon(Icons.storage),
                  title: const Text('المساحة المستخدمة'),
                  trailing: Text(_human(_totalBytes),
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                ),

                const _Header('محافظات أخرى'),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                  child: Text(
                    'تنزيل المحافظات يحتاج استضافة للحِزَم، وهي ما '
                    'نُصبت بعد.\n\nكل حزمة محافظة ≈ 10–40MB للخريطة '
                    'و3–8MB للبحث. العراق كامل ≈ 300MB، ولهذا نُنزّله '
                    'محافظةً محافظة لا دفعة واحدة.',
                    style: const TextStyle(
                        color: Color(0xFF6B7280), height: 1.5),
                  ),
                ),

                if (_meta.isNotEmpty) ...[
                  const _Header('تفاصيل حزمة بغداد'),
                  _MetaRow('المخطّط', _meta['name'] ?? '؟'),
                  _MetaRow('أعلى زوم', _meta['maxzoom'] ?? '؟'),
                  _MetaRow('بُنيت', _buildTime()),
                  if (_coverage != null)
                    _MetaRow(
                      'التغطية الفعلية',
                      '${_coverage![1].toStringAsFixed(2)}° – '
                          '${_coverage![3].toStringAsFixed(2)}° عرضاً',
                    ),
                ],
              ],
            ),
    );
  }

  String _buildTime() {
    final raw = _meta['planetiler:buildtime'];
    if (raw == null) return '؟';
    final dt = DateTime.tryParse(raw);
    if (dt == null) return raw;
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-'
        '${dt.day.toString().padLeft(2, '0')}';
  }

  String _packLabel(String name) =>
      name == 'baghdad' ? 'بغداد' : name == 'iraq' ? 'العراق' : name;

  String _packSubtitle(Pack p) {
    final tiles = p.tiles.existsSync() ? p.tiles.lengthSync() : 0;
    final pois = p.pois.existsSync() ? p.pois.lengthSync() : 0;
    return 'خريطة ${_human(tiles)} · بحث ${_human(pois)}';
  }

  Future<void> _confirmDelete(Pack p) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('احذف حزمة ${_packLabel(p.name)}؟'),
        content: const Text(
            'راح تختفي الخريطة والبحث في هذي المنطقة حتى تنزّلها من جديد.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('إلغاء')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('احذف')),
        ],
      ),
    );

    if (ok != true) return;
    await deletePack(p.name);
    await _load();
  }

  static String _human(int bytes) {
    if (bytes < 1024) return '$bytes ب';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).round()} كب';
    return '${(bytes / 1024 / 1024).toStringAsFixed(1)} مب';
  }
}

class _Header extends StatelessWidget {
  final String text;
  const _Header(this.text);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(right: 16, left: 16, top: 16, bottom: 4),
        child: Text(text,
            style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: Color(0xFF2D7FF9))),
      );
}

class _MetaRow extends StatelessWidget {
  final String label;
  final String value;
  const _MetaRow(this.label, this.value);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        child: Row(
          children: [
            Text(label, style: const TextStyle(color: Color(0xFF6B7280))),
            const Spacer(),
            Text(value),
          ],
        ),
      );
}
