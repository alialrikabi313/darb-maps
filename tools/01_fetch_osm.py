# -*- coding: utf-8 -*-
"""المرحلة ٠١: تنزيل خريطة العراق من OSM وتقليم عيّنة بغداد.

يقرأ: لا شيء (المصدر من الشبكة).
ينتج: darb-data/osm/iraq-latest.osm.pbf و darb-data/osm/baghdad.osm.pbf

الخطوات:
  ١. تنزيل ملف العراق من Geofabrik — قابل للاستئناف عبر Range
  ٢. التحقق من الحجم والترويسة قبل اعتماده
  ٣. تقليم bbox بغداد منه بـpyosmium
  ٤. طباعة إحصاء العُقد والطرق في المخرجين

شغّله مرة واحدة. لإعادة التنزيل من الصفر مرّر --force.
"""

import sys
import time
import argparse

import requests

from config import (
    IRAQ_PBF, IRAQ_PBF_URL, IRAQ_PBF_MIN_BYTES, SAMPLE_PBF, SAMPLE_BBOX,
    ensure_dirs,
)

_CHUNK = 1 << 20  # 1MB

# أول 4 بايت في PBF هي طول BlobHeader بـbig-endian وتكون صغيرة. نستخدمها
# فحصاً سريعاً أن الملف PBF فعلاً مو صفحة HTML خطأ حُفظت باسم .pbf
_PBF_MAX_HEADER_LEN = 64 * 1024


def human(n: float) -> str:
    for unit in ("B", "KB", "MB", "GB"):
        if n < 1024:
            return f"{n:.1f}{unit}"
        n /= 1024.0
    return f"{n:.1f}TB"


def download_resumable(url: str, dest, force: bool = False) -> None:
    """ينزّل url إلى dest، ويكمل من حيث توقّف إن كان هناك جزء سابق."""
    if force:
        dest.unlink(missing_ok=True)
        dest.with_suffix(dest.suffix + ".part").unlink(missing_ok=True)

    if dest.exists() and dest.stat().st_size >= IRAQ_PBF_MIN_BYTES:
        print(f"  ✓ موجود مسبقاً: {dest.name} ({human(dest.stat().st_size)})")
        return

    tmp = dest.with_suffix(dest.suffix + ".part")
    have = tmp.stat().st_size if tmp.exists() else 0

    headers = {"Range": f"bytes={have}-"} if have else {}
    r = requests.get(url, headers=headers, stream=True, timeout=60)

    # 416 يعني طلبنا استئنافاً من بعد نهاية الملف — الجزء عندنا تالف
    if r.status_code == 416:
        print("  ◄ الجزء المحلي أطول من المصدر — نبدأ من الصفر")
        return download_resumable(url, dest, force=True)

    if r.status_code not in (200, 206):
        sys.exit(f"فشل التنزيل: HTTP {r.status_code} من {url}")

    # 200 على طلب Range يعني السيرفر ما يدعم الاستئناف، فالجزء السابق لا قيمة له
    if have and r.status_code == 200:
        print("  ◄ السيرفر ما يدعم الاستئناف — نبدأ من الصفر")
        have = 0

    total = int(r.headers.get("Content-Length", 0)) + have
    mode = "ab" if have else "wb"

    print(f"  ◄ تنزيل {human(total)}" + (f" (مستأنف من {human(have)})" if have else ""))
    t0 = time.time()
    done = have
    last_print = 0.0

    with open(tmp, mode) as f:
        for chunk in r.iter_content(_CHUNK):
            f.write(chunk)
            done += len(chunk)
            now = time.time()
            if now - last_print > 3.0:
                speed = (done - have) / max(now - t0, 0.1)
                pct = 100 * done / total if total else 0
                print(f"    {pct:5.1f}%  {human(done)} / {human(total)}"
                      f"  — {human(speed)}/s", flush=True)
                last_print = now

    size = tmp.stat().st_size
    if size < IRAQ_PBF_MIN_BYTES:
        sys.exit(f"الملف المنزّل صغير جداً ({human(size)}) — التنزيل ناقص أو "
                 f"المصدر تغيّر. امسح {tmp} وأعد المحاولة")

    with open(tmp, "rb") as f:
        header_len = int.from_bytes(f.read(4), "big")
    if not 0 < header_len < _PBF_MAX_HEADER_LEN:
        sys.exit(f"الملف المنزّل مو PBF صالح (طول الترويسة {header_len}) — "
                 f"يحتمل أن Geofabrik رجّع صفحة خطأ. امسح {tmp} وأعد المحاولة")

    tmp.replace(dest)
    print(f"  ✓ {dest.name} — {human(size)} في {time.time() - t0:.0f}s")


def clip_sample() -> None:
    """يقلّم bbox العيّنة من ملف العراق.

    ما نستخدم أداة osmium السطرية لأنها C++ منفصلة وما تتوفّر لويندوز بسهولة؛
    pyosmium عندها BackReferenceWriter يكمل المراجع تلقائياً وهو كل اللي نحتاجه:
    نضيف ما يقع داخل الـbbox، وهو يجيب عُقد الطرق المقطوعة على الحدود.
    """
    import osmium
    from osmium.osm import Box

    box = Box(*SAMPLE_BBOX)
    print(f"  ◄ تقليم {box}")

    # نتابع ما قبلناه لنقرّر العلاقات: في PBF ترتيب الأقسام عُقد ثم طرق ثم
    # علاقات، فحين نصل العلاقات نعرف أي طريق قبلناه — مرّة واحدة تكفي
    kept_nodes: set[int] = set()
    kept_ways: set[int] = set()
    n_rel = 0

    t0 = time.time()
    with osmium.BackReferenceWriter(str(SAMPLE_PBF), ref_src=str(IRAQ_PBF),
                                    overwrite=True) as writer:
        for obj in osmium.FileProcessor(str(IRAQ_PBF)).with_locations():
            if isinstance(obj, osmium.osm.Node):
                if box.contains(obj.location):
                    kept_nodes.add(obj.id)
                    writer.add_node(obj)

            elif isinstance(obj, osmium.osm.Way):
                # طريق يُقبل إذا لمس الـbbox بأي عقدة — نبي الطرق المقطوعة
                # كاملة لا منقوصة، وإلا انكسر رسم التوجيه على حدود العيّنة
                touches = any(
                    n.location.valid() and box.contains(n.location)
                    for n in obj.nodes
                )
                if touches:
                    kept_ways.add(obj.id)
                    writer.add_way(obj)

            else:
                # علاقة تُقبل إذا أي عضو منها مقبول — هكذا تدخل متعددات
                # الأضلاع (شطّ دجلة، المناطق السكنية) لا تُحذف من العيّنة
                if any((m.type == "w" and m.ref in kept_ways)
                       or (m.type == "n" and m.ref in kept_nodes)
                       for m in obj.members):
                    n_rel += 1
                    writer.add_relation(obj)

    print(f"  ✓ {SAMPLE_PBF.name} — {human(SAMPLE_PBF.stat().st_size)} "
          f"في {time.time() - t0:.0f}s")
    print(f"    قبلنا {len(kept_nodes):,} عقدة و {len(kept_ways):,} طريقاً "
          f"و {n_rel:,} علاقة (قبل إكمال المراجع)")


def count_features(pbf) -> dict[str, int]:
    """يعدّ العُقد والطرق والعلاقات، والطرق القابلة للسير منها."""
    import osmium

    counts = {"nodes": 0, "ways": 0, "relations": 0,
              "highways": 0, "named_highways": 0}

    for obj in osmium.FileProcessor(str(pbf)):
        if isinstance(obj, osmium.osm.Node):
            counts["nodes"] += 1
        elif isinstance(obj, osmium.osm.Way):
            counts["ways"] += 1
            if "highway" in obj.tags:
                counts["highways"] += 1
                if "name" in obj.tags or "name:ar" in obj.tags:
                    counts["named_highways"] += 1
        else:
            counts["relations"] += 1

    return counts


def report(name: str, pbf) -> None:
    s = count_features(pbf)
    named_pct = 100 * s["named_highways"] / s["highways"] if s["highways"] else 0
    print(f"\n  {name}:")
    print(f"    عُقد          {s['nodes']:>10,}")
    print(f"    طرق          {s['ways']:>10,}")
    print(f"    علاقات        {s['relations']:>10,}")
    print(f"    منها highway  {s['highways']:>10,}  "
          f"({s['named_highways']:,} مسمّى = {named_pct:.0f}%)")


def main() -> None:
    ap = argparse.ArgumentParser(description="تنزيل OSM العراق وتقليم عيّنة بغداد")
    ap.add_argument("--force", action="store_true",
                    help="أعد التنزيل من الصفر حتى لو الملف موجود")
    ap.add_argument("--skip-clip", action="store_true",
                    help="نزّل فقط بلا تقليم العيّنة")
    ap.add_argument("--skip-count", action="store_true",
                    help="لا تعدّ المعالم (العدّ يمرّ على الملف كاملاً)")
    args = ap.parse_args()

    ensure_dirs()

    print("─ المرحلة ٠١: بيانات OSM ─")
    print("\n١. تنزيل العراق")
    download_resumable(IRAQ_PBF_URL, IRAQ_PBF, force=args.force)

    if not args.skip_clip:
        print("\n٢. تقليم عيّنة بغداد")
        clip_sample()

    if not args.skip_count:
        print("\n٣. إحصاء")
        report("العراق", IRAQ_PBF)
        if SAMPLE_PBF.exists():
            report("بغداد (العيّنة)", SAMPLE_PBF)

    print("\n✓ المرحلة ٠١ تمّت. التالي: 02_build_tiles.py")


if __name__ == "__main__":
    main()
