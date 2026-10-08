# -*- coding: utf-8 -*-
"""اختبار تقطيع الحزمة ولصقها.

هذا الاختبار يحمي العقد الذي يعتمد عليه التطبيق: لصق القطع بفهرس تصاعدي
يرجّع الملف الأصلي بايتاً ببايت. لو انكسر، يفتح sqflite قاعدة تالفة ويرمي
«database disk image is malformed» — خطأ يصعب ربطه بسببه.

يشتغل على الحزمة المشحونة فعلاً في app/assets/data، لا على بيانات
مخترَعة. إذا ما كانت مشحونة يُتخطّى.

    cd tools && python -m pytest tests/test_pack_chunks.py -v
"""

import sys
import json
import hashlib
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from config import REPO_DIR, TILES_DIR, POI_DB  # noqa: E402

_ASSETS = REPO_DIR / "app" / "assets" / "data"
_MANIFEST = _ASSETS / "manifest.json"

pytestmark = pytest.mark.skipif(
    not _MANIFEST.exists(),
    reason="ما في حزمة مشحونة — شغّل 07_pack_assets.py",
)


@pytest.fixture(scope="module")
def manifest() -> dict:
    return json.loads(_MANIFEST.read_text(encoding="utf-8"))


def _parts(name: str, count: int) -> list[Path]:
    return [_ASSETS / f"{name}.part{i:03d}" for i in range(count)]


def test_manifest_shape(manifest):
    assert manifest["pack"]
    assert len(manifest["files"]) == 2, "نتوقّع ملفين: بلاطات وبحث"
    for f in manifest["files"]:
        assert f["chunks"] >= 1
        assert f["size"] > 0
        assert len(f["sha256"]) == 64


def test_all_declared_parts_exist(manifest):
    # قطعة مفقودة من الأصول تعني لصقاً ناقصاً. pubspec يشحن المجلد كاملاً
    # فالنقص يصير بتعديل يدوي أو ببناء ناقص
    for f in manifest["files"]:
        for p in _parts(f["name"], f["chunks"]):
            assert p.exists(), f"{p.name} مفقودة"


def test_no_stray_parts(manifest):
    """ما في قطع زائدة من حزمة سابقة.

    صادفناه منطقياً: التبديل من بغداد للعراق يترك قطع بغداد لو ما مسحنا
    المجلد، فيكبر الـAPK بلا فائدة وقد يلصق التطبيق الغلط.
    """
    declared = set()
    for f in manifest["files"]:
        declared.update(p.name for p in _parts(f["name"], f["chunks"]))

    on_disk = {p.name for p in _ASSETS.glob("*.part*")}
    assert on_disk == declared, f"قطع زائدة: {sorted(on_disk - declared)}"


def test_parts_sum_to_declared_size(manifest):
    for f in manifest["files"]:
        total = sum(p.stat().st_size for p in _parts(f["name"], f["chunks"]))
        assert total == f["size"], f"{f['name']}: المجموع ما يطابق المُعلَن"


def test_chunk_sizes_respect_limit(manifest):
    """كل قطعة بحجم القطع أو أصغر (الأخيرة).

    الحدّ هو أعلى استهلاك ذاكرة أثناء اللصق على الجهاز — قطعة أكبر من
    المُعلَن تعيد مشكلة نفاد الذاكرة التي قطّعنا الملف لأجلها.
    """
    limit = manifest["chunk_bytes"]
    for f in manifest["files"]:
        parts = _parts(f["name"], f["chunks"])
        for p in parts[:-1]:
            assert p.stat().st_size == limit, f"{p.name} مو بحجم القطعة"
        assert parts[-1].stat().st_size <= limit


def test_concatenation_reproduces_original(manifest):
    """اللصق بفهرس تصاعدي يرجّع الملف الأصلي — العقد الذي يعتمده التطبيق."""
    sources = {
        "iraq.mbtiles": TILES_DIR / "iraq.mbtiles",
        "baghdad.mbtiles": TILES_DIR / "baghdad.mbtiles",
        "iraq.pois.sqlite": POI_DB,
        "baghdad.pois.sqlite": POI_DB,
    }

    for f in manifest["files"]:
        digest = hashlib.sha256()
        total = 0
        for p in _parts(f["name"], f["chunks"]):
            block = p.read_bytes()
            digest.update(block)
            total += len(block)

        assert total == f["size"]
        assert digest.hexdigest() == f["sha256"], \
            f"{f['name']}: اللصق ما يطابق هاش الأصل"

        # والمقارنة مع الملف المصدر نفسه إن كان موجوداً
        src = sources.get(f["name"])
        if src and src.exists():
            src_hash = hashlib.sha256(src.read_bytes()).hexdigest()
            assert src_hash == digest.hexdigest(), \
                f"{f['name']}: الملصوق يختلف عن {src.name}"


def test_assembled_db_opens(manifest):
    """الملف الملصوق قاعدة SQLite صالحة فعلاً.

    الهاش يثبت تطابق البايتات، وهذا يثبت أن البايتات قاعدة يفتحها
    sqflite — وهو ما يسويه التطبيق بعد اللصق مباشرة.
    """
    import sqlite3
    import tempfile

    for f in manifest["files"]:
        with tempfile.NamedTemporaryFile(suffix=".sqlite",
                                         delete=False) as tmp:
            for p in _parts(f["name"], f["chunks"]):
                tmp.write(p.read_bytes())
            path = tmp.name

        try:
            con = sqlite3.connect(path)

            if f["name"].endswith(".mbtiles"):
                # نفحص أن tiles يُستعلَم منها لا أنها «جدول»: Planetiler
                # يبني للمجموعات الكبيرة tiles_shallow + tiles_data مع
                # tiles كـview (إزالة تكرار البلاطات المتطابقة — وهي
                # كثيرة في صحراء العراق). حزمة بغداد الصغيرة جاءت جدولاً
                # عادياً. التطبيق يقرأ من tiles فيشتغل على الاثنين،
                # واختبار يفحص type='table' يسقط على العراق وحده
                n, = con.execute("SELECT COUNT(*) FROM tiles").fetchone()
                assert n > 0, "جدول البلاطات فارغ"

                meta = dict(con.execute(
                    "SELECT name, value FROM metadata").fetchall())
                assert meta.get("format") == "pbf"

                # وبلاطة واحدة فعلية تُقرأ وتبدأ بعلامة gzip
                blob, = con.execute(
                    "SELECT tile_data FROM tiles LIMIT 1").fetchone()
                assert blob[:2] == b"\x1f\x8b", \
                    "البلاطة مو مضغوطة gzip — ترويسة السيرفر راح تكون غلط"
            else:
                tables = {r[0] for r in con.execute(
                    "SELECT name FROM sqlite_master "
                    "WHERE type IN ('table','view')")}
                assert "poi" in tables and "search_meta" in tables

                n, = con.execute("SELECT COUNT(*) FROM poi").fetchone()
                assert n > 0, "قاعدة البحث فارغة"
                # فهرس FTS لازم يرد على استعلام فعلي
                con.execute(
                    'SELECT COUNT(*) FROM poi_fts WHERE poi_fts MATCH "بغداد"'
                ).fetchone()

            con.close()
        finally:
            Path(path).unlink(missing_ok=True)
