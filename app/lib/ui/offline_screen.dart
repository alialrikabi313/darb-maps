// الخرائط الأوفلاين: الحِزَم المثبّتة وحجمها وتغطيتها.
//
// حزمة العراق مشحونة مع التطبيق فتظهر دائماً ولا تُحذف — حذفها يترك
// التطبيق بلا خريطة وما عنده من وين يرجّعها.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../config.dart';
import '../core/packs.dart';
import '../state/app_state.dart';
import 'theme.dart';

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
    final pad = MediaQuery.of(context).padding;

    return Scaffold(
      backgroundColor: D.bg,
      body: Column(
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(14, pad.top + 10, 14, 10),
            child: Row(
              children: [
                DMapButton(
                  icon: Icons.arrow_forward,
                  tooltip: 'رجوع',
                  onTap: () => Navigator.of(context).pop(),
                  size: 44,
                ),
                const Spacer(),
                const Text('خرائط أوفلاين', style: D.h2),
                const SizedBox(width: 10),
                const DIconCircle(Icons.download_done_rounded,
                    size: 40, foreground: D.greenDeep),
              ],
            ),
          ),

          Expanded(
            child: _loading
                ? const Center(
                    child: CircularProgressIndicator(color: D.green))
                : ListView(
                    padding: const EdgeInsets.fromLTRB(14, 4, 14, 28),
                    children: [
                      DCard(
                        color: D.mintPale,
                        shadow: const [],
                        padding: const EdgeInsets.all(16),
                        child: Row(
                          children: [
                            const Expanded(
                              child: Text(
                                'الخريطة والبحث يشتغلون بلا إنترنت.\n'
                                'التوجيه والبلاغات والزحام يحتاجون اتصالاً.',
                                textAlign: TextAlign.right,
                                style: D.bodySoft,
                              ),
                            ),
                            const SizedBox(width: 12),
                            const DIconCircle(Icons.offline_bolt,
                                size: 46,
                                background: D.mint,
                                foreground: D.greenDeep),
                          ],
                        ),
                      ),

                      const SizedBox(height: 20),
                      const DSectionHeader(
                          title: 'المثبّت على الجهاز',
                          icon: Icons.sd_storage_outlined),
                      const SizedBox(height: 10),

                      for (final p in _packs) ...[
                        _PackRow(
                          pack: p,
                          label: _packLabel(p.name),
                          bundled: p.name == Cfg.bundledPack,
                          onDelete: () => _confirmDelete(p),
                        ),
                        const SizedBox(height: 8),
                      ],

                      const SizedBox(height: 8),
                      DCard(
                        color: D.cardInner,
                        shadow: const [],
                        radius: D.rInner,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 14),
                        child: Row(
                          children: [
                            Text(_human(_totalBytes), style: D.num2),
                            const Spacer(),
                            const Text('المساحة المستخدمة', style: D.h3),
                            const SizedBox(width: 10),
                            const DIconCircle(Icons.storage,
                                size: 38, foreground: D.greenDeep),
                          ],
                        ),
                      ),

                      if (_meta.isNotEmpty) ...[
                        const SizedBox(height: 20),
                        const DSectionHeader(
                            title: 'تفاصيل الحزمة',
                            icon: Icons.info_outline),
                        const SizedBox(height: 10),
                        DCard(
                          color: D.cardInner,
                          shadow: const [],
                          radius: D.rInner,
                          child: Column(
                            children: [
                              _MetaRow('المخطّط', _meta['name'] ?? '؟'),
                              _MetaRow('أعلى زوم', _meta['maxzoom'] ?? '؟'),
                              _MetaRow('بُنيت', _buildTime()),
                              if (_coverage != null)
                                _MetaRow(
                                  'التغطية الفعلية',
                                  '${_coverage![1].toStringAsFixed(1)}° – '
                                      '${_coverage![3].toStringAsFixed(1)}° '
                                      'عرضاً',
                                ),
                            ],
                          ),
                        ),
                      ],

                      const SizedBox(height: 20),
                      const DSectionHeader(
                          title: 'مناطق أخرى',
                          icon: Icons.public),
                      const SizedBox(height: 8),
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 4),
                        child: Text(
                          'العراق كامل مشحون مع التطبيق — ما تحتاج تنزيل '
                          'شي. تنزيل مناطق خارج العراق يحتاج استضافة '
                          'للحِزَم، وهي ما نُصبت بعد.',
                          textAlign: TextAlign.right,
                          style: D.bodySoft,
                        ),
                      ),
                    ],
                  ),
          ),
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

  static String _packLabel(String name) => switch (name) {
        'iraq' => 'العراق',
        'baghdad' => 'بغداد',
        _ => name,
      };

  Future<void> _confirmDelete(Pack p) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: D.card,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(D.rCard)),
        title: Text('احذف حزمة ${_packLabel(p.name)}؟', style: D.h2),
        content: const Text(
            'راح تختفي الخريطة والبحث في هذي المنطقة حتى تنزّلها من جديد.',
            style: D.bodySoft),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('إلغاء',
                  style: TextStyle(color: D.textSoft))),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              style: FilledButton.styleFrom(backgroundColor: D.danger),
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

class _PackRow extends StatelessWidget {
  final Pack pack;
  final String label;
  final bool bundled;
  final VoidCallback onDelete;

  const _PackRow({
    required this.pack,
    required this.label,
    required this.bundled,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final tiles = pack.tiles.existsSync() ? pack.tiles.lengthSync() : 0;
    final pois = pack.pois.existsSync() ? pack.pois.lengthSync() : 0;

    return DCard(
      color: D.cardInner,
      shadow: const [],
      radius: D.rInner,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      child: Row(
        children: [
          if (bundled)
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: D.mint,
                borderRadius: BorderRadius.circular(D.rPill),
              ),
              child: Text('مشحونة',
                  style: D.caption.copyWith(
                      color: D.greenDeep, fontWeight: FontWeight.w700)),
            )
          else
            IconButton(
              icon: const Icon(Icons.delete_outline, color: D.danger),
              onPressed: onDelete,
              tooltip: 'احذف',
            ),
          const Spacer(),
          Expanded(
            flex: 5,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(label, style: D.h3),
                Text(
                  'خريطة ${_OfflineScreenState._human(tiles)} · '
                  'بحث ${_OfflineScreenState._human(pois)}',
                  style: D.caption,
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          const DIconCircle(Icons.map, size: 40, foreground: D.greenDeep),
        ],
      ),
    );
  }
}

class _MetaRow extends StatelessWidget {
  final String label;
  final String value;
  const _MetaRow(this.label, this.value);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 7),
        child: Row(
          children: [
            Text(value, style: D.body.copyWith(fontWeight: FontWeight.w600)),
            const Spacer(),
            Text(label, style: D.bodySoft),
          ],
        ),
      );
}
