# -*- coding: utf-8 -*-
"""المرحلة ٠٧: اختيار الحزمة التي تُشحن داخل التطبيق.

يقرأ: darb-data/tiles/*.mbtiles و darb-data/poi/pois.sqlite
ينتج: app/assets/data/ + تعديل app/lib/config.dart على الحزمة المختارة

المقايضة التي يحسمها هذا السكربت:

    بغداد   ~15MB  → حجم تطبيق معقول، وبقية العراق تُنزَّل لاحقاً
    العراق  ~211MB → يشتغل في كل محافظة من أول تشغيل بلا شبكة ولا استضافة

ليس قراراً تقنياً بل قرار توزيع: 211MB فوق حدّ Google Play للحزمة
الأساسية (150MB)، فالعراق كامل يعني توزيعاً مباشراً (APK) لا عبر المتجر.

    python 07_pack_assets.py baghdad     # الافتراضي
    python 07_pack_assets.py iraq
    python 07_pack_assets.py --status     # شنو مشحون الآن
"""

import re
import sys
import shutil
import argparse

from config import TILES_DIR, POI_DB, REPO_DIR

_ASSETS = REPO_DIR / "app" / "assets" / "data"
_APP_CONFIG = REPO_DIR / "app" / "lib" / "config.dart"

# حدّ Google Play للحزمة الأساسية. نطبعه حين تتجاوزه الحزمة كي لا
# يُكتشف عند الرفع
_PLAY_LIMIT_MB = 150


def human(n: float) -> str:
    for unit in ("B", "KB", "MB", "GB"):
        if n < 1024:
            return f"{n:.1f}{unit}"
        n /= 1024.0
    return f"{n:.1f}TB"


def available() -> dict[str, int]:
    return {p.stem: p.stat().st_size for p in sorted(TILES_DIR.glob("*.mbtiles"))}


def current_pack() -> str | None:
    """الحزمة المشحونة الآن حسب config.dart."""
    if not _APP_CONFIG.exists():
        return None
    m = re.search(r"bundledPack\s*=\s*'([^']+)'",
                  _APP_CONFIG.read_text(encoding="utf-8"))
    return m.group(1) if m else None


def show_status() -> None:
    print("─ حالة الحزم ─\n")
    print("المبنيّ في darb-data:")
    for name, size in available().items():
        print(f"    {name:<10} {human(size):>9}")

    print(f"\nقاعدة البحث:   {human(POI_DB.stat().st_size)}"
          if POI_DB.exists() else "\nقاعدة البحث:   غير موجودة")

    print(f"\nالمشحون الآن:  {current_pack() or '؟'}")

    if _ASSETS.exists():
        total = sum(f.stat().st_size for f in _ASSETS.glob("*"))
        for f in sorted(_ASSETS.glob("*")):
            print(f"    {f.name:<22} {human(f.stat().st_size):>9}")
        print(f"    {'المجموع':<22} {human(total):>9}")


def pack(name: str) -> None:
    tiles = TILES_DIR / f"{name}.mbtiles"
    if not tiles.exists():
        sys.exit(f"{tiles} غير موجود.\nابنِه أولاً:\n"
                 f"    python 02_build_tiles.py"
                 f"{' --full' if name == 'iraq' else ''}")
    if not POI_DB.exists():
        sys.exit(f"{POI_DB} غير موجود — شغّل 04_extract_pois.py")

    # قاعدة البحث واحدة لكل البناء الأخير، فننبّه لو ما تطابقت النطاقات.
    # شحن بلاطات العراق مع بحث بغداد يعطي خريطة كاملة وبحثاً أعمى في
    # الموصل، وهو خلل يصعب تشخيصه
    poi_mb = POI_DB.stat().st_size / 1024 / 1024
    if name == "iraq" and poi_mb < 15:
        print(f"  ⚠ قاعدة البحث {poi_mb:.1f}MB — تبدو مبنيّة على عيّنة بغداد "
              f"لا على العراق.\n    شغّل: python 04_extract_pois.py --full")
    if name != "iraq" and poi_mb > 15:
        print(f"  ⚠ قاعدة البحث {poi_mb:.1f}MB — تبدو مبنيّة على العراق "
              f"كامل.\n    هذا يشتغل، لكنه يكبّر التطبيق بلا فائدة.\n"
              f"    لبغداد وحدها: python 04_extract_pois.py")

    _ASSETS.mkdir(parents=True, exist_ok=True)
    for old in _ASSETS.glob("*.mbtiles"):
        print(f"  ◄ نمسح {old.name}")
        old.unlink()

    dest_tiles = _ASSETS / f"{name}.mbtiles"
    print(f"  ◄ نسخ {tiles.name} ({human(tiles.stat().st_size)})")
    shutil.copy2(tiles, dest_tiles)

    dest_poi = _ASSETS / "pois.sqlite"
    print(f"  ◄ نسخ pois.sqlite ({human(POI_DB.stat().st_size)})")
    shutil.copy2(POI_DB, dest_poi)

    _rewrite_config(name)

    total = dest_tiles.stat().st_size + dest_poi.stat().st_size
    print(f"\n  ✓ الحزمة «{name}» مشحونة — {human(total)}")

    total_mb = total / 1024 / 1024
    if total_mb > _PLAY_LIMIT_MB:
        print(f"\n  ⚠ {total_mb:.0f}MB فوق حدّ Google Play للحزمة الأساسية "
              f"({_PLAY_LIMIT_MB}MB).\n"
              f"    التوزيع لازم يكون APK مباشراً، أو تُنقل الحزمة لـ"
              f"asset delivery.")


def _rewrite_config(name: str) -> None:
    """يعدّل bundledPack و bundledTilesAsset في config.dart.

    تعديل نصّي لا توليد ملف: config.dart فيه تعليقات تشرح كل قيمة، وتوليده
    يمسحها. وسطران فقط يتغيّران.
    """
    text = _APP_CONFIG.read_text(encoding="utf-8")

    text, n1 = re.subn(r"(bundledPack\s*=\s*')[^']+(')",
                       rf"\g<1>{name}\g<2>", text)
    text, n2 = re.subn(r"(bundledTilesAsset\s*=\s*'assets/data/)[^']+(')",
                       rf"\g<1>{name}.mbtiles\g<2>", text)

    if n1 != 1 or n2 != 1:
        sys.exit(f"ما قدرنا نعدّل config.dart (طابقنا {n1} و{n2}) — "
                 f"عدّل bundledPack و bundledTilesAsset يدوياً")

    _APP_CONFIG.write_text(text, encoding="utf-8")
    print(f"  ◄ config.dart: bundledPack = '{name}'")


def main() -> None:
    ap = argparse.ArgumentParser(
        description="اختيار الحزمة المشحونة داخل التطبيق")
    ap.add_argument("name", nargs="?", default=None,
                    help="اسم الحزمة (baghdad أو iraq)")
    ap.add_argument("--status", action="store_true",
                    help="اعرض الحالة بلا تعديل")
    args = ap.parse_args()

    if args.status or args.name is None:
        show_status()
        if args.name is None and not args.status:
            print("\nللشحن:  python 07_pack_assets.py <اسم الحزمة>")
        return

    print(f"─ المرحلة ٠٧: شحن حزمة «{args.name}» ─\n")
    pack(args.name)
    print("\n  التالي: cd app && flutter build apk")


if __name__ == "__main__":
    main()
