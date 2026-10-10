# -*- coding: utf-8 -*-
"""المرحلة ٠٨: دمج نقاط Overture Maps مع قاعدة البحث.

يقرأ: darb-data/poi/pois.sqlite (من المرحلة ٠٤) + Overture من S3
ينتج: نفس القاعدة وقد كبرت، مع عمود source لكل صفّ

المشكلة التي يحلّها — مقيسة لا مفترَضة (2026-10-09):

    المدينة      OSM عندنا    Overture    الزيادة
    بغداد           24,701      22,446       +91%
    البصرة           3,540       2,387       +67%
    الموصل           3,127       2,218       +71%
    الناصرية         1,191         679       +57%

62,426 نقطة داخل العراق، ولا واحدة منها في OSM. 72% لها اسم عربي،
و48,546 لها رقم هاتف. مصدرها Meta وMicrosoft وFoursquare عبر Overture.

الترخيص CDLA-Permissive-2.0 — تجاري مسموح بشرط الإسناد. لهذا نخزّن
المصدر مع كل صفّ، ويعرضه التطبيق في بطاقة المكان.

ما لا يحلّه: أسماء الشوارع. طبقة الطرق عند Overture من OSM نفسه
(قِسناه: 12,597 قطعة من OSM مقابل 6 من TomTom في رقعة بغداد).

    python 08_merge_overture.py --download   # ينزّل العراق (~10MB)
    python 08_merge_overture.py              # يدمج في القاعدة
    python 08_merge_overture.py --dry-run    # يحسب بلا كتابة
"""

import re
import sys
import json
import math
import time
import sqlite3
import argparse

from config import (
    POI_DB, OVERTURE_S3, OVERTURE_DIR, OVERTURE_PLACES, OVERTURE_COUNTRY,
    OVERTURE_RELEASE,
    OVERTURE_MIN_CONFIDENCE, OVERTURE_DEDUP_RADIUS_M, POI_DEDUP_RADIUS_M,
    POI_CATEGORY_LABELS, ensure_dirs,
)
from arabic import normalize, fts_text

# ربط تصنيفات Overture (225 في العراق) بتصنيفاتنا الخمسة عشر.
# ما نقبل إلا ما يقابل تصنيفاً عندنا: الباقي (خدمات عقارية، مكاتب
# تسويق، موردون) ما يبحث عنه سائق، ودخوله يضخّم القاعدة ويخرّب الترتيب
_CATEGORY_MAP: dict[str, str] = {}


def _map(ours: str, *overture: str) -> None:
    for o in overture:
        _CATEGORY_MAP[o] = ours


_map("restaurant", "restaurant", "casual_eatery", "fast_food_restaurant",
     "cafe", "coffee_shop", "bakery", "dessert_shop", "juice_bar",
     "food_court", "buffet", "pizzeria", "burger_restaurant",
     "middle_eastern_restaurant", "turkish_restaurant", "seafood_restaurant",
     "grill", "shawarma_restaurant", "breakfast_and_brunch_restaurant")

# أسماء التصنيفات مأخوذة من القائمة الفعلية في بيانات العراق لا من
# التوثيق: جرّبنا «diagnostics_imaging_or_laboratory_service» فما طابق،
# والاسم الحقيقي «…_lab_service»
_map("hospital", "hospital", "health_care", "specialized_health_care",
     "dental_clinic", "diagnostics_imaging_or_lab_service", "surgery",
     "medical_service", "specialized_medical_facility",
     "primary_care_or_general_clinic", "outpatient_care_facility",
     "emergency_or_urgent_care_facility", "pediatric_clinic",
     "vision_or_eye_care_clinic", "behavioral_or_mental_health_clinic",
     "reproductive_perinatal_and_womens_care", "optometrist",
     "physical_therapy", "veterinary_care")

# خدمات السيارات: السائق يبحث عنها بالتحديد — تصليح، كهربائي، بنجرچي،
# معرض. أهملناها أول مرة وهي 1,292 نقطة في العراق
_map("car_service", "automotive_service", "auto_dealer", "car_wash",
     "tire_dealer_and_repair_shop", "auto_body_shop",
     "motorcycle_dealer_and_repair")

_map("pharmacy", "pharmacy_and_drug_store", "pharmacy")

_map("fuel", "gas_station", "petrol_station", "automotive_fuel_station")

_map("market", "shopping", "shopping_mall", "food_and_beverage_store",
     "grocery_store", "supermarket", "convenience_store",
     "fashion_and_apparel_store", "electronics_store",
     "hardware_home_and_garden_store", "vehicle_parts_store",
     "books_music_and_video_store", "flowers_and_gifts_store",
     "furniture_store", "jewelry_store", "mobile_phone_store",
     "department_store", "wholesale_store")

_map("school", "elementary_school", "high_school", "place_of_learning",
     "education", "school", "kindergarten", "preschool", "middle_school",
     "specialty_school")

_map("university", "college_university", "university", "college")

_map("bank", "financial_service", "bank_credit_union", "bank", "atm")

_map("mosque", "muslim_place_of_worship", "religious_organization",
     "mosque", "shrine", "church", "place_of_worship")

_map("hotel", "hotel", "lodging", "motel", "hostel", "resort",
     "bed_and_breakfast")

_map("government", "government_office", "community_and_government",
     "police_station", "fire_station", "post_office", "courthouse",
     "embassy", "city_hall", "library", "social_or_community_service")

_map("transport", "airport", "bus_station", "train_station", "taxi_service",
     "transportation_service", "travel_service", "car_rental", "parking")

_map("park", "park", "playground", "garden", "recreation_center",
     "sport_or_fitness_facility", "gym", "stadium", "zoo")

# معالم تستحق الظهور على الخريطة ويبحث عنها الناس
_map("place", "historic_site", "tourist_attraction", "monument", "museum",
     "landmark_and_historical_building")


def human(n: float) -> str:
    for unit in ("B", "KB", "MB", "GB"):
        if n < 1024:
            return f"{n:.1f}{unit}"
        n /= 1024.0
    return f"{n:.1f}TB"


def meters_between(lon1: float, lat1: float,
                   lon2: float, lat2: float) -> float:
    dlat = (lat2 - lat1) * 111_320.0
    dlon = (lon2 - lon1) * 111_320.0 * math.cos(math.radians((lat1 + lat2) / 2))
    return math.hypot(dlat, dlon)


# ── التنزيل ────────────────────────────────────────────────────────────────

def download() -> None:
    """ينزّل نقاط العراق من Overture إلى parquet محلي."""
    try:
        import duckdb
    except ImportError:
        sys.exit("يلزم duckdb:  pip install duckdb")

    OVERTURE_DIR.mkdir(parents=True, exist_ok=True)

    con = duckdb.connect()
    con.execute("INSTALL httpfs; LOAD httpfs; SET s3_region='us-west-2';"
                " SET enable_progress_bar=false;")

    print(f"  ◄ تنزيل من {OVERTURE_S3}")
    print("    (قد يأخذ دقيقة — نقرأ من S3 ونقتطع العراق)")
    t0 = time.time()

    # نختار الأعمدة صراحةً: الجدول الكامل فيه هياكل متداخلة ثقيلة،
    # وقراءتها كلها تحوّل تنزيلاً من 10MB إلى غيغابايتات
    con.execute(f"""
        COPY (
          SELECT id,
                 names.primary                              AS name_primary,
                 names.common                               AS name_common,
                 basic_category,
                 confidence,
                 addresses[1].country                       AS country,
                 addresses[1].freeform                      AS address,
                 addresses[1].locality                      AS locality,
                 phones,
                 websites,
                 list_transform(sources, s -> s.dataset)    AS datasets,
                 bbox.xmin AS lon, bbox.ymin AS lat
          FROM read_parquet(?, filename=false, hive_partitioning=1)
          WHERE bbox.xmin BETWEEN 38.7 AND 48.6
            AND bbox.ymin BETWEEN 29.0 AND 37.4
        ) TO '{OVERTURE_PLACES.as_posix()}' (FORMAT PARQUET)
    """, [OVERTURE_S3])

    size = OVERTURE_PLACES.stat().st_size
    n = con.execute(
        f"SELECT count(*) FROM '{OVERTURE_PLACES.as_posix()}'").fetchone()[0]
    print(f"  ✓ {n:,} صفّ — {human(size)} في {time.time() - t0:.0f}s")


# ── القراءة والتصفية ───────────────────────────────────────────────────────

def load_candidates() -> list[dict]:
    """يقرأ الـparquet ويرجّع المرشّحين بعد التصفية والتصنيف."""
    try:
        import duckdb
    except ImportError:
        sys.exit("يلزم duckdb:  pip install duckdb")

    if not OVERTURE_PLACES.exists():
        sys.exit(f"{OVERTURE_PLACES} غير موجود — شغّل --download أولاً")

    con = duckdb.connect()
    rows = con.execute(f"""
        SELECT id, name_primary, name_common, basic_category, confidence,
               address, locality, phones, websites, datasets, lon, lat
        FROM '{OVERTURE_PLACES.as_posix()}'
        WHERE country = ?
          AND confidence >= ?
          AND name_primary IS NOT NULL
    """, [OVERTURE_COUNTRY, OVERTURE_MIN_CONFIDENCE]).fetchall()

    out: list[dict] = []
    skipped_category = 0

    for (gers, name, common, cat, conf, address, locality,
         phones, websites, datasets, lon, lat) in rows:
        ours = _CATEGORY_MAP.get(cat or "")
        if ours is None:
            skipped_category += 1
            continue

        # الاسم العربي: من name.common['ar'] إن وُجد، وإلا من الأساسي
        # إذا كان مكتوباً بحروف عربية
        name_ar = None
        name_en = None
        common = dict(common or {})
        if "ar" in common:
            name_ar = common["ar"]
        if _has_arabic(name):
            name_ar = name_ar or name
        else:
            name_en = name

        tags = {}
        if phones:
            tags["phone"] = phones[0]
        if websites:
            tags["website"] = websites[0]
        if address:
            tags["addr:street"] = address
        if locality:
            tags["addr:city"] = locality

        out.append({
            # معرّف GERS: ثابت بين إصدارات Overture، ونحتاجه كي نحدّث
            # نقطة بدل ما نضيفها من جديد في التحديث القادم
            "gers": gers,
            "category": ours,
            "subtype": cat,
            "name_ar": name_ar,
            "name_en": name_en,
            "name_norm": normalize(name_ar or name_en or ""),
            "lat": lat,
            "lon": lon,
            "confidence": conf,
            "tags": json.dumps(tags, ensure_ascii=False) if tags else None,
            "source": "overture:" + ",".join(sorted(set(datasets or []))),
        })

    print(f"    قرأنا {len(rows):,} صفّاً، قبلنا {len(out):,}، "
          f"أهملنا {skipped_category:,} بتصنيف لا يهمّ سائقاً")
    return out


_ARABIC_RE = re.compile(r"[؀-ۿ]")


def _has_arabic(s: str) -> bool:
    return bool(_ARABIC_RE.search(s or ""))


# ── الدمج ──────────────────────────────────────────────────────────────────

def ensure_source_column(con: sqlite3.Connection) -> None:
    """يضيف عمود source إن لم يكن موجوداً.

    الإسناد لكل صفّ لا سطر واحد في «عن التطبيق»: CDLA تشترط الإسناد،
    وخلط مصدرين في قاعدة واحدة بلا تمييز يجعل الإسناد غير قابل للتحقّق.
    """
    cols = {r[1] for r in con.execute("PRAGMA table_info(poi)")}
    if "source" not in cols:
        con.execute("ALTER TABLE poi ADD COLUMN source TEXT")
        con.execute("UPDATE poi SET source = 'osm' WHERE source IS NULL")
        con.commit()
        print("    أضفنا عمود source ووسمنا الموجود بـosm")


def build_index(con: sqlite3.Connection) -> dict[tuple[str, str], list[tuple]]:
    """فهرس (تصنيف، اسم مطبّع) → إحداثيات، من نقاط OSM الموجودة.

    بديل البحث المكاني لكل مرشّح: 62 ألف مرشّح × استعلام R*Tree أبطأ
    بكثير من قاموس في الذاكرة، والقاعدة كلها 105 آلاف صفّ.
    """
    idx: dict[tuple[str, str], list[tuple]] = {}
    for cat, norm, lon, lat in con.execute(
            "SELECT category, name_norm, lon, lat FROM poi"):
        if not norm:
            continue
        idx.setdefault((cat, norm), []).append((lon, lat))
    return idx


def _with_gers(tags_json: str | None, gers: str) -> str:
    """يضيف معرّف GERS إلى وسوم النقطة."""
    tags = json.loads(tags_json) if tags_json else {}
    tags["gers"] = gers
    return json.dumps(tags, ensure_ascii=False)


def merge(con: sqlite3.Connection, candidates: list[dict],
          dry_run: bool) -> dict[str, int]:
    ensure_source_column(con)
    idx = build_index(con)

    next_id = (con.execute("SELECT COALESCE(MAX(id), 0) FROM poi").fetchone()[0]
               + 1)

    stats = {"added": 0, "dup_osm": 0, "dup_self": 0, "by_cat": {}}
    rows: list[dict] = []

    # رتبة نقاط Overture أقل من مثيلتها في OSM بخمس درجات: OSM يحرّره
    # بشر يعرفون المكان، وMeta تستنتج من بيانات أعمال قد تكون قديمة.
    # الفرق صغير كي لا تختفي، وكافٍ كي يتقدّم المحرَّر يدوياً عند التعادل
    base_rank = {"place": 95, "transport": 55, "hospital": 50,
                 "university": 47, "government": 45, "fuel": 40,
                 "market": 35, "car_service": 33, "school": 30,
                 "mosque": 28, "bank": 25,
                 "pharmacy": 23, "hotel": 20, "park": 15, "restaurant": 12}

    for c in candidates:
        key = (c["category"], c["name_norm"])
        if not c["name_norm"]:
            continue

        radius = OVERTURE_DEDUP_RADIUS_M
        near = idx.get(key, [])

        if any(meters_between(c["lon"], c["lat"], plon, plat) < radius
               for plon, plat in near):
            stats["dup_osm"] += 1
            continue

        # ومكرّرة داخل Overture نفسها: نفس المحل يرد من Meta وFoursquare
        # بإحداثيات متقاربة. نضع المقبولين في نفس الفهرس بمفتاح موسوم
        # كي يقارن بهم من يأتي بعدهم
        self_key = ("+" + c["category"], c["name_norm"])
        if any(meters_between(c["lon"], c["lat"], plon, plat) <
               POI_DEDUP_RADIUS_M["_default"]
               for plon, plat in idx.get(self_key, [])):
            stats["dup_self"] += 1
            continue

        idx.setdefault(self_key, []).append((c["lon"], c["lat"]))

        rank = base_rank.get(c["category"], 10)
        # الثقة ترفع الرتبة قليلاً: نقطة بثقة 0.9 أرجح من واحدة بـ0.35
        rank += int(round(c["confidence"] * 4))
        # الفحص على المفتاح لا على نصّ JSON: «phone» ككلمة تظهر في
        # موقع phonehouse.iq فترفع الرتبة بلا رقم هاتف
        if c["tags"] and "phone" in json.loads(c["tags"]):
            rank += 2

        rows.append({
            "id": next_id,
            # o = overture تمييزاً عن n/w/r. وosm_id يأخذ نفس id لأن
            # معرّف Overture نصّ (GERS) لا عدد، والقيد في القاعدة مركّب
            # على (osm_type, osm_id) — صفر لكلها يكسره
            "osm_type": "o",
            "osm_id": next_id,
            "category": c["category"],
            "subtype": c["subtype"],
            "name_ar": c["name_ar"],
            "name_en": c["name_en"],
            "name_norm": c["name_norm"],
            "lat": c["lat"],
            "lon": c["lon"],
            "rank": rank,
            "tags": _with_gers(c["tags"], c["gers"]),
            "source": c["source"],
            # التسمية العربية للتصنيف لا قيمة Overture الإنجليزية:
            # «fashion_and_apparel_store» ما يبحث بها أحد
            "terms": fts_text(c["name_ar"] or "", c["name_en"] or "",
                              POI_CATEGORY_LABELS.get(c["category"], "")),
        })
        next_id += 1
        stats["added"] += 1
        stats["by_cat"][c["category"]] = \
            stats["by_cat"].get(c["category"], 0) + 1

    if dry_run:
        print("    (تجربة — ما كتبنا شيئاً)")
        return stats

    con.executemany(
        "INSERT INTO poi (id, osm_type, osm_id, category, subtype, name_ar, "
        "name_en, name_norm, lat, lon, rank, tags, source) VALUES "
        "(:id, :osm_type, :osm_id, :category, :subtype, :name_ar, :name_en, "
        ":name_norm, :lat, :lon, :rank, :tags, :source)", rows)
    con.executemany("INSERT INTO poi_fts (rowid, terms) VALUES (:id, :terms)",
                    rows)
    con.executemany("INSERT INTO poi_geo VALUES (:id, :lon, :lon, :lat, :lat)",
                    rows)

    con.execute(
        "INSERT OR REPLACE INTO search_meta VALUES ('overture_release', ?)",
        (OVERTURE_RELEASE,))
    con.execute(
        "INSERT OR REPLACE INTO search_meta VALUES ('attribution', ?)",
        ("© OpenStreetMap contributors (ODbL) · "
         "© Overture Maps Foundation (CDLA-Permissive-2.0)",))
    con.commit()
    return stats


def main() -> None:
    ap = argparse.ArgumentParser(
        description="دمج نقاط Overture Maps مع قاعدة البحث")
    ap.add_argument("--download", action="store_true",
                    help="نزّل بيانات العراق من Overture أولاً")
    ap.add_argument("--dry-run", action="store_true",
                    help="احسب الزيادة بلا كتابة في القاعدة")
    args = ap.parse_args()

    ensure_dirs()
    print("─ المرحلة ٠٨: دمج Overture Maps ─")

    if args.download:
        print("\n١. التنزيل")
        download()

    if not POI_DB.exists():
        sys.exit(f"{POI_DB} غير موجود — شغّل 04_extract_pois.py أولاً")

    print("\n٢. القراءة والتصنيف")
    candidates = load_candidates()

    con = sqlite3.connect(POI_DB)
    before, = con.execute("SELECT COUNT(*) FROM poi").fetchone()

    print("\n٣. الدمج")
    t0 = time.time()
    stats = merge(con, candidates, args.dry_run)

    print(f"\n    أضفنا        {stats['added']:>8,}")
    print(f"    مكرّرة مع OSM {stats['dup_osm']:>8,}")
    print(f"    مكرّرة داخلياً {stats['dup_self']:>8,}")
    print(f"    ({time.time() - t0:.0f}s)")

    if stats["by_cat"]:
        print("\n    الزيادة حسب التصنيف:")
        for cat, n in sorted(stats["by_cat"].items(),
                             key=lambda kv: -kv[1]):
            print(f"      {cat:<12} {n:>7,}")

    if not args.dry_run:
        con.execute("VACUUM")
        after, = con.execute("SELECT COUNT(*) FROM poi").fetchone()
        size = POI_DB.stat().st_size
        pct = 100 * (after - before) / before if before else 0
        print(f"\n  ✓ القاعدة {before:,} ← {after:,} نقطة "
              f"(+{pct:.0f}%) — {human(size)}")
        print("    الإسناد محفوظ في search_meta ويعرضه التطبيق")

    con.close()
    print("\n✓ المرحلة ٠٨ تمّت. التالي: python 07_pack_assets.py iraq")


if __name__ == "__main__":
    main()
