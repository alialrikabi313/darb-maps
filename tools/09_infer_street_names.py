# -*- coding: utf-8 -*-
"""المرحلة ٠٩: أسماء شوارع من عناوين المباني.

يقرأ: darb-data/osm/iraq-latest.osm.pbf + poi/pois.sqlite
ينتج: صفوف شوارع جديدة في نفس القاعدة

المشكلة: 9% فقط من طرق العراق مسمّاة. سألنا «ليش ما نأخذ الأسماء من
خرائط Google؟» — ما نقدر، بياناتهم ممنوعة استخراجاً وشراءً (شروطهم تمنع
عرض أماكنهم على خريطة غير خرائطهم).

لكن قِسنا فوجدنا أسماء نملكها ولا نستعملها: 43,794 مبنى في العراق يحمل
وسم addr:street، وفيها 9,780 اسم شارع مختلف. الاسم موجود في OSM — على
المبنى لا على الطريق. فما كان البحث يجده ولا الصوت ينطقه.

نستخرجها مرّتين:

  ١. اسماً قابلاً للبحث بنفسه. من يكتب «شارع السلام» يصل لمركز تجمّع
     المباني التي تحمله. مكسب أكيد بلا تخمين.

  ٢. استنتاجاً لاسم الطريق المجاور: طريق بلا اسم تحيط به مبانٍ تتفق
     على addr:street واحد هو ذلك الشارع غالباً. هذا تخمين — نوسمه
     بمصدر «osm-inferred» ورتبة أقل، وتعرضه الواجهة بعلامة.

    python 09_infer_street_names.py            # العراق
    python 09_infer_street_names.py --sample   # عيّنة بغداد، أسرع
    python 09_infer_street_names.py --dry-run
"""

import sys
import math
import time
import json
import sqlite3
import argparse
import collections

from config import (
    IRAQ_PBF, SAMPLE_PBF, POI_DB, STREET_INFER_RADIUS_M,
    STREET_INFER_MIN_VOTES, STREET_INFER_MIN_SHARE, ensure_dirs,
)
from arabic import normalize, fts_text

# أصناف الطرق التي نحاول تسميتها. الخدمي والمسار خارج: أسماؤها لا
# تُبحث، ونسبة اسم شارع لممرّ موقف خطأ مرئي على الخريطة
_NAMEABLE = {"motorway", "trunk", "primary", "secondary", "tertiary",
             "residential", "living_street", "unclassified"}

# حجم خلية الفهرس المكاني بالدرجات. 0.001° ≈ 110م — أكبر من نصف قطر
# البحث كي تكفي خلية واحدة وجاراتها
_CELL = 0.001


def human(n: float) -> str:
    for unit in ("B", "KB", "MB"):
        if n < 1024:
            return f"{n:.1f}{unit}"
        n /= 1024.0
    return f"{n:.1f}GB"


def meters_between(lon1: float, lat1: float,
                   lon2: float, lat2: float) -> float:
    dlat = (lat2 - lat1) * 111_320.0
    dlon = (lon2 - lon1) * 111_320.0 * math.cos(math.radians((lat1 + lat2) / 2))
    return math.hypot(dlat, dlon)


def _cell(lon: float, lat: float) -> tuple[int, int]:
    return (int(lon / _CELL), int(lat / _CELL))


# ── المرور على البيانات ────────────────────────────────────────────────────

class Harvest:
    """ما نجمعه في مرور واحد على الـPBF."""

    def __init__(self) -> None:
        # (اسم مطبّع) → [(الاسم الأصلي، lon، lat)، …]
        self.addresses: dict[str, list[tuple[str, float, float]]] = \
            collections.defaultdict(list)
        # فهرس مكاني: خلية → [(اسم مطبّع، lon، lat)، …]
        self.grid: dict[tuple[int, int], list] = collections.defaultdict(list)
        # الطرق بلا اسم: (معرّف، صنف، [إحداثيات العيّنة])
        self.unnamed: list[tuple[int, str, list]] = []
        self.stats = collections.Counter()


def harvest(pbf) -> Harvest:
    import osmium

    h = Harvest()
    t0 = time.time()
    seen = 0

    for obj in osmium.FileProcessor(str(pbf)).with_locations():
        seen += 1
        if seen % 3_000_000 == 0:
            print(f"    … {seen:,} كائن ({time.time() - t0:.0f}s)", flush=True)

        tags = obj.tags
        street = tags.get("addr:street")

        # عنوان على عقدة أو على مضلّع مبنى
        if street:
            norm = normalize(street)
            if norm:
                loc = None
                if isinstance(obj, osmium.osm.Node):
                    loc = (obj.location.lon, obj.location.lat)
                elif isinstance(obj, osmium.osm.Way):
                    pts = [(n.location.lon, n.location.lat)
                           for n in obj.nodes if n.location.valid()]
                    if pts:
                        loc = pts[len(pts) // 2]

                if loc:
                    h.addresses[norm].append((street, loc[0], loc[1]))
                    h.grid[_cell(*loc)].append((norm, loc[0], loc[1]))
                    h.stats["address_tags"] += 1

        if isinstance(obj, osmium.osm.Way):
            hw = tags.get("highway")
            if hw not in _NAMEABLE:
                continue
            h.stats["nameable"] += 1

            if "name" in tags or "name:ar" in tags:
                h.stats["already_named"] += 1
                continue

            pts = [(n.location.lon, n.location.lat)
                   for n in obj.nodes if n.location.valid()]
            if len(pts) < 2:
                continue

            # نأخذ عيّنة لا كل العُقد: طريق فيه 400 عقدة يصوّت 400 مرة
            # فيطغى على غيره، والعشر نقاط تكفي لتغطية طوله
            step = max(1, len(pts) // 10)
            h.unnamed.append((obj.id, hw, pts[::step]))

    print(f"    ✓ {h.stats['address_tags']:,} عنوان، "
          f"{len(h.addresses):,} اسم شارع مختلف، "
          f"{len(h.unnamed):,} طريق بلا اسم "
          f"({time.time() - t0:.0f}s)")
    return h


# ── الاستنتاج ──────────────────────────────────────────────────────────────

def infer(h: Harvest) -> list[dict]:
    """ينسب اسم شارع لكل طريق بلا اسم، حين تتفق المباني حوله."""
    out: list[dict] = []
    t0 = time.time()

    for i, (way_id, hw, pts) in enumerate(h.unnamed):
        if i % 100_000 == 0 and i:
            print(f"    … {i:,}/{len(h.unnamed):,} طريق "
                  f"({time.time() - t0:.0f}s)", flush=True)

        votes: collections.Counter = collections.Counter()

        for lon, lat in pts:
            cx, cy = _cell(lon, lat)
            # الخلية وجاراتها الثماني: نصف قطر البحث أصغر من الخلية
            for dx in (-1, 0, 1):
                for dy in (-1, 0, 1):
                    for norm, alon, alat in h.grid.get((cx + dx, cy + dy), ()):
                        if meters_between(lon, lat, alon, alat) \
                                <= STREET_INFER_RADIUS_M:
                            votes[norm] += 1

        if not votes:
            continue

        total = sum(votes.values())
        name, n = votes.most_common(1)[0]

        if n < STREET_INFER_MIN_VOTES or n / total < STREET_INFER_MIN_SHARE:
            continue

        # نقطة الطريق: منتصف العيّنة — على الطريق نفسه لا على مبنى
        lon, lat = pts[len(pts) // 2]
        original = h.addresses[name][0][0]

        out.append({
            "osm_id": way_id,
            "subtype": hw,
            "name": original,
            "name_norm": name,
            "lon": lon,
            "lat": lat,
            "votes": n,
            "share": round(n / total, 2),
        })

    print(f"    ✓ استنتجنا {len(out):,} اسماً ({time.time() - t0:.0f}s)")
    return out


def street_centroids(h: Harvest) -> list[dict]:
    """مركز تجمّع المباني لكل اسم شارع — قابل للبحث بلا أي تخمين.

    ليس استنتاجاً: الاسم مكتوب في OSM، وموقعه متوسط المباني التي تحمله.
    من يبحث «شارع السلام» يصل إليه، وهو ما كان مستحيلاً قبل هذا.
    """
    out: list[dict] = []

    for norm, entries in h.addresses.items():
        if len(entries) < 2:
            continue

        # الوسيط لا المتوسط: شارع طويل فيه مبنى شاذّ بعيد يجرّ المتوسط
        # لمكان ما فيه شيء
        lons = sorted(e[1] for e in entries)
        lats = sorted(e[2] for e in entries)
        mid = len(entries) // 2

        out.append({
            "name": entries[0][0],
            "name_norm": norm,
            "lon": lons[mid],
            "lat": lats[mid],
            "buildings": len(entries),
        })

    return out


# ── الكتابة ────────────────────────────────────────────────────────────────

def existing_streets(con: sqlite3.Connection) -> dict[str, list]:
    idx: dict[str, list] = collections.defaultdict(list)
    for norm, lon, lat in con.execute(
            "SELECT name_norm, lon, lat FROM poi WHERE category = 'street'"):
        if norm:
            idx[norm].append((lon, lat))
    return idx


def write(con: sqlite3.Connection, centroids: list[dict],
          inferred: list[dict], dry_run: bool) -> dict:
    cols = {r[1] for r in con.execute("PRAGMA table_info(poi)")}
    if "source" not in cols:
        con.execute("ALTER TABLE poi ADD COLUMN source TEXT")
        con.execute("UPDATE poi SET source = 'osm' WHERE source IS NULL")

    idx = existing_streets(con)
    next_id = (con.execute("SELECT COALESCE(MAX(id),0) FROM poi").fetchone()[0]
               + 1)
    next_osm = (con.execute(
        "SELECT COALESCE(MAX(osm_id),0) FROM poi").fetchone()[0] + 1)

    rows: list[dict] = []
    stats = collections.Counter()

    # ١. مراكز الشوارع من العناوين — يقين لا تخمين
    for c in centroids:
        near = idx.get(c["name_norm"], [])
        # 1200م: نفس نصف قطر إزالة تكرار الشوارع في المرحلة ٠٤
        if any(meters_between(c["lon"], c["lat"], plon, plat) < 1200
               for plon, plat in near):
            stats["centroid_dup"] += 1
            continue

        rows.append(_row(next_id, next_osm, c["name"], c["name_norm"],
                         c["lon"], c["lat"], "addr",
                         rank=12 + min(6, c["buildings"] // 5),
                         source="osm-address",
                         tags={"buildings": c["buildings"]}))
        idx[c["name_norm"]].append((c["lon"], c["lat"]))
        next_id += 1
        next_osm += 1
        stats["centroid_added"] += 1

    # ٢. الطرق المستنتَجة — تخمين مُعلَن
    for s in inferred:
        near = idx.get(s["name_norm"], [])
        if any(meters_between(s["lon"], s["lat"], plon, plat) < 400
               for plon, plat in near):
            stats["inferred_dup"] += 1
            continue

        rows.append(_row(next_id, next_osm, s["name"], s["name_norm"],
                         s["lon"], s["lat"], s["subtype"],
                         # أقل من المسمّى صراحةً في OSM: التخمين يتأخّر
                         # عن اليقين عند تساوي التطابق
                         rank=8,
                         source="osm-inferred",
                         tags={"inferred_from": "addr:street",
                               "votes": s["votes"], "share": s["share"],
                               "way": s["osm_id"]}))
        idx[s["name_norm"]].append((s["lon"], s["lat"]))
        next_id += 1
        next_osm += 1
        stats["inferred_added"] += 1

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
    con.commit()
    return stats


def _row(rid: int, osm_id: int, name: str, norm: str, lon: float, lat: float,
         subtype: str, rank: int, source: str, tags: dict) -> dict:
    import re
    arabic = bool(re.search(r"[؀-ۿ]", name))
    return {
        "id": rid,
        # a = address-derived، تمييزاً عن n/w/r و o
        "osm_type": "a",
        "osm_id": osm_id,
        "category": "street",
        "subtype": subtype,
        "name_ar": name if arabic else None,
        "name_en": None if arabic else name,
        "name_norm": norm,
        "lat": lat,
        "lon": lon,
        "rank": rank,
        "tags": json.dumps(tags, ensure_ascii=False),
        "source": source,
        "terms": fts_text(name if arabic else "", "" if arabic else name,
                          "شارع"),
    }


def main() -> None:
    ap = argparse.ArgumentParser(
        description="استخراج أسماء الشوارع من عناوين المباني")
    ap.add_argument("--sample", action="store_true",
                    help="اشتغل على عيّنة بغداد لا العراق")
    ap.add_argument("--dry-run", action="store_true",
                    help="احسب بلا كتابة")
    args = ap.parse_args()

    ensure_dirs()
    pbf = SAMPLE_PBF if args.sample else IRAQ_PBF
    if not pbf.exists():
        sys.exit(f"{pbf} غير موجود — شغّل 01_fetch_osm.py أولاً")
    if not POI_DB.exists():
        sys.exit(f"{POI_DB} غير موجود — شغّل 04_extract_pois.py أولاً")

    print(f"─ المرحلة ٠٩: أسماء الشوارع من العناوين ({pbf.name}) ─")

    print("\n١. الجمع")
    h = harvest(pbf)

    if not h.addresses:
        sys.exit("ما في أي وسم addr:street — لا شيء نستخرجه")

    print("\n٢. مراكز الشوارع")
    centroids = street_centroids(h)
    print(f"    ✓ {len(centroids):,} شارعاً له مبنيان فأكثر")

    print("\n٣. استنتاج أسماء الطرق")
    inferred = infer(h)

    print("\n٤. الكتابة")
    con = sqlite3.connect(POI_DB)
    before, = con.execute("SELECT COUNT(*) FROM poi").fetchone()
    stats = write(con, centroids, inferred, args.dry_run)

    print(f"\n    مراكز شوارع مضافة   {stats['centroid_added']:>8,}")
    print(f"    منها مكرّر           {stats['centroid_dup']:>8,}")
    print(f"    طرق مستنتَجة مضافة  {stats['inferred_added']:>8,}")
    print(f"    منها مكرّر           {stats['inferred_dup']:>8,}")

    if not args.dry_run:
        con.execute("VACUUM")
        after, = con.execute("SELECT COUNT(*) FROM poi").fetchone()
        streets, = con.execute(
            "SELECT COUNT(*) FROM poi WHERE category='street'").fetchone()
        print(f"\n  ✓ القاعدة {before:,} ← {after:,} "
              f"(شوارع قابلة للبحث: {streets:,}) — "
              f"{human(POI_DB.stat().st_size)}")

    con.close()
    print("\n✓ المرحلة ٠٩ تمّت. التالي: python 07_pack_assets.py iraq")


if __name__ == "__main__":
    main()
