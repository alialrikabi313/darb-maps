# -*- coding: utf-8 -*-
"""المرحلة ٠٥: جلب ملفات glyph العربية للخريطة.

يقرأ: لا شيء (المصدر من الشبكة).
ينتج: app/assets/fonts/<fontstack>/<range>.pbf

المشكلة التي يحلّها: MapLibre ما يرسم نصّاً من خطوط النظام — يبي glyph
مُسبَق التحويل لكل نطاق محارف. بلاها تظهر الخريطة بلا أي كتابة، ولا رسالة
خطأ تقول السبب. والخريطة أوفلاين فلا نقدر نشير لخدمة glyphs على الشبكة.

ليش نقتطع نطاقات بعينها: الحزمة الكاملة 59MB وفيها كل لغات العالم. العربية
واللاتينية وعلامات الترقيم ~1MB، والفرق يدخل حجم التطبيق مباشرة.

    python 05_fetch_fonts.py
"""

import io
import sys
import time
import shutil
import zipfile

import requests

from config import TOOLS_CACHE_DIR, REPO_DIR, ensure_dirs

_FONTS_URL = ("https://github.com/openmaptiles/fonts/releases/download/"
              "v2.0/noto-sans.zip")
_ZIP_PATH = TOOLS_CACHE_DIR / "noto-sans.zip"
_OUT_DIR = REPO_DIR / "app" / "assets" / "fonts"

# حزم الخطوط التي يستخدمها النمط. Regular للأسماء وBold لأسماء المدن
# والطرق الرئيسية — النمط يشير لهما بالاسم حرفياً فأي تغيير هنا يلزمه
# تغيير في darb-day.json
_STACKS = ("Noto Sans Regular", "Noto Sans Bold")

# نطاقات المحارف اللازمة. كل ملف 256 محرفاً.
_RANGES = (
    "0-255",        # لاتيني أساسي — الأسماء الإنجليزية والأرقام
    "256-511",      # لاتيني ممتد — أسماء منقولة بعلامات تشكيل
    "1536-1791",    # العربية
    "1792-2047",    # ملحق العربية والسريانية
    "8192-8447",    # علامات ترقيم عامة — «…» و«—» في الأسماء المقطوعة
    "64768-65023",  # أشكال العربية التقديمية أ
    "65024-65279",  # أشكال العربية التقديمية ب — اللامالف والتشكيل المركّب
)


def human(n: float) -> str:
    for unit in ("B", "KB", "MB", "GB"):
        if n < 1024:
            return f"{n:.1f}{unit}"
        n /= 1024.0
    return f"{n:.1f}TB"


def download() -> None:
    if _ZIP_PATH.exists() and _ZIP_PATH.stat().st_size > 40 << 20:
        print(f"  ✓ موجود مسبقاً ({human(_ZIP_PATH.stat().st_size)})")
        return

    print(f"  ◄ تنزيل noto-sans.zip (~59MB)")
    r = requests.get(_FONTS_URL, stream=True, timeout=120,
                     allow_redirects=True)
    if r.status_code != 200:
        sys.exit(f"فشل تنزيل الخطوط: HTTP {r.status_code}\n{_FONTS_URL}")

    tmp = _ZIP_PATH.with_suffix(".part")
    total = int(r.headers.get("Content-Length", 0))
    done = 0
    last = 0.0
    t0 = time.time()

    with open(tmp, "wb") as f:
        for chunk in r.iter_content(1 << 20):
            f.write(chunk)
            done += len(chunk)
            if time.time() - last > 3:
                pct = 100 * done / total if total else 0
                print(f"    {pct:5.1f}%  {human(done)}", flush=True)
                last = time.time()

    if tmp.stat().st_size < 40 << 20:
        tmp.unlink()
        sys.exit("الملف المنزّل صغير جداً — يحتمل أن الإصدار v2.0 ما عاد "
                 "موجوداً. افحص https://github.com/openmaptiles/fonts/releases")

    tmp.replace(_ZIP_PATH)
    print(f"  ✓ {human(_ZIP_PATH.stat().st_size)} في {time.time() - t0:.0f}s")


def extract() -> int:
    if _OUT_DIR.exists():
        shutil.rmtree(_OUT_DIR)
    _OUT_DIR.mkdir(parents=True)

    written = 0
    total_bytes = 0

    with zipfile.ZipFile(_ZIP_PATH) as z:
        names = set(z.namelist())

        for stack in _STACKS:
            dest = _OUT_DIR / stack
            dest.mkdir(parents=True, exist_ok=True)

            for rng in _RANGES:
                # مسار الحزمة فيه مجلد جذر يتغيّر بين الإصدارات، فنبحث
                # عن النهاية لا نبني المسار كاملاً
                tail = f"{stack}/{rng}.pbf"
                match = next((n for n in names if n.endswith(tail)), None)

                if match is None:
                    # نطاق مفقود ليس خطأً قاتلاً: الحزمة ما تحتوي نطاقاً
                    # خالياً من المحارف في هذا الخط. لكن نطبعه كي ما نكتشف
                    # لاحقاً أن نصّاً عربياً ما ظهر ونظن المشكلة في النمط
                    print(f"      (ناقص) {tail}")
                    continue

                data = z.read(match)
                (dest / f"{rng}.pbf").write_bytes(data)
                written += 1
                total_bytes += len(data)

    print(f"  ✓ {written} ملف glyph — {human(total_bytes)} في {_OUT_DIR}")
    return written


def verify() -> None:
    """يتأكد أن نطاق العربية موجود وغير فارغ لكل حزمة خط.

    هذا الفحص بالتحديد: نطاق 1536-1791 هو كل الحرف العربي. لو جاء فارغاً
    تظهر الخريطة بأسماء إنجليزية فقط، والسبب يُشخّص بصعوبة لأن النمط صحيح
    والبلاطات فيها name:ar.
    """
    for stack in _STACKS:
        f = _OUT_DIR / stack / "1536-1791.pbf"
        if not f.exists() or f.stat().st_size < 1000:
            sys.exit(f"نطاق العربية ناقص أو فارغ في «{stack}» — "
                     f"الخريطة راح تظهر بلا أسماء عربية")
        print(f"    ✓ {stack}: العربية {human(f.stat().st_size)}")


def main() -> None:
    ensure_dirs()
    print("─ المرحلة ٠٥: خطوط الخريطة ─")

    print("\n١. التنزيل")
    download()

    print("\n٢. الاقتطاع")
    extract()

    print("\n٣. الفحص")
    verify()

    print("\n✓ المرحلة ٠٥ تمّت. الخطوط في app/assets/fonts/")


if __name__ == "__main__":
    main()
