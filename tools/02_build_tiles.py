# -*- coding: utf-8 -*-
"""المرحلة ٠٢: بناء بلاطات الخريطة من PBF بـPlanetiler.

يقرأ: darb-data/osm/{baghdad|iraq-latest}.osm.pbf
ينتج: darb-data/tiles/{baghdad|iraq}.mbtiles

الخطوات:
  ١. تنزيل planetiler.jar في الكاش إن لم يكن موجوداً
  ٢. تشغيله بمخطط OpenMapTiles مع تفضيل الأسماء العربية
  ٣. فحص المخرج: عدد البلاطات، أعلى زوم، وجود بلاطة بغداد في z14

ليش MBTiles لا PMTiles: التطبيق يقرأها بسطر SQL عبر sqflite بلا طبقة
وسيطة ولا تطبيق مواصفة ثنائية بيدي، وهو أصلاً يحمل SQLite لبحث نقاط
الاهتمام. PMTiles أفضل للتقديم من CDN، ونبنيه حين نحتاج الويب.

    python 02_build_tiles.py            # العيّنة (بغداد)
    python 02_build_tiles.py --full     # العراق كامل
"""

import sys
import time
import math
import sqlite3
import argparse
import subprocess

import requests

from config import (
    IRAQ_PBF, SAMPLE_PBF, SAMPLE_NAME, TILES_DIR, TILE_MAX_ZOOM, TILE_MIN_ZOOM,
    PLANETILER_JAR, PLANETILER_JAR_URL, PLANETILER_HEAP, MAP_START_CENTER,
    PLANETILER_SOURCES_DIR, PLANETILER_TMP_DIR, PLANETILER_HTTP_TIMEOUT_S,
    PLANETILER_HTTP_RETRIES, PLANETILER_DOWNLOAD_THREADS,
    ensure_dirs,
)


def human(n: float) -> str:
    for unit in ("B", "KB", "MB", "GB"):
        if n < 1024:
            return f"{n:.1f}{unit}"
        n /= 1024.0
    return f"{n:.1f}TB"


def ensure_jar() -> None:
    if PLANETILER_JAR.exists() and PLANETILER_JAR.stat().st_size > 10 << 20:
        print(f"  ✓ planetiler.jar موجود ({human(PLANETILER_JAR.stat().st_size)})")
        return

    print(f"  ◄ تنزيل planetiler.jar من GitHub")
    r = requests.get(PLANETILER_JAR_URL, stream=True, timeout=120,
                     allow_redirects=True)
    if r.status_code != 200:
        sys.exit(f"فشل تنزيل planetiler.jar: HTTP {r.status_code}\n"
                 f"نزّله يدوياً إلى {PLANETILER_JAR} من {PLANETILER_JAR_URL}")

    tmp = PLANETILER_JAR.with_suffix(".part")
    with open(tmp, "wb") as f:
        for chunk in r.iter_content(1 << 20):
            f.write(chunk)

    # الـjar أكبر من 10MB دائماً؛ أصغر من هذا يعني أن GitHub رجّع صفحة
    if tmp.stat().st_size < 10 << 20:
        tmp.unlink()
        sys.exit("planetiler.jar المنزّل صغير جداً — يحتمل أن الإصدار "
                 f"{PLANETILER_JAR_URL} ما عاد موجوداً. حدّث PLANETILER_VERSION")

    tmp.replace(PLANETILER_JAR)
    print(f"  ✓ {human(PLANETILER_JAR.stat().st_size)}")


def build(pbf, out, heap: str) -> None:
    cmd = [
        "java", f"-Xmx{heap}", "-jar", str(PLANETILER_JAR),
        f"--osm-path={pbf}",
        f"--output={out}",
        "--force",
        f"--minzoom={TILE_MIN_ZOOM}",
        f"--maxzoom={TILE_MAX_ZOOM}",
        # Planetiler يحتاج بيانات مساعدة (بولیغونات الماء، Natural Earth،
        # ~1.3GB) وينزّلها مرة ويكاشها. المجلد صريح لأن الافتراضي
        # data/sources نسبةً لمجلد التشغيل — أي جوّا الريبو
        "--download",
        f"--download-dir={PLANETILER_SOURCES_DIR}",
        f"--tmpdir={PLANETILER_TMP_DIR}",
        # 30s الافتراضية فشلت فعلاً على osmdata.openstreetmap.de من شبكة
        # ~400KB/s، والفشل كان في قياس الحجم لا التنزيل وأسقط البناء كله
        # الصيغة "180s" لا "180 seconds": يمرّرها Planetiler لـDuration.parse
        # وجرّبنا "seconds" فرمى DateTimeParseException قبل أي عمل
        f"--http-timeout={PLANETILER_HTTP_TIMEOUT_S}s",
        f"--http-retries={PLANETILER_HTTP_RETRIES}",
        f"--download-threads={PLANETILER_DOWNLOAD_THREADS}",
        # العربية أولاً ثم الإنجليزية: نبي name:ar في البلاطة لأن واجهة
        # التطبيق عربية، والإنجليزية احتياط للأسماء غير المعرَّبة في OSM
        "--languages=ar,en",
        # التخزين على القرص لا في الذاكرة: العراق كامل يفجّر 4g لو mmap
        "--nodemap-type=array",
        "--nodemap-storage=mmap",
    ]

    print(f"  ◄ java -Xmx{heap} … {pbf.name} ← {out.name}")
    print(f"    (المخرجات الكاملة في {out.parent / (out.stem + '.planetiler.log')})")

    log_path = out.parent / (out.stem + ".planetiler.log")
    t0 = time.time()
    with open(log_path, "w", encoding="utf-8") as log:
        proc = subprocess.Popen(cmd, stdout=subprocess.PIPE,
                                stderr=subprocess.STDOUT, text=True,
                                encoding="utf-8", errors="replace")
        for line in proc.stdout:
            log.write(line)
            # نطبع أسطر المراحل فقط: Planetiler يرمي آلاف أسطر تقدّم
            if " - Starting..." in line or "Finished in" in line or "ERROR" in line:
                print(f"    {line.rstrip()[:150]}", flush=True)
        rc = proc.wait()

    if rc != 0:
        sys.exit(f"فشل Planetiler (رمز {rc}). آخر السجل:\n" +
                 "".join(open(log_path, encoding="utf-8").readlines()[-25:]))

    print(f"  ✓ {out.name} — {human(out.stat().st_size)} في {time.time() - t0:.0f}s")


def lonlat_to_tile(lon: float, lat: float, z: int) -> tuple[int, int]:
    """إحداثيات XYZ لبلاطة تحتوي النقطة — نحتاجها للفحص لا للعرض."""
    n = 2 ** z
    x = int((lon + 180.0) / 360.0 * n)
    lat_rad = math.radians(lat)
    y = int((1.0 - math.asinh(math.tan(lat_rad)) / math.pi) / 2.0 * n)
    return x, y


def inspect(out) -> None:
    """يفحص المخرج: إحصاء البلاطات، ووجود بلاطة مركز الخريطة في أعلى زوم."""
    con = sqlite3.connect(out)
    cur = con.cursor()

    total, = cur.execute("SELECT COUNT(*) FROM tiles").fetchone()
    zmin, zmax = cur.execute(
        "SELECT MIN(zoom_level), MAX(zoom_level) FROM tiles").fetchone()

    print(f"\n  إحصاء {out.name}:")
    print(f"    بلاطات      {total:>12,}")
    print(f"    زوم         {zmin} → {zmax}")

    rows = cur.execute(
        "SELECT zoom_level, COUNT(*), SUM(LENGTH(tile_data)) FROM tiles "
        "GROUP BY zoom_level ORDER BY zoom_level").fetchall()
    for z, n, nbytes in rows:
        print(f"      z{z:<3} {n:>10,} بلاطة   {human(nbytes or 0):>9}")

    # بلاطة مركز الخريطة في أعلى زوم لازم تكون موجودة وغير فارغة، وإلا
    # التطبيق راح يفتح على شاشة رمادية والسبب يصعب تشخيصه لاحقاً
    lon, lat = MAP_START_CENTER
    x, y = lonlat_to_tile(lon, lat, TILE_MAX_ZOOM)
    # MBTiles يخزّن y مقلوباً (TMS) بخلاف XYZ
    tms_y = (2 ** TILE_MAX_ZOOM - 1) - y
    row = cur.execute(
        "SELECT LENGTH(tile_data) FROM tiles WHERE zoom_level=? AND "
        "tile_column=? AND tile_row=?", (TILE_MAX_ZOOM, x, tms_y)).fetchone()

    if not row or not row[0]:
        sys.exit(f"بلاطة مركز الخريطة ({lon},{lat}) مفقودة في z{TILE_MAX_ZOOM} "
                 f"— البلاطات مبنية لكن ما تغطّي المنطقة المطلوبة")
    print(f"    ✓ بلاطة ساحة التحرير z{TILE_MAX_ZOOM} = {human(row[0])}")

    meta = dict(cur.execute("SELECT name, value FROM metadata").fetchall())
    print(f"    الاسم «{meta.get('name', '?')}»  "
          f"الصيغة {meta.get('format', '?')}")
    con.close()


def main() -> None:
    ap = argparse.ArgumentParser(description="بناء بلاطات الخريطة بـPlanetiler")
    ap.add_argument("--full", action="store_true",
                    help="ابنِ العراق كامل بدل عيّنة بغداد")
    ap.add_argument("--heap", default=None,
                    help=f"حجم ذاكرة Java (الافتراضي {PLANETILER_HEAP})")
    args = ap.parse_args()

    ensure_dirs()

    pbf = IRAQ_PBF if args.full else SAMPLE_PBF
    name = "iraq" if args.full else SAMPLE_NAME
    out = TILES_DIR / f"{name}.mbtiles"

    if not pbf.exists():
        sys.exit(f"{pbf} غير موجود — شغّل 01_fetch_osm.py أولاً")

    print(f"─ المرحلة ٠٢: بلاطات {name} ─")
    print("\n١. الأداة")
    ensure_jar()

    print("\n٢. البناء")
    build(pbf, out, args.heap or PLANETILER_HEAP)

    print("\n٣. الفحص")
    inspect(out)

    print("\n✓ المرحلة ٠٢ تمّت. التالي: 03_build_routing_graph.py")


if __name__ == "__main__":
    main()
