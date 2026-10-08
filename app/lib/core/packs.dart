// حِزَم المناطق: البلاطات وقاعدة البحث لكل منطقة.
//
// الحزمة تُشحن مع التطبيق ليشتغل من أول تشغيل بلا شبكة.
//
// ليش ننسخ الأصول لملفات: sqflite ما يفتح ملفاً داخل حزمة الـAPK (مضغوط
// وما له مسار في نظام الملفات)، ولا MapLibre يقرأه.
//
// وليش القطع: `rootBundle.load` تحمّل الأصل كاملاً في الذاكرة قبل
// الكتابة. مرّت بحزمة بغداد (10MB)، لكن حزمة العراق 178MB تعني انهياراً
// بنفاد الذاكرة على أكثر الهواتف المتوسطة. فنلصق قطعة قطعة، ويبقى أعلى
// استهلاك حجم قطعة واحدة (16MB). التقطيع في tools/07_pack_assets.py.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import '../config.dart';

class Pack {
  final String name;
  final File tiles;
  final File pois;

  const Pack({required this.name, required this.tiles, required this.pois});

  bool get isReady => tiles.existsSync() && pois.existsSync();
}

/// ملف داخل الحزمة كما يصفه المنفست.
class _PackFile {
  final String name;
  final int size;
  final int chunks;
  final String sha256;

  _PackFile.fromJson(Map<String, dynamic> j)
      : name = j['name'] as String,
        size = (j['size'] as num).toInt(),
        chunks = (j['chunks'] as num).toInt(),
        sha256 = j['sha256'] as String;
}

/// تقدّم التهيئة. نعرضه لأن لصق 203MB يأخذ عشرات الثواني على تخزين
/// بطيء، وشاشة ساكنة بلا رقم تبدو كتطبيق معلّق.
class PackProgress {
  final String label;
  final double fraction; // 0..1
  const PackProgress(this.label, this.fraction);
}

Directory? _root;

Future<Directory> packsDir() async {
  if (_root != null) return _root!;
  final base = await getApplicationSupportDirectory();
  // getApplicationSupportDirectory لا getTemporaryDirectory: النظام يمسح
  // المؤقّت تحت ضغط التخزين، وفقدان خريطة 200MB أثناء رحلة أسوأ خطأ ممكن
  _root = Directory('${base.path}/packs')..createSync(recursive: true);
  return _root!;
}

/// يهيّئ الحزمة المشحونة: يلصق قطعها من الأصول إن لم تكن ملصوقة.
Future<Pack> ensureBundledPack(
    {void Function(PackProgress)? onProgress}) async {
  final dir = await packsDir();

  final manifest = jsonDecode(
      await rootBundle.loadString(Cfg.packManifestAsset)) as Map<String, dynamic>;

  final pack = manifest['pack'] as String;
  final files = (manifest['files'] as List)
      .map((e) => _PackFile.fromJson(e as Map<String, dynamic>))
      .toList();

  final totalBytes = files.fold<int>(0, (a, f) => a + f.size);
  var doneBytes = 0;

  for (final f in files) {
    final dest = File('${dir.path}/${f.name}');

    if (dest.existsSync() && dest.lengthSync() == f.size) {
      doneBytes += f.size;
      onProgress?.call(PackProgress('الخريطة جاهزة', doneBytes / totalBytes));
      continue;
    }

    await _assemble(f, dest, onChunk: (written) {
      onProgress?.call(PackProgress(
        _labelFor(f.name),
        (doneBytes + written) / totalBytes,
      ));
    });

    doneBytes += f.size;
  }

  return Pack(
    name: pack,
    tiles: File('${dir.path}/$pack.mbtiles'),
    pois: File('${dir.path}/$pack.pois.sqlite'),
  );
}

String _labelFor(String fileName) =>
    fileName.endsWith('.mbtiles') ? 'نجهّز الخريطة' : 'نجهّز البحث';

/// يلصق قطع ملف من الأصول إلى ملف واحد على القرص.
///
/// نكتب لملف مؤقّت ثم نعيد تسميته: انقطاع التهيئة (قتل التطبيق، نفاد
/// تخزين) يترك ملفاً ناقصاً باسمه النهائي، فيفتحه sqflite في التشغيل
/// القادم ويرمي «database disk image is malformed» — خطأ يصعب ربطه بسببه.
Future<void> _assemble(_PackFile f, File dest,
    {required void Function(int written) onChunk}) async {
  final tmp = File('${dest.path}.part');
  if (tmp.existsSync()) tmp.deleteSync();

  final sink = tmp.openWrite();
  var written = 0;

  try {
    for (var i = 0; i < f.chunks; i++) {
      final asset = 'assets/data/${f.name}.part${i.toString().padLeft(3, '0')}';
      final data = await rootBundle.load(asset);
      final bytes = data.buffer
          .asUint8List(data.offsetInBytes, data.lengthInBytes);

      sink.add(bytes);
      written += bytes.length;
      onChunk(written);
    }
  } finally {
    await sink.close();
  }

  // نتحقق بالحجم لا بالهاش: الحجم يمسك البتر وهو الفشل الواقعي (تخزين
  // ممتلئ، قطعة مفقودة من الأصول). والترتيب مضمون لأننا نلصق بفهرس
  // تصاعدي لا بقراءة مجلد. الهاش في المنفست لمسار التنزيل لاحقاً
  if (written != f.size) {
    tmp.deleteSync();
    throw StateError(
      'حزمة «${f.name}» ما لصقت كاملة ($written بايت من ${f.size}) — '
      'يحتمل أن التخزين امتلأ أو أن قطعة من الأصول ناقصة.',
    );
  }

  await tmp.rename(dest.path);
}

/// الحِزَم الموجودة على الجهاز.
Future<List<Pack>> installedPacks() async {
  final dir = await packsDir();
  final out = <Pack>[];

  for (final f in dir.listSync()) {
    if (f is! File || !f.path.endsWith('.mbtiles')) continue;
    final name = f.uri.pathSegments.last.replaceAll('.mbtiles', '');
    out.add(Pack(
      name: name,
      tiles: f,
      pois: File('${dir.path}/$name.pois.sqlite'),
    ));
  }
  return out;
}

Future<int> packsSizeBytes() async {
  final dir = await packsDir();
  var total = 0;
  for (final f in dir.listSync(recursive: true)) {
    if (f is File) total += f.lengthSync();
  }
  return total;
}

Future<void> deletePack(String name) async {
  final dir = await packsDir();
  for (final suffix in ['.mbtiles', '.pois.sqlite']) {
    final f = File('${dir.path}/$name$suffix');
    if (f.existsSync()) f.deleteSync();
  }
}
