// البحث المحلي في نقاط الاهتمام.
//
// محلي لا Nominatim: التطبيق يشتغل أوفلاين، وحدّ استخدام Nominatim طلب
// واحد بالثانية — يعني لا نقدر نبحث أثناء الكتابة أصلاً.
//
// قواعد تطبيع العربية تُقرأ من جدول search_meta في نفس القاعدة لا تُكتب
// هنا. السبب: البحث لازم يطبّع بنفس الطريقة التي فُهرست بها، ونسخة ثانية
// من القواعد في Dart تفترق عن بايثون بعد أول تعديل فتضيع النتائج بلا أي
// رسالة خطأ.

import 'dart:convert';
import 'dart:math' as math;

import 'package:maplibre_gl/maplibre_gl.dart';
import 'package:sqflite/sqflite.dart';

import '../config.dart';
import 'geo.dart';
import 'packs.dart';

class Place {
  final int id;
  final String? nameAr;
  final String? nameEn;

  /// الاسم المطبّع كما فُهرس. نحتاجه لترجيح التطابق التام في الترتيب
  /// النهائي — إعادة تطبيعه في Dart تخاطر بأن يفترق عن المفهرس.
  final String? nameNorm;
  final String category;
  final String? subtype;
  final LatLng pos;
  final int rank;
  final Map<String, dynamic> tags;

  /// مصدر النقطة: `osm` أو `overture:…` أو `osm-address` أو
  /// `osm-inferred`. نعرضه في بطاقة المكان لأن CDLA-Permissive-2.0
  /// تشترط الإسناد، ولأن المستخدم يستحق يعرف من أين جاءت المعلومة حين
  /// تكون خاطئة — وهو أهمّ في المستنتَج.
  final String source;

  /// المسافة من المستخدم بالأمتار — تُحسب وقت البحث لا تُخزَّن.
  final double? distanceM;

  const Place({
    required this.id,
    required this.nameAr,
    required this.nameEn,
    this.nameNorm,
    required this.category,
    required this.subtype,
    required this.pos,
    required this.rank,
    required this.tags,
    this.source = 'osm',
    this.distanceM,
  });

  /// اسم المصدر مقروءاً للعرض.
  String get sourceLabel => switch (source) {
        final s when s.startsWith('overture') => 'Overture Maps',
        'osm-address' => 'من عناوين المباني',
        'osm-inferred' => 'اسم مستنتَج — قد يكون غير دقيق',
        _ => 'OpenStreetMap',
      };

  /// الاسم مستنتَج لا مكتوب صراحةً في الخريطة.
  ///
  /// الواجهة تعلّمه، والأهمّ أنه **لا يُنطق أبداً**: التوجيه الصوتي يأخذ
  /// أسماء الشوارع من ڤالهالا مباشرة ولا يمسّ قاعدة البحث. اسم مستنتَج
  /// خاطئ يظهر في نتيجة بحث يصحّحه المستخدم بنظرة، ولو نُطق في مناورة
  /// لأضلّه.
  bool get isInferred => source == 'osm-inferred';

  String get title => nameAr ?? nameEn ?? 'بلا اسم';
  String? get subtitle => nameAr != null && nameEn != null ? nameEn : null;

  /// نسخة بالاسم مقصوصاً — تُستعمل للمعالم المنطوقة فقط، فالبحث
  /// والخريطة يعرضان الاسم الكامل.
  Place renamed(String shortName) => Place(
        id: id, nameAr: shortName, nameEn: nameEn, nameNorm: nameNorm,
        category: category,
        subtype: subtype, pos: pos, rank: rank, tags: tags,
        source: source, distanceM: distanceM,
      );

  Place withDistance(double d) => Place(
        id: id, nameAr: nameAr, nameEn: nameEn, nameNorm: nameNorm,
        category: category,
        subtype: subtype, pos: pos, rank: rank, tags: tags,
        source: source, distanceM: d,
      );
}

/// تسميات عربية للتصنيفات — تُعرض تحت اسم النتيجة.
///
/// هذي نسخة احتياطية للعرض فقط. المصدر الحقيقي جدول `search_meta` في
/// نفس القاعدة (`PoiSearch.categoryLabels`)، لأن نفس التسميات تدخل
/// فهرس البحث في بايثون — ونسختان تفترقان بعد أول تعديل.
const Map<String, String> categoryLabels = {
  'place': 'منطقة',
  'street': 'شارع',
  'hospital': 'مستشفى',
  'pharmacy': 'صيدلية',
  'fuel': 'محطة وقود',
  'restaurant': 'مطعم',
  'mosque': 'جامع',
  'school': 'مدرسة',
  'university': 'جامعة',
  'bank': 'مصرف',
  'market': 'سوق',
  'government': 'دائرة حكومية',
  'transport': 'نقل',
  'hotel': 'فندق',
  'park': 'حديقة',
  'car_service': 'خدمة سيارات',
};

class PoiSearch {
  final List<Database> _dbs = [];

  // قواعد التطبيع كما خزّنها سكربت الاستخراج
  Map<String, String> _normMap = {};
  String _stripChars = '';
  RegExp? _stripRe;

  /// تسميات التصنيفات كما فُهرست في بايثون.
  Map<String, String> categoryLabelsFromDb = const {};

  // البادئات (ال، مستشفى، شارع…) ما نحتاجها وقت البحث: سكربت الاستخراج
  // فهرس الاسم كاملاً وكلماته منزوعة البادئة معاً، ومطابقة البادئة في
  // FTS تمسكها. نقرأها من القاعدة ولا نخزّنها — وجودها هناك توثيق لما
  // فُهرس به، لا مدخل لحساب هنا

  // كل ما ليس حرفاً عربياً أو لاتينياً أو رقماً هو فاصل: OSM يستخدم «-»
  // و«/» و«،» بلا اتساق في نفس المدينة.
  //
  // `\w` في Dart محصور بـASCII دائماً (يتبع ECMAScript، و`unicode: true`
  // لا يوسّعه)، بخلاف بايثون حيث يشمل اليونيكود. فكان «Şeqlawe Pîrmam»
  // يُفهرس كاملاً في بايثون ويتفتّت في الجهاز — والأسماء الكردية
  // والتركية المنقولة بلاتينية في شمال العراق كانت تعطي صفر نتائج.
  // نسمّي النطاقات اللاتينية الممتدة صراحةً
  static final _sepRe = RegExp(
      r'[^؀-ۿA-Za-z0-9_À-ɏḀ-ỿ]+',
      unicode: true);

  Future<void> open(List<Pack> packs) async {
    for (final p in packs) {
      if (!p.pois.existsSync()) continue;
      final db = await openDatabase(p.pois.path, readOnly: true);
      _dbs.add(db);
      if (_normMap.isEmpty) await _loadMeta(db);
    }
    if (_dbs.isEmpty) {
      throw StateError('ما في قاعدة نقاط اهتمام على الجهاز');
    }
  }

  Future<void> _loadMeta(Database db) async {
    final rows = await db.rawQuery('SELECT key, value FROM search_meta');
    final meta = {for (final r in rows) r['key'] as String: '${r['value']}'};

    _normMap = (jsonDecode(meta['normalize_map'] ?? '{}') as Map)
        .map((k, v) => MapEntry('$k', '$v'));
    _stripChars = meta['strip_chars'] ?? '';

    final labels = meta['category_labels'];
    if (labels != null) {
      categoryLabelsFromDb = (jsonDecode(labels) as Map)
          .map((k, v) => MapEntry('$k', '$v'));
    }

    if (_stripChars.isNotEmpty) {
      _stripRe = RegExp('[${RegExp.escape(_stripChars)}]');
    }
  }

  /// نفس تطبيع tools/arabic.py حرفاً بحرف — القواعد منه لا من هنا.
  String normalize(String text) {
    if (text.isEmpty) return '';
    var t = _stripRe == null ? text : text.replaceAll(_stripRe!, '');
    final sb = StringBuffer();
    for (final ch in t.split('')) {
      sb.write(_normMap[ch] ?? ch);
    }
    return sb.toString().replaceAll(_sepRe, ' ').trim().toLowerCase();
  }

  /// يبحث، ويرتّب بثلاث طبقات قبل الرتبة الثابتة.
  ///
  /// الاستعلام منقول من tools/04_extract_pois.py بعد ما ضبطناه هناك على
  /// بيانات بغداد — نسخة واحدة من المنطق في مكانين، مقابل أن البحث يشتغل
  /// أوفلاين. لو تغيّر هناك يتغيّر هنا.
  Future<List<Place>> search(String query, {LatLng? near}) async {
    final norm = normalize(query);
    final tokens = norm.split(' ').where((t) => t.isNotEmpty).toList();
    if (tokens.isEmpty || norm.length < Cfg.searchMinChars) return [];

    // FTS5 يعدّ المسافة AND ضمناً. النجمة بادئة لأن المستخدم يكتب وهو يبحث
    final andQuery = tokens.map((t) => '"$t"*').join(' ');
    final orQuery = tokens.map((t) => '"$t"*').join(' OR ');

    final out = <String, Place>{};

    for (final db in _dbs) {
      for (final q in [andQuery, if (tokens.length > 1) orQuery]) {
        if (out.length >= Cfg.searchLimit) break;
        final rows = await _run(db, q, norm, Cfg.searchLimit);
        for (final p in rows) {
          // المفتاح يشمل اسم الحزمة: معرّفات poi.id متسلسلة داخل كل
          // قاعدة بدءاً من 1، فحزمتان على الجهاز تتصادم معرّفاتهما
          // و`putIfAbsent` كان يُسقط نتيجة الثانية بصمت
          out.putIfAbsent('${db.path}#${p.id}', () => p);
        }
      }
    }

    var results = out.values.toList();

    if (near != null) {
      results = results
          .map((p) => p.withDistance(metersBetween(near, p.pos)))
          .toList();

      // الأقرب أولاً بين متقاربي الرتبة: «صيدلية الرحمة» التي على بعد
      // 300 متر أنفع من واحدة بنفس الاسم في الجهة الثانية من بغداد.
      // ما نرتّب بالمسافة وحدها: «بغداد» على بعد 5 كم تبقى أهم من زقاق
      // على بعد 100 متر
      // التطابق التام يتقدّم على القرب دائماً: من يكتب «جامعة بغداد»
      // كاملة يريدها هي، لا «عيادة جامعة بغداد» الأقرب إليه.
      // الفرز بالرتبة والمسافة وحدهما كان يلغي ترجيح التطابق الذي
      // بُني في SQL ويُفحص في tools/06
      results.sort((a, b) {
        final exactA = a.nameNorm == norm ? 1 : 0;
        final exactB = b.nameNorm == norm ? 1 : 0;
        if (exactA != exactB) return exactB - exactA;

        final prefixA = (a.nameNorm?.startsWith(norm) ?? false) ? 1 : 0;
        final prefixB = (b.nameNorm?.startsWith(norm) ?? false) ? 1 : 0;
        if (prefixA != prefixB) return prefixB - prefixA;

        final byRank = (b.rank ~/ 20).compareTo(a.rank ~/ 20);
        if (byRank != 0) return byRank;
        return (a.distanceM ?? 0).compareTo(b.distanceM ?? 0);
      });
    } else {
      results.sort((a, b) => b.rank.compareTo(a.rank));
    }

    return results.take(Cfg.searchLimit).toList();
  }

  Future<List<Place>> _run(
      Database db, String match, String norm, int limit) async {
    final rows = await db.rawQuery('''
      SELECT p.id, p.name_ar, p.name_en, p.name_norm, p.category, p.subtype,
             p.lat, p.lon, p.rank, p.tags, p.source
      FROM poi_fts f JOIN poi p ON p.id = f.rowid
      WHERE poi_fts MATCH ?
      ORDER BY
        (p.name_norm = ?) DESC,
        (p.name_norm LIKE ?) DESC,
        p.rank DESC,
        LENGTH(p.name_norm) ASC,
        bm25(poi_fts)
      LIMIT ?
    ''', [match, norm, '$norm%', limit]);

    return rows.map(_toPlace).toList();
  }

  /// نقاط اهتمام قريبة من نقطة، مفلترة بالتصنيف.
  ///
  /// تستخدمها شاشة «محطات وقود قريبة» وشاشة البحث قبل ما يكتب المستخدم
  /// شيئاً — الفهرس المكاني R*Tree يجيبها بلا مسح الجدول.
  Future<List<Place>> nearby(LatLng center,
      {required List<String> categories,
      double radiusM = 5000,
      int limit = 20}) async {
    // درجة عرض ≈ 111.32 كم. نحوّل نصف القطر لصندوق، ثم نفلتر بالمسافة
    // الحقيقية — الصندوق يجيب زواياه الأبعد من نصف القطر
    final dLat = radiusM / 111320.0;
    final dLon = dLat / math.cos(center.latitude * math.pi / 180.0);

    final placeholders = List.filled(categories.length, '?').join(',');
    final out = <Place>[];

    for (final db in _dbs) {
      final rows = await db.rawQuery('''
        SELECT p.id, p.name_ar, p.name_en, p.name_norm, p.category,
               p.subtype, p.lat, p.lon, p.rank, p.tags, p.source
        FROM poi_geo g JOIN poi p ON p.id = g.id
        WHERE g.min_lon >= ? AND g.max_lon <= ?
          AND g.min_lat >= ? AND g.max_lat <= ?
          AND p.category IN ($placeholders)
        LIMIT ?
      ''', [
        center.longitude - dLon, center.longitude + dLon,
        center.latitude - dLat, center.latitude + dLat,
        ...categories,
        limit * 4,
      ]);

      for (final r in rows) {
        final p = _toPlace(r);
        final d = metersBetween(center, p.pos);
        if (d <= radiusM) out.add(p.withDistance(d));
      }
    }

    out.sort((a, b) => (a.distanceM ?? 0).compareTo(b.distanceM ?? 0));
    return out.take(limit).toList();
  }

  /// كم يُعرَف هذا التصنيف من السيارة. المعلم المفيد في التوجيه هو ما
  /// يراه السائق بطرف عينه ويميّزه بلا تدقيق: محطة وقود، جامع، مستشفى.
  /// الصيدلية والمكتب قد لا يُرَيان من الشارع أصلاً.
  static const _landmarkWeight = <String, int>{
    'fuel': 100,
    'mosque': 95,
    'hospital': 90,
    'university': 85,
    'transport': 80,
    'market': 70,
    'park': 65,
    'government': 60,
    'school': 55,
    'bank': 45,
    'hotel': 40,
    'car_service': 35,
    'restaurant': 30,
    'pharmacy': 25,
  };

  /// أقصى طول لاسم المعلم حرفاً وكلمةً.
  ///
  /// الجملة المنطوقة «بعد 300 متر، انعطف يمين عند …» لازم تنتهي قبل ما
  /// يصل السائق التقاطع. قرأنا الجمل الفعلية على مسار الموصل فوجدنا
  /// «انعطف يمين عند شركة المسار العالميه للسفر والسياحة» — أطول من أن
  /// تُسمع، والاسم القصير بعدها أنفع من الطويل قبلها.
  static const _landmarkMaxChars = 34;
  static const _landmarkMaxWords = 5;

  /// حروف عربية — المعلم بلا اسم عربي لا يصلح معلماً صوتياً.
  static final _arabicRe = RegExp(r'[؀-ۿ]');

  /// فواصل نقطع عندها اسم المعلم.
  ///
  /// «مصرف الرشيد - فرع الفرات 515» يصير «مصرف الرشيد»: السائق يميّز
  /// المصرف من الشارع ولا يميّز رقم الفرع، والاسم الأقصر يُسمع قبل
  /// التقاطع. 1,852 معلماً إضافياً صار صالحاً بهذا القطع وحده.
  static final _landmarkCutRe =
      RegExp(r'\s[-–—/|]\s|\s*[(（]|\s*[،,]\s*');

  /// أسماء هي كلمة التصنيف وحدها — لا تصلح معلماً.
  ///
  /// شاهدنا «انعطف يمين قبل جامع» على مسار الموصل: نقطة في OSM اسمها
  /// «جامع» حرفياً. الدلالة بها أسوأ من لا دلالة، لأن السائق يبحث عن
  /// جامع بعينه وكلّ ما حوله جوامع.
  static const _genericNames = {
    'جامع', 'مسجد', 'حسينية', 'كنيسة', 'مرقد',
    'مدرسة', 'ثانوية', 'اعدادية', 'ابتدائية', 'روضة', 'جامعة', 'كلية',
    'مستشفى', 'عيادة', 'مستوصف', 'مختبر', 'صيدلية',
    'مطعم', 'مقهى', 'كافيه', 'سوق', 'مول', 'محل', 'محلات',
    'فندق', 'مصرف', 'بنك', 'صراف',
    'حديقة', 'متنزه', 'ملعب', 'محطة', 'كراج', 'مرآب', 'موقف',
    'بنزين', 'وقود', 'دائرة', 'مكتب', 'شركة', 'معرض',
  };

  static String _trimLandmark(String name) {
    final head = name.split(_landmarkCutRe).first.trim();
    // القطع الذي يفرّغ الاسم أو يمسح عربيته لا يُقبل
    if (head.isEmpty || !_arabicRe.hasMatch(head)) return name;
    return head;
  }

  /// أبرز معلم قرب نقطة، أو null إن لم يكن قريباً شيء يستحق الذكر.
  ///
  /// نحتاجه لأن 9% فقط من طرق العراق مسمّاة. قِسنا على ثمانية مسارات في
  /// ستّ مدن: التعليمات التي فيها اسم شارع 55%، وبإضافة المعالم 84%.
  /// فالمعلم ليس تحسيناً تجميلياً — هو ثلث التعليمات.
  ///
  /// محلي وفوري: القاعدة على الجهاز وفيها فهرس R*Tree.
  Future<Place?> landmarkNear(LatLng p, {double radiusM = 100}) async {
    final dLat = radiusM / 111320.0;
    final dLon = dLat / math.cos(p.latitude * math.pi / 180.0);

    Place? best;
    var bestScore = -1.0;

    for (final db in _dbs) {
      final rows = await db.rawQuery('''
        SELECT p.id, p.name_ar, p.name_en, p.name_norm, p.category, p.subtype,
               p.lat, p.lon, p.rank, p.tags, p.source
        FROM poi_geo g JOIN poi p ON p.id = g.id
        WHERE g.min_lon >= ? AND g.max_lon <= ?
          AND g.min_lat >= ? AND g.max_lat <= ?
          AND p.category != 'street'
        LIMIT 60
      ''', [
        p.longitude - dLon, p.longitude + dLon,
        p.latitude - dLat, p.latitude + dLat,
      ]);

      for (final r in rows) {
        final place = _toPlace(r);
        final weight = _landmarkWeight[place.category];
        // تصنيف ما نثق أن السائق يميّزه من السيارة لا يصير معلماً
        if (weight == null) continue;

        final raw = place.nameAr;
        // الاسم اللاتيني يُنطق مشوّهاً في جملة عربية. قرأنا
        // «انعطف يمين عند Rabia Kathun Mosque» على مسار الموصل —
        // محرّك النطق العربي يلفظها حروفاً مفكّكة
        if (raw == null || !_arabicRe.hasMatch(raw)) continue;

        final name = _trimLandmark(raw);
        if (name.length > _landmarkMaxChars) continue;

        final words = name.split(' ');
        if (words.length > _landmarkMaxWords) continue;
        // «جامع» وحدها ليست معلماً؛ «جامع العبادي» معلم
        if (words.length == 1 && _genericNames.contains(words.first)) continue;

        final d = metersBetween(p, place.pos);
        if (d > radiusM) continue;

        // ثلاثة عوامل: نوع المعلم، وبروزه، وقربه.
        // البروز (rank) يفرّق بين «مول بغداد» و«لمعة و اناقة» وكلاهما
        // عندنا تصنيفه market — والثاني ما يُرى من الشارع أصلاً
        final score = weight + place.rank * 0.5 - d * 0.35;
        if (score > bestScore) {
          bestScore = score;
          best = place.withDistance(d).renamed(name);
        }
      }
    }

    return best;
  }

  Place _toPlace(Map<String, Object?> r) => Place(
        id: r['id'] as int,
        nameAr: r['name_ar'] as String?,
        nameEn: r['name_en'] as String?,
        nameNorm: r['name_norm'] as String?,
        category: r['category'] as String,
        subtype: r['subtype'] as String?,
        pos: LatLng(r['lat'] as double, r['lon'] as double),
        rank: r['rank'] as int,
        tags: r['tags'] == null
            ? const {}
            : jsonDecode(r['tags'] as String) as Map<String, dynamic>,
        // الحزم القديمة بلا عمود source — نعدّها OSM بدل ما ننهار عليها
        source: (r['source'] as String?) ?? 'osm',
      );

  Future<void> close() async {
    for (final db in _dbs) {
      await db.close();
    }
    _dbs.clear();
  }
}
