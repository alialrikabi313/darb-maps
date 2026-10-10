# -*- coding: utf-8 -*-
"""المرحلة ٠٤: استخراج نقاط الاهتمام والأماكن والشوارع إلى SQLite للبحث.

يقرأ: darb-data/osm/{baghdad|iraq-latest}.osm.pbf
ينتج: darb-data/poi/pois.sqlite — يُحزَم مع التطبيق ويُبحَث محلياً

الخطوات:
  ١. تهيئة القاعدة: جدول poi + فهرس FTS5 + فهرس مكاني R*Tree
  ٢. مرور واحد على الـPBF يجمع العُقد والطرق والشوارع
  ٣. كتابة الصفوف دفعات، وتخزين قواعد التطبيع في القاعدة
  ٤. تجربة بحث على حالات صادفناها فعلاً

ليش بحث محلي لا Nominatim: التطبيق يشتغل أوفلاين، وحدّ استخدام Nominatim
طلب واحد بالثانية — يعني لا نقدر نبحث أثناء الكتابة أصلاً.

    python 04_extract_pois.py            # العيّنة
    python 04_extract_pois.py --full     # العراق كامل
"""

import re
import sys
import json
import math
import time
import sqlite3
import argparse

from config import (
    IRAQ_PBF, SAMPLE_PBF, POI_DB, POI_CATEGORIES, POI_REQUIRE_NAME,
    POI_DEDUP_RADIUS_M, POI_CATEGORY_LABELS, STREET_SAME_RADIUS_M,
    PLACE_VALUES, ARABIC_NORMALIZE_MAP, ARABIC_STRIP_CHARS,
    SEARCH_STOP_PREFIXES, ensure_dirs,
)
from arabic import normalize, fts_text

# وزن التصنيف في ترتيب النتائج. المستشفى أهم من مقهى حين يتطابق الاسمان،
# وحدود المدن والأحياء أهم من الاثنين لأنها الوجهة الأكثر طلباً
# قرارك: الأوزان مبدئية، تُعاير بعد ما نشاهد بحث مستخدمين حقيقيين
_CATEGORY_RANK = {
    "place": 100, "transport": 60, "hospital": 55, "university": 52,
    "government": 50, "fuel": 45, "market": 40, "school": 35, "mosque": 33,
    "bank": 30, "pharmacy": 28, "hotel": 25, "park": 20, "restaurant": 15,
    "street": 10,
}

# الأوسمة التي نحفظها مع النقطة. الباقي يُهمل: القاعدة تُحزَم مع التطبيق
# وكل وسم زائد يكبّر حجم التحميل بلا أن يُعرض في أي شاشة
_KEEP_TAGS = ("phone", "opening_hours", "website", "operator", "addr:street",
              "addr:city", "healthcare", "religion", "brand", "cuisine",
              # wikidata و wikimedia_commons: الطريق الوحيد لصورة مكان في
              # بياناتنا. OSM العراق ما فيه وسم image ولا صور أصلاً، وهذان
              # يصلان لصورة كومنز للمعالم المشهورة وحدها — عشرات لا آلاف.
              # نحفظهما وبطاقة المكان تعرض الصورة إن وُجدت وأيقونة إن غابت
              "wikidata", "wikimedia_commons", "image",
              # fee و capacity للمواقف: «موقف مجاني 200 سيارة» معلومة تغيّر
              # قرار السائق، بخلاف باقي الأوسمة التي نهملها
              "fee", "capacity")

_SCHEMA = """
PRAGMA journal_mode = WAL;

CREATE TABLE IF NOT EXISTS poi (
    id        INTEGER PRIMARY KEY,
    osm_type  TEXT NOT NULL,          -- n / w / r
    osm_id    INTEGER NOT NULL,
    category  TEXT NOT NULL,
    subtype   TEXT,                   -- قيمة الوسم الأصلية من OSM
    name_ar   TEXT,
    name_en   TEXT,
    -- الاسم المطبّع يُخزَّن عموداً لا يُحسَب وقت البحث: الاستعلام يرجّح
    -- التطابق التام عليه، ودالة تطبيع في WHERE تمنع أي فهرس
    name_norm TEXT,
    lat       REAL NOT NULL,
    lon       REAL NOT NULL,
    rank      INTEGER NOT NULL,
    tags      TEXT,                   -- JSON
    -- المصدر مع كل صفّ لا في سطر واحد: المراحل ٠٨ و٠٩ تضيف نقاطاً من
    -- Overture ومن عناوين المباني، والتطبيق يستعلم عن هذا العمود.
    -- كان يُضاف في ٠٨ فقط، فتشغيل ٠٤ وحده يكسر كل بحث في التطبيق
    -- بـ«no such column: p.source»
    source    TEXT NOT NULL DEFAULT 'osm'
);

CREATE UNIQUE INDEX IF NOT EXISTS poi_osm ON poi(osm_type, osm_id);
CREATE INDEX IF NOT EXISTS poi_cat ON poi(category);

-- البحث النصّي. المحتوى منفصل (content='') لأننا نخزّن النص المطبّع لا
-- الأصلي، والأصل موجود في جدول poi نفسه
CREATE VIRTUAL TABLE IF NOT EXISTS poi_fts USING fts5(
    terms,
    content=''
);

-- الفهرس المكاني: «نقاط الاهتمام حولي» و«محطات وقود على المسار»
CREATE VIRTUAL TABLE IF NOT EXISTS poi_geo USING rtree(
    id, min_lon, max_lon, min_lat, max_lat
);

-- قواعد التطبيع تُقرأ من هنا في التطبيق. السبب: بحث الجهاز لازم يطبّع
-- بنفس الطريقة التي فُهرست بها، ونسخ القواعد يدوياً في Dart يفترق عن
-- بايثون بعد أول تعديل وتضيع النتائج بلا أي رسالة خطأ
CREATE TABLE IF NOT EXISTS search_meta (
    key   TEXT PRIMARY KEY,
    value TEXT NOT NULL
);
"""

# صنف الشارع الذي يستحق الدخول في البحث. الأزقّة (service, track) خارج:
# أحد ما يبحث عن زقاق بالاسم، ودخولها يضاعف حجم القاعدة
_SEARCHABLE_HIGHWAYS = {
    "motorway", "trunk", "primary", "secondary", "tertiary", "residential",
    "living_street", "pedestrian", "motorway_link", "trunk_link",
}

# الشوارع المكرّرة: شارع واحد في OSM مقطّع عشرات القطع بنفس الاسم. نحفظ
# قطعة واحدة لكل اسم **في كل منطقة** ونهمل الباقي — المستخدم يبي يوصل
# الشارع لا قطعة بعينها منه.
#
# كان المفتاح الاسم وحده على كل العراق، فـ«شارع الجمهورية» في بغداد
# يمحو نظيره في البصرة والموصل. قِسناه: 27,538 اسماً كلها نسخة واحدة.
# الآن المفتاح (الاسم، الإحداثيات) ونقارن بالمسافة
_seen_streets: dict[str, list[tuple[float, float]]] = {}

# وسم التصنيف المعاكس: من (tag, value) إلى تصنيفنا، نبنيه مرة من config
_TAG_TO_CATEGORY: dict[tuple[str, str], str] = {}
for _cat, _pairs in POI_CATEGORIES.items():
    for _p in _pairs:
        _TAG_TO_CATEGORY[_p] = _cat


def init_db(path) -> sqlite3.Connection:
    path.unlink(missing_ok=True)
    for suffix in ("-wal", "-shm"):
        path.with_name(path.name + suffix).unlink(missing_ok=True)

    con = sqlite3.connect(path)
    con.executescript(_SCHEMA)

    meta = {
        "normalize_map": json.dumps(ARABIC_NORMALIZE_MAP, ensure_ascii=False),
        "strip_chars": ARABIC_STRIP_CHARS,
        "stop_prefixes": json.dumps(SEARCH_STOP_PREFIXES, ensure_ascii=False),
        "category_labels": json.dumps(POI_CATEGORY_LABELS,
                                      ensure_ascii=False),
        "built_at": time.strftime("%Y-%m-%d %H:%M:%S"),
    }
    con.executemany("INSERT OR REPLACE INTO search_meta VALUES (?,?)",
                    meta.items())
    con.commit()
    return con


def pick_names(tags) -> tuple[str | None, str | None]:
    """يرجّع (الاسم العربي، الاسم اللاتيني).

    OSM العراق فيه name عربي غالباً و name:en أحياناً، لكن بعض المعالم
    name لاتيني و name:ar عربي. فنفحص المحتوى لا المفتاح.
    """
    ar = tags.get("name:ar")
    en = tags.get("name:en")
    plain = tags.get("name")

    if plain and not ar and _has_arabic(plain):
        ar = plain
    elif plain and not en and not _has_arabic(plain):
        en = plain

    return ar, en


_ARABIC_RE = re.compile(r"[؀-ۿ]")


def _has_arabic(s: str) -> bool:
    return bool(_ARABIC_RE.search(s))


def classify(tags) -> tuple[str, str] | None:
    """يرجّع (تصنيفنا، قيمة OSM الأصلية) أو None إذا ما كانت نقطة اهتمام."""
    place = tags.get("place")
    if place in PLACE_VALUES:
        return "place", place

    for key in ("amenity", "shop", "tourism", "leisure", "office", "aeroway"):
        val = tags.get(key)
        if val and (key, val) in _TAG_TO_CATEGORY:
            return _TAG_TO_CATEGORY[(key, val)], val

    return None


def rank_of(category: str, subtype: str, tags) -> int:
    """ترتيب النتيجة. الأعلى يظهر أولاً."""
    r = _CATEGORY_RANK.get(category, 5)

    # المدينة قبل الحي قبل القرية — place=city وحده لا يميّز بغداد عن قرية
    if category == "place":
        r += {"city": 40, "town": 25, "suburb": 15, "quarter": 10,
              "neighbourhood": 8, "village": 5}.get(subtype, 0)

    # نقطة عندها اسم عربي ترتفع: المستخدم يبحث بالعربي، والنتيجة اللاتينية
    # وحدها تطابق أقل وتُقرأ أسوأ
    if tags.get("name:ar"):
        r += 5

    # نقطة موسومة بتفاصيل (هاتف، ساعات عمل) أرجح أن تكون معلماً حقيقياً
    # لا مجرد نقطة رماها أحدهم على الخريطة
    r += min(3, sum(1 for t in ("phone", "opening_hours", "website")
                    if t in tags))

    # الطرق الرئيسية قبل السكنية
    if category == "street":
        r += {"motorway": 12, "trunk": 10, "primary": 8, "secondary": 5,
              "tertiary": 3}.get(subtype, 0)

    return r


def keep_tags(tags) -> str | None:
    kept = {k: tags[k] for k in _KEEP_TAGS if k in tags}
    return json.dumps(kept, ensure_ascii=False) if kept else None


def way_center(way) -> tuple[float, float] | None:
    """مركز الطريق تقريباً: منتصف قائمة العُقد.

    حل مؤقت مقبول: للشوارع نبي نقطة على الشارع نفسه، والمنتصف يحقّقها.
    للمباني (مستشفى مرسوم مضلّعاً) المنتصف قد يقع خارج المضلّع لو كان
    مقعّراً — ما صادفنا هذا في بغداد، ولو صار نحسب centroid فعلياً.
    """
    locs = [(n.location.lon, n.location.lat) for n in way.nodes
            if n.location.valid()]
    if not locs:
        return None
    return locs[len(locs) // 2]


def _meters_between(lon1: float, lat1: float, lon2: float, lat2: float) -> float:
    """مسافة تقريبية. تكفي لإزالة التكرار على مسافات أقل من بضعة كيلومترات
    — ما نحتاج haversine كامل هنا وهو أبطأ ونُناديه ملايين المرات."""
    dlat = (lat2 - lat1) * 111_320.0
    dlon = (lon2 - lon1) * 111_320.0 * math.cos(math.radians((lat1 + lat2) / 2))
    return math.hypot(dlat, dlon)


def dedup(rows: list[dict]) -> tuple[list[dict], int]:
    """يحذف المعالم المكرّرة: نفس الاسم والتصنيف داخل نصف قطر التصنيف.

    المشكلة الفعلية: OSM يسمّي المعلم عقدةً للنقطة ومضلّعاً للمبنى وعلاقةً
    للحدود، فيدخل ثلاث مرات. شاهدنا «الكاظمية» ثلاثاً في نتائج بغداد.
    نُبقي الأعلى رتبة لأنه الأغنى وسوماً.
    """
    # تنازلياً بالرتبة: أول ما نشاهده من كل اسم هو اللي نُبقيه
    rows = sorted(rows, key=lambda r: -r["rank"])

    kept: list[dict] = []
    # (تصنيف، اسم مطبّع) → إحداثيات ما أبقيناه
    seen: dict[tuple[str, str], list[tuple[float, float]]] = {}
    dropped = 0

    for r in rows:
        key = (r["category"], r["name_norm"])
        if not key[1]:
            kept.append(r)
            continue

        radius = POI_DEDUP_RADIUS_M.get(r["category"],
                                        POI_DEDUP_RADIUS_M["_default"])
        prev = seen.setdefault(key, [])

        if any(_meters_between(r["lon"], r["lat"], plon, plat) < radius
               for plon, plat in prev):
            dropped += 1
            continue

        prev.append((r["lon"], r["lat"]))
        kept.append(r)

    return kept, dropped


def extract(pbf, con: sqlite3.Connection) -> dict[str, int]:
    import osmium

    stats = {"nodes": 0, "ways": 0, "streets": 0, "skipped_noname": 0}
    rows: list[dict] = []
    next_id = 1

    def add(osm_type: str, osm_id: int, category: str, subtype: str,
            tags, lon: float, lat: float) -> None:
        nonlocal next_id
        name_ar, name_en = pick_names(tags)
        if POI_REQUIRE_NAME and not (name_ar or name_en):
            stats["skipped_noname"] += 1
            return

        rows.append({
            "id": next_id,
            "osm_type": osm_type,
            "osm_id": osm_id,
            "category": category,
            "subtype": subtype,
            "name_ar": name_ar,
            "name_en": name_en,
            "name_norm": normalize(name_ar or name_en or ""),
            "lat": lat,
            "lon": lon,
            "rank": rank_of(category, subtype, tags),
            "tags": keep_tags(tags),
            # التسمية العربية للتصنيف لا قيمة OSM الإنجليزية: من يكتب
            # «بنزين» يريد كل محطات الوقود لا التي اسمها يحتويها
            "terms": fts_text(name_ar or "", name_en or "",
                              POI_CATEGORY_LABELS.get(category, "")),
        })
        next_id += 1

    t0 = time.time()
    seen = 0
    for obj in osmium.FileProcessor(str(pbf)).with_locations():
        seen += 1
        if seen % 2_000_000 == 0:
            print(f"    … {seen:,} كائن، {len(rows):,} نقطة "
                  f"({time.time() - t0:.0f}s)", flush=True)

        tags = obj.tags

        if isinstance(obj, osmium.osm.Node):
            cls = classify(tags)
            if cls:
                add("n", obj.id, cls[0], cls[1], tags,
                    obj.location.lon, obj.location.lat)
                stats["nodes"] += 1

        elif isinstance(obj, osmium.osm.Way):
            hw = tags.get("highway")
            if hw in _SEARCHABLE_HIGHWAYS:
                name_ar, name_en = pick_names(tags)
                key = normalize(name_ar or name_en or "")
                if not key:
                    continue

                c = way_center(obj)
                if c is None:
                    continue

                placed = _seen_streets.setdefault(key, [])
                if any(_meters_between(c[0], c[1], plon, plat)
                       < STREET_SAME_RADIUS_M for plon, plat in placed):
                    continue

                placed.append(c)
                add("w", obj.id, "street", hw, tags, c[0], c[1])
                stats["streets"] += 1
                continue

            cls = classify(tags)
            if cls:
                c = way_center(obj)
                if c:
                    add("w", obj.id, cls[0], cls[1], tags, c[0], c[1])
                    stats["ways"] += 1

    rows, dropped = dedup(rows)
    stats["deduped"] = dropped
    print(f"    ◄ حذفنا {dropped:,} مكرّراً، نكتب {len(rows):,} صف")
    con.executemany(
        "INSERT INTO poi (id, osm_type, osm_id, category, subtype, name_ar, "
        "name_en, name_norm, lat, lon, rank, tags) VALUES "
        "(:id, :osm_type, :osm_id, :category, :subtype, :name_ar, :name_en, "
        ":name_norm, :lat, :lon, :rank, :tags)", rows)
    con.executemany("INSERT INTO poi_fts (rowid, terms) VALUES (:id, :terms)",
                    rows)
    # النقطة ليست مستطيلاً، لكن R*Tree يبي صندوقاً — نعطيه صندوقاً منعدم
    # المساحة، والاستعلام عن جوار يشتغل تماماً
    con.executemany("INSERT INTO poi_geo VALUES (:id, :lon, :lon, :lat, :lat)",
                    rows)
    con.commit()

    stats["total"] = len(rows)
    return stats


# حالات بحث صادفناها: أسماء كتبها مستخدمون في بغداد بأشكال ما تطابق OSM حرفياً
_SEARCH_CASES = [
    ("يرموك", "مستشفى اليرموك — بحث بكلمة من داخل الاسم بلا البادئة"),
    ("كاظمية", "الكاظمية — بلا «ال»"),
    ("المنصور", "حي المنصور"),
    ("مطار", "مطار بغداد الدولي"),
    ("جامعه بغداد", "تاء مربوطة مكتوبة هاء — وكلمتان لازم تتطابقا معاً"),
    ("الكرادة", "منطقة"),
    ("بنزين", "بحث بالتصنيف — لازم يرجّع محطات وقود لا أسماء تحتوي الكلمة"),
]


# ترتيب النتائج بثلاث طبقات قبل الرتبة الثابتة:
#   ١. التطابق التام للاسم المطبّع — من كتب «جامعة بغداد» يقصدها هي
#   ٢. الاسم يبدأ بالاستعلام — «المنصور» قبل «عيادة المنصور»
#   ٣. الاسم الأقصر — الاسم الطويل يحتوي كلمتنا عرضاً غالباً
# بلا هذي الطبقات كان «جامعه بغداد» يرجّع مكتبين حكوميين قبل الجامعة،
# لأن رتبة government الثابتة أعلى من رتبة university
_SEARCH_SQL = """
    SELECT p.id, p.name_ar, p.name_en, p.category, p.rank, p.lat, p.lon
    FROM poi_fts f JOIN poi p ON p.id = f.rowid
    WHERE poi_fts MATCH :q
    ORDER BY
        (p.name_norm = :norm) DESC,
        (p.name_norm LIKE :prefix) DESC,
        p.rank DESC,
        LENGTH(p.name_norm) ASC,
        bm25(poi_fts)
    LIMIT :lim
"""


def search(con: sqlite3.Connection, q: str, limit: int = 10) -> list[tuple]:
    """بحث مطابقة كل الكلمات أولاً، ثم بعضها.

    ليش مرحلتان: جرّبنا OR وحده فكان «جامعه بغداد» يرجّع «بغداد» لأن
    رتبة المدينة أعلى من رتبة الجامعة — الكلمة الثانية صارت تضرّ بدل أن
    تخصّص. وAND وحده يرجّع صفراً حين تكون كلمة واحدة مو في OSM أصلاً.
    """
    norm = normalize(q)
    tokens = norm.split()
    if not tokens:
        return []

    params = {"norm": norm, "prefix": norm + "%", "lim": limit}

    # FTS5 يعدّ المسافة AND ضمناً. النجمة بادئة: المستخدم يكتب وهو يبحث
    # فلا نطالبه بإكمال الكلمة
    and_query = " ".join(f'"{t}"*' for t in tokens)
    hits = list(con.execute(_SEARCH_SQL, {**params, "q": and_query}).fetchall())

    if len(hits) < limit and len(tokens) > 1:
        or_query = " OR ".join(f'"{t}"*' for t in tokens)
        have = {h[0] for h in hits}
        rest = con.execute(_SEARCH_SQL,
                           {**params, "q": or_query, "lim": limit * 3})
        for row in rest.fetchall():
            if row[0] not in have:
                hits.append(row)
                if len(hits) >= limit:
                    break

    return hits


def try_search(con: sqlite3.Connection) -> None:
    for q, why in _SEARCH_CASES:
        try:
            hits = search(con, q, limit=3)
        except sqlite3.OperationalError as e:
            sys.exit(f"فشل استعلام FTS على «{q}»: {e}")

        print(f"\n    «{q}» — {why}")
        if not hits:
            print("      (لا نتائج)")
        for _id, name_ar, name_en, cat, rank, _lat, _lon in hits:
            print(f"      [{rank:>3}] {cat:<10} {name_ar or name_en}")


def main() -> None:
    ap = argparse.ArgumentParser(description="استخراج نقاط الاهتمام للبحث المحلي")
    ap.add_argument("--full", action="store_true", help="العراق كامل")
    args = ap.parse_args()

    ensure_dirs()
    pbf = IRAQ_PBF if args.full else SAMPLE_PBF
    if not pbf.exists():
        sys.exit(f"{pbf} غير موجود — شغّل 01_fetch_osm.py أولاً")

    print(f"─ المرحلة ٠٤: نقاط الاهتمام ({pbf.name}) ─")

    print("\n١. تهيئة القاعدة")
    con = init_db(POI_DB)
    print(f"  ✓ {POI_DB}")

    print("\n٢. الاستخراج")
    stats = extract(pbf, con)

    print("\n٣. الإحصاء")
    print(f"    عُقد نقاط اهتمام  {stats['nodes']:>8,}")
    print(f"    مضلّعات           {stats['ways']:>8,}")
    print(f"    شوارع مسمّاة      {stats['streets']:>8,}")
    print(f"    بلا اسم (مهملة)   {stats['skipped_noname']:>8,}")
    print(f"    مكرّرة (محذوفة)   {stats['deduped']:>8,}")
    print(f"    المجموع           {stats['total']:>8,}")

    by_cat = con.execute(
        "SELECT category, COUNT(*) FROM poi GROUP BY category "
        "ORDER BY COUNT(*) DESC").fetchall()
    print("\n    حسب التصنيف:")
    for cat, n in by_cat:
        print(f"      {cat:<12} {n:>7,}")

    print("\n٤. تجربة بحث")
    try_search(con)

    con.execute("VACUUM")
    # WAL يبقى في ترويسة الملف بعد الإغلاق، وقاعدة بوضع WAL تحتاج إنشاء
    # ملف -shm قبل أول قراءة — والتطبيق يفتحها readOnly فما يقدر ينشئه.
    # DELETE يجعل الملف مكتفياً بنفسه، وهو ما نشحنه
    con.execute("PRAGMA journal_mode = DELETE")
    con.close()
    size = POI_DB.stat().st_size
    print(f"\n  حجم القاعدة: {size / 1024 / 1024:.1f}MB")

    print("\n✓ المرحلة ٠٤ تمّت. التالي: تطبيق Flutter")


if __name__ == "__main__":
    main()
