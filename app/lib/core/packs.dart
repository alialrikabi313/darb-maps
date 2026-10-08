// حِزَم المناطق: البلاطات وقاعدة البحث لكل منطقة.
//
// حزمة بغداد مشحونة مع التطبيق ليشتغل من أول تشغيل بلا شبكة. الحِزَم
// الأخرى تُنزَّل من شاشة الأوفلاين.
//
// ليش ننسخ الأصول لملفات: sqflite ما يفتح ملفاً داخل حزمة الـAPK (مضغوط
// وما له مسار في نظام الملفات)، ولا MapLibre يقرأه. النسخة مرة واحدة.

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

Directory? _root;

Future<Directory> packsDir() async {
  if (_root != null) return _root!;
  final base = await getApplicationSupportDirectory();
  // getApplicationSupportDirectory لا getTemporaryDirectory: النظام يمسح
  // المؤقّت تحت ضغط التخزين، وفقدان خريطة 500MB أثناء رحلة أسوأ خطأ ممكن
  _root = Directory('${base.path}/packs')..createSync(recursive: true);
  return _root!;
}

/// يهيّئ حزمة بغداد المشحونة: ينسخها من الأصول إن لم تكن منسوخة.
Future<Pack> ensureBundledPack() async {
  final dir = await packsDir();
  final tiles = File('${dir.path}/${Cfg.bundledPack}.mbtiles');
  final pois = File('${dir.path}/${Cfg.bundledPack}.pois.sqlite');

  await _copyAssetIfMissing(Cfg.bundledTilesAsset, tiles);
  await _copyAssetIfMissing(Cfg.bundledPoiAsset, pois);

  return Pack(name: Cfg.bundledPack, tiles: tiles, pois: pois);
}

Future<void> _copyAssetIfMissing(String asset, File dest) async {
  // نقارن الحجم لا مجرد الوجود: تحديث التطبيق بحزمة أحدث يخلّي النسخة
  // القديمة في مكانها، فتبقى الخريطة قديمة بلا أي علامة
  final data = await rootBundle.load(asset);
  if (dest.existsSync() && dest.lengthSync() == data.lengthInBytes) return;

  await dest.writeAsBytes(
    data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
    flush: true,
  );
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
