# -*- coding: utf-8 -*-
"""المرحلة ٠٦: فحص السلسلة كاملة من طرف لطرف.

يقرأ: الباكند على 8080 وValhalla على 8002 وقاعدة البلاطات ونقاط الاهتمام.
ينتج: تقريراً على الشاشة، ويموت بخطأ واضح عند أول فشل.

ما يفحصه بالترتيب:
  ١. البلاطات: بلاطة بغداد موجودة وبصيغة صحيحة
  ٢. البحث: حالات عربية حقيقية ترجّع نتائج
  ٣. Valhalla: مسار بغدادي بأسماء شوارع
  ٤. الباكند: تسجيل جهاز، بلاغ، تجميع، تصويت، إغلاق
  ٥. الزحام: إرسال رحلة مجهولة ومطابقتها على الطرق
  ٦. الخصوصية: قصّ أطراف الرحلة يشتغل فعلاً

شغّله بعد أي تعديل على الباكند أو السكربتات.

    python 06_smoke_test.py
"""

import sys
import time
import json
import sqlite3
import argparse

import requests

from config import (
    API_URL, VALHALLA_URL, TILES_DIR, POI_DB, SAMPLE_NAME, MAP_START_CENTER,
    TILE_MAX_ZOOM, REPORT_TYPES, TRACE_TRIM_ENDPOINTS_M, REPO_DIR,
    ROAD_CANDIDATE_PROMOTE_HITS,
)

# نقاط بغدادية حقيقية نستخدمها في كل الفحوص
_TAHRIR = (33.3074, 44.4009)
_MANSOUR = (33.3094, 44.3384)
_AIRPORT = (33.2625, 44.2346)

_passed: list[str] = []
_warned: list[str] = []


def ok(label: str, detail: str = "") -> None:
    _passed.append(label)
    print(f"    ✓ {label}" + (f" — {detail}" if detail else ""))


def warn(label: str, detail: str) -> None:
    """شيء ناقص لكن ما يمنع عمل التطبيق. نجمعها ونعرضها بالآخر."""
    _warned.append(f"{label}: {detail}")
    print(f"    ⚠ {label} — {detail}")


def die(label: str, detail: str) -> None:
    print(f"    ✗ {label} — {detail}")
    sys.exit(f"\nفشل الفحص عند «{label}». لا تكمل قبل إصلاحه.")


# ── ١. البلاطات ────────────────────────────────────────────────────────────

def check_tiles() -> None:
    path = TILES_DIR / f"{SAMPLE_NAME}.mbtiles"
    if not path.exists():
        die("البلاطات", f"{path} غير موجود — شغّل 02_build_tiles.py")

    con = sqlite3.connect(path)
    meta = dict(con.execute("SELECT name, value FROM metadata").fetchall())

    if meta.get("format") != "pbf":
        die("صيغة البلاطات", f"توقّعنا pbf وجاء {meta.get('format')}")
    if meta.get("compression") != "gzip":
        # السيرفر المحلي يفحص علامة gzip بنفسه فما ينكسر، لكن الترويسة
        # تتغيّر فننبّه
        warn("ضغط البلاطات", f"توقّعنا gzip وجاء {meta.get('compression')}")

    total, = con.execute("SELECT COUNT(*) FROM tiles").fetchone()
    ok("البلاطات", f"{total:,} بلاطة، صيغة {meta['format']}")

    # بلاطة مركز الخريطة: بلاها يفتح التطبيق على شاشة رمادية
    import math
    lon, lat = MAP_START_CENTER
    n = 2 ** TILE_MAX_ZOOM
    x = int((lon + 180.0) / 360.0 * n)
    y = int((1.0 - math.asinh(math.tan(math.radians(lat))) / math.pi) / 2.0 * n)
    row = con.execute(
        "SELECT LENGTH(tile_data) FROM tiles WHERE zoom_level=? AND "
        "tile_column=? AND tile_row=?",
        (TILE_MAX_ZOOM, x, n - 1 - y)).fetchone()

    if not row or not row[0]:
        die("بلاطة ساحة التحرير", f"مفقودة في z{TILE_MAX_ZOOM}")
    ok("بلاطة ساحة التحرير", f"{row[0] / 1024:.1f}KB في z{TILE_MAX_ZOOM}")
    con.close()


# ── ١ب. النمط ──────────────────────────────────────────────────────────────

def check_style() -> None:
    """يطابق نمط الخريطة مع البلاطات والخطوط الموجودة فعلاً.

    ليش هذا الفحص: ثلاثة أخطاء لا تُكتشف إلا على الجهاز وتظهر كخريطة
    «تشتغل» وهي ناقصة — طبقة تشير لـsource-layer غير موجود فتبقى فارغة،
    ونصّ يطلب حزمة خط ما شحنّاها فيختفي، وعلامة {{TILE_BASE}} تبقى في
    النمط فما تُحمَّل أي بلاطة. ولا واحد منها يرمي خطأ.
    """
    style_path = (REPO_DIR / "app" / "assets" / "style" / "darb-day.json")
    if not style_path.exists():
        die("النمط", f"{style_path} غير موجود")

    style = json.loads(style_path.read_text(encoding="utf-8"))

    # العلامة لازم تكون موجودة: السيرفر يزرع مكانها عنوانه وقت التشغيل
    raw = style_path.read_text(encoding="utf-8")
    if "{{TILE_BASE}}" not in raw:
        die("علامة النمط", "{{TILE_BASE}} مفقودة — النمط فيه عنوان مكتوب "
                           "بيده، والمنفذ عشوائي فما راح يطابقه")

    # طبقات البلاطات الموجودة فعلاً
    tiles_db = TILES_DIR / f"{SAMPLE_NAME}.mbtiles"
    con = sqlite3.connect(tiles_db)
    meta_json = con.execute(
        "SELECT value FROM metadata WHERE name='json'").fetchone()[0]
    con.close()
    available = {L["id"] for L in json.loads(meta_json)["vector_layers"]}

    used_layers = {l["source-layer"] for l in style["layers"]
                   if "source-layer" in l}
    missing = used_layers - available
    if missing:
        die("طبقات النمط",
            f"النمط يشير لطبقات غير موجودة في البلاطات: {sorted(missing)}")
    ok("طبقات النمط", f"{len(used_layers)} طبقة كلها موجودة في البلاطات")

    # طبقات موجودة وما نستخدمها: ليس خطأً، لكنه يعني تفاصيل مبنيّة
    # وغير معروضة — بلاطات أكبر بلا فائدة
    unused = available - used_layers
    if unused:
        warn("طبقات غير مستخدمة",
             f"مبنيّة في البلاطات وما يرسمها النمط: {sorted(unused)}")

    # حزم الخطوط التي يطلبها النمط لازم تكون مشحونة
    fonts_dir = REPO_DIR / "app" / "assets" / "fonts"
    wanted: set[str] = set()
    for layer in style["layers"]:
        for font in (layer.get("layout", {}) or {}).get("text-font", []):
            wanted.add(font)

    for font in sorted(wanted):
        arabic = fonts_dir / font / "1536-1791.pbf"
        if not arabic.exists():
            die("خطوط النمط",
                f"النمط يطلب «{font}» وما شحنّا نطاق العربية له — "
                f"الكتابة العربية راح تختفي من الخريطة.\n"
                f"    عدّل _STACKS في 05_fetch_fonts.py وأعد تشغيله")
        ok(f"خط «{font}»", f"العربية {arabic.stat().st_size / 1024:.0f}KB")

    # الأسماء العربية: كل طبقة نصّ لازم تفضّل name:ar
    text_layers = [l for l in style["layers"] if l.get("type") == "symbol"]
    without_ar = [
        l["id"] for l in text_layers
        if "name:ar" not in json.dumps(
            (l.get("layout", {}) or {}).get("text-field", ""),
            ensure_ascii=False)
    ]
    if without_ar:
        warn("أسماء غير معرَّبة",
             f"طبقات نصّ ما تفضّل name:ar: {without_ar}")
    else:
        ok("تعريب الأسماء", f"{len(text_layers)} طبقة نصّ كلها تفضّل name:ar")


# ── ٢. البحث ───────────────────────────────────────────────────────────────

# حالات صادفناها في بيانات بغداد — كل واحدة تختبر قاعدة تطبيع مختلفة
_SEARCH_CASES = [
    ("يرموك", "كلمة من داخل الاسم"),
    ("كاظمية", "بلا «ال»"),
    ("جامعه بغداد", "تاء مربوطة مكتوبة هاء + كلمتان"),
    ("مطار بغداد", "اسم مركّب"),
    ("الكرادة", "منطقة"),
]


def check_search() -> None:
    if not POI_DB.exists():
        die("البحث", f"{POI_DB} غير موجود — شغّل 04_extract_pois.py")

    sys.path.insert(0, str(POI_DB.parent))
    import importlib
    mod = importlib.import_module("04_extract_pois")

    con = sqlite3.connect(POI_DB)
    total, = con.execute("SELECT COUNT(*) FROM poi").fetchone()
    ok("قاعدة البحث", f"{total:,} نقطة")

    for query, why in _SEARCH_CASES:
        hits = mod.search(con, query, limit=3)
        if not hits:
            die(f"بحث «{query}»", f"صفر نتائج ({why})")
        top = hits[0][1] or hits[0][2]
        ok(f"بحث «{query}»", f"{top} ({why})")

    # قواعد التطبيع لازم تكون في القاعدة ليقرأها التطبيق
    meta = dict(con.execute("SELECT key, value FROM search_meta").fetchall())
    for key in ("normalize_map", "strip_chars", "stop_prefixes"):
        if key not in meta:
            die("قواعد التطبيع", f"المفتاح «{key}» ناقص في search_meta — "
                                 f"بحث التطبيق راح يطبّع غير ما فُهرس به")
    ok("قواعد التطبيع", f"{len(json.loads(meta['normalize_map']))} حرفاً مُطبَّعاً")
    con.close()


# ── ٣. Valhalla ────────────────────────────────────────────────────────────

def check_valhalla() -> None:
    try:
        r = requests.get(f"{VALHALLA_URL}/status", timeout=8)
    except requests.RequestException as e:
        die("Valhalla", f"ما وصلنا {VALHALLA_URL} — {e}")

    if r.status_code != 200:
        die("Valhalla", f"HTTP {r.status_code}")

    body = {"locations": [{"lat": _TAHRIR[0], "lon": _TAHRIR[1]},
                          {"lat": _AIRPORT[0], "lon": _AIRPORT[1]}],
            "costing": "auto"}
    r = requests.post(f"{VALHALLA_URL}/route", json=body, timeout=25)
    if r.status_code != 200:
        die("مسار ڤالهالا", f"HTTP {r.status_code} — {r.text[:150]}")

    trip = r.json()["trip"]
    km = trip["summary"]["length"]
    legs = trip["legs"][0]

    # المسار المعروف: ساحة التحرير ← مطار بغداد ≈ 24 كم. رقم بعيد عن هذا
    # يعني رسماً مبنياً غلط أو مقلوب الإحداثيات
    if not 15 < km < 40:
        die("مسار التحرير ← المطار", f"{km:.1f} كم — خارج المدى المعقول")

    named = [m for m in legs["maneuvers"] if m.get("street_names")]
    if not named:
        die("أسماء الشوارع", "ولا مناورة فيها اسم شارع — الرسم بلا أسماء")

    ok("مسار التحرير ← المطار",
       f"{km:.1f} كم، {len(legs['maneuvers'])} مناورة، "
       f"{len(named)} منها مسمّاة")

    # polyline6 لا polyline5: نفكّ أول نقطة ونتأكد أنها في بغداد
    shape = legs["shape"]
    lat, lon = _decode_first(shape)
    if not (32.9 < lat < 33.7 and 44.0 < lon < 44.8):
        die("ترميز الخط", f"أول نقطة ({lat:.4f}, {lon:.4f}) خارج بغداد — "
                          f"يحتمل أن القاسم غلط (1e5 بدل 1e6)")
    ok("ترميز الخط polyline6", f"أول نقطة ({lat:.4f}, {lon:.4f})")


def _decode_first(enc: str) -> tuple[float, float]:
    i = lat = lon = 0
    for which in range(2):
        shift = result = 0
        while True:
            b = ord(enc[i]) - 63
            i += 1
            result |= (b & 0x1f) << shift
            shift += 5
            if b < 0x20:
                break
        dv = ~(result >> 1) if result & 1 else result >> 1
        if which == 0:
            lat += dv
        else:
            lon += dv
    return lat / 1e6, lon / 1e6


# ── ٤. الباكند ─────────────────────────────────────────────────────────────

def check_backend() -> dict:
    try:
        r = requests.get(f"{API_URL}/health", timeout=8)
    except requests.RequestException as e:
        die("الباكند", f"ما وصلنا {API_URL} — {e}\n"
                       f"شغّله: cd server && .venv/Scripts/python -m uvicorn "
                       f"app.main:app --port 8080")
    if r.status_code != 200:
        die("الباكند", f"/health رجّع {r.status_code}")
    ok("الباكند", json.dumps(r.json(), ensure_ascii=False))

    # أنواع البلاغات لازم تطابق config.py — التطبيق يبني قائمته منها
    types = requests.get(f"{API_URL}/reports/types", timeout=8).json()
    if set(types) != set(REPORT_TYPES):
        die("أنواع البلاغات", f"السيرفر يرجّع {len(types)} والإعدادات فيها "
                              f"{len(REPORT_TYPES)}")
    ok("أنواع البلاغات", f"{len(types)} نوعاً")

    dev1 = requests.post(f"{API_URL}/auth/device", timeout=8).json()
    dev2 = requests.post(f"{API_URL}/auth/device", timeout=8).json()
    if dev1["device_id"] == dev2["device_id"]:
        die("تسجيل الجهاز", "جهازان مختلفان أخذا نفس المعرّف")
    ok("تسجيل الجهاز", f"جهازان، التوكن {len(dev1['token'])} حرفاً")

    h1 = {"authorization": f"Bearer {dev1['token']}"}
    h2 = {"authorization": f"Bearer {dev2['token']}"}

    # بلا توكن لازم يُرفض: بلاغ مجهول المصدر ما نقدر نسحبه ولا نحسب سمعته
    r = requests.post(f"{API_URL}/reports",
                      json={"kind": "crash", "lat": _TAHRIR[0],
                            "lon": _TAHRIR[1]}, timeout=8)
    if r.status_code != 401:
        die("حماية الإبلاغ", f"بلاغ بلا توكن رجّع {r.status_code} لا 401")
    ok("حماية الإبلاغ", "البلاغ بلا توكن مرفوض")

    # نوع مجهول لازم يُرفض برسالة تسمّي المتاح
    r = requests.post(f"{API_URL}/reports", headers=h1,
                      json={"kind": "ufo", "lat": _TAHRIR[0],
                            "lon": _TAHRIR[1]}, timeout=8)
    if r.status_code != 422:
        die("فحص نوع البلاغ", f"نوع مجهول رجّع {r.status_code} لا 422")
    ok("فحص نوع البلاغ", "النوع المجهول مرفوض")

    return {"dev1": dev1, "dev2": dev2, "h1": h1, "h2": h2}


def check_reports(ctx: dict) -> None:
    h1, h2 = ctx["h1"], ctx["h2"]

    rep = requests.post(f"{API_URL}/reports", headers=h1,
                        json={"kind": "crash", "lat": _TAHRIR[0],
                              "lon": _TAHRIR[1], "heading": 90,
                              "note": "فحص آلي"}, timeout=8).json()
    ok("إنشاء بلاغ", f"id={rep['id']}، ثقة {rep['confidence']}")

    # صاحب البلاغ ما يصوّت على بلاغه
    r = requests.post(f"{API_URL}/reports/{rep['id']}/vote", headers=h1,
                      json={"is_up": True}, timeout=8)
    if r.status_code != 409:
        die("تصويت صاحب البلاغ", f"رجّع {r.status_code} لا 409")
    ok("تصويت صاحب البلاغ", "مرفوض")

    voted = requests.post(f"{API_URL}/reports/{rep['id']}/vote", headers=h2,
                          json={"is_up": True}, timeout=8).json()
    if voted["up_votes"] != 2:
        die("التصويت", f"توقّعنا صوتين وجاء {voted['up_votes']}")
    if not voted["confirmed"]:
        die("التأكيد", f"crash يحتاج "
                       f"{REPORT_TYPES['crash']['votes_to_confirm']} أصوات "
                       f"وصار عنده {voted['up_votes']} وما تأكّد")
    ok("التصويت والتأكيد", f"{voted['up_votes']} أصوات، مؤكّد")

    # صوت ثانٍ من نفس الجهاز مرفوض — القيد في القاعدة لا في الكود
    r = requests.post(f"{API_URL}/reports/{rep['id']}/vote", headers=h2,
                      json={"is_up": True}, timeout=8)
    if r.status_code != 409:
        die("التصويت المكرّر", f"رجّع {r.status_code} لا 409")
    ok("التصويت المكرّر", "مرفوض")

    # التجميع: بلاغ ثانٍ من نفس النوع على بعد ~30 متراً
    near = {"kind": "crash", "lat": _TAHRIR[0] + 0.00027,
            "lon": _TAHRIR[1], "note": "نفس الحادث"}
    requests.post(f"{API_URL}/reports", headers=h2, json=near, timeout=8)

    found = requests.get(f"{API_URL}/reports/near",
                         params={"lat": _TAHRIR[0], "lon": _TAHRIR[1],
                                 "radius_m": 500}, timeout=8).json()
    crashes = [r_ for r_ in found if r_["kind"] == "crash"]
    if not crashes:
        die("البلاغات حولي", "ما رجّع البلاغ اللي أنشأناه قبل سطرين")
    if crashes[0]["cluster_size"] < 2:
        die("تجميع البلاغات", f"بلاغان على بعد 30م رجعوا "
                              f"{len(crashes)} مجموعة بحجم "
                              f"{crashes[0]['cluster_size']}")
    ok("تجميع البلاغات", f"بلاغان على 30م = مجموعة واحدة بحجم "
                         f"{crashes[0]['cluster_size']}")

    # الفلترة بالاتجاه: بلاغ باتجاه 90 ما يظهر لسائق باتجاه 270
    opposite = requests.get(f"{API_URL}/reports/near",
                            params={"lat": _TAHRIR[0], "lon": _TAHRIR[1],
                                    "radius_m": 500, "heading": 270},
                            timeout=8).json()
    directed = [r_ for r_ in opposite if r_.get("heading") == 90]
    if directed:
        die("فلترة الاتجاه", "بلاغ باتجاه 90 ظهر لسائق باتجاه 270")
    ok("فلترة الاتجاه", "البلاغ الموجّه ما يظهر للجهة المعاكسة")

    # الإغلاق المؤكّد يدخل حساب المسار — نضعه على المسار نفسه لا على أي
    # نقطة، وإلا كان الفحص يمرّ بلا ما يتحقق من شي
    on_route = _point_on_route()
    closed = requests.post(
        f"{API_URL}/reports", headers=h1,
        json={"kind": "road_closed", "lat": on_route[0],
              "lon": on_route[1]}, timeout=8).json()

    # road_closed يحتاج 3 أصوات. البلاغ يبدأ بصوت صاحبه، فنحتاج صوتين
    # إضافيين من جهازين مختلفين — جهاز واحد صوته واحد
    need = REPORT_TYPES["road_closed"]["votes_to_confirm"]
    for _ in range(need - 1):
        token = requests.post(f"{API_URL}/auth/device", timeout=8).json()
        requests.post(f"{API_URL}/reports/{closed['id']}/vote",
                      headers={"authorization": f"Bearer {token['token']}"},
                      json={"is_up": True}, timeout=8)

    state = requests.get(f"{API_URL}/reports/near",
                         params={"lat": on_route[0], "lon": on_route[1],
                                 "radius_m": 200}, timeout=8).json()
    closures = [r_ for r_ in state if r_["kind"] == "road_closed"]
    if not closures or not closures[0]["confirmed"]:
        die("تأكيد الإغلاق",
            f"بعد {need} أصوات ما تأكّد بلاغ الإغلاق")

    ctx["closure_point"] = on_route
    ok("تأكيد الإغلاق", f"id={closed['id']}، {need} أصوات من أجهزة مختلفة")


def _point_on_route() -> tuple[float, float]:
    """نقطة تقع فعلاً على مسار التحرير ← المنصور.

    نأخذها من منتصف خط ڤالهالا لا نخترعها: الإغلاق على نقطة مجاورة
    للطريق لا يؤثّر على حساب المسار، فكان الفحص يمرّ بلا معنى.
    """
    body = {"locations": [{"lat": _TAHRIR[0], "lon": _TAHRIR[1]},
                          {"lat": _MANSOUR[0], "lon": _MANSOUR[1]}],
            "costing": "auto"}
    shape = requests.post(f"{VALHALLA_URL}/route", json=body,
                          timeout=25).json()["trip"]["legs"][0]["shape"]
    pts = _decode_all(shape)
    return pts[len(pts) // 2]


# ── ٥. التوجيه عبر الباكند ─────────────────────────────────────────────────

def check_routing(ctx: dict) -> None:
    r = requests.post(f"{API_URL}/route",
                      json={"locations": [
                          {"lat": _TAHRIR[0], "lon": _TAHRIR[1]},
                          {"lat": _MANSOUR[0], "lon": _MANSOUR[1]}],
                          "alternates": 2}, timeout=30)
    if r.status_code != 200:
        die("التوجيه عبر الباكند", f"HTTP {r.status_code} — {r.text[:200]}")

    data = r.json()
    trip = data["trip"]
    km = trip["summary"]["length"]
    alts = len(data.get("alternates", []))

    # الإغلاق المؤكّد لازم يُحقن في الطلب. صفر هنا يعني أن سلسلة
    # بلاغ ← تأكيد ← road_closure ← exclude_polygons مقطوعة في مكان ما
    if data["closures_avoided"] < 1:
        die("حقن الإغلاقات",
            "أكّدنا إغلاقاً على هذا المسار وحساب المسار تجنّب صفر إغلاق — "
            "افحص جدول road_closure ومزامنته في routers/reports.py")

    ok("التوجيه عبر الباكند",
       f"{km:.1f} كم، {alts} بديلاً، تجنّبنا "
       f"{data['closures_avoided']} إغلاقاً")

    # المسار لازم يبتعد عن نقطة الإغلاق: التجنّب الحقيقي لا مجرد حقن
    # المضلّع في الطلب
    closure = ctx.get("closure_point")
    if closure:
        pts = _decode_all(trip["legs"][0]["shape"])
        nearest = min(
            abs(la - closure[0]) * 111320 + abs(lo - closure[1]) * 93000
            for la, lo in pts)
        if nearest < 40:
            warn("تجنّب الإغلاق",
                 f"المسار يمرّ على {nearest:.0f}م من نقطة الإغلاق — "
                 f"ربما ما في بديل، وربما المضلّع صغير جداً")
        else:
            ok("تجنّب الإغلاق",
               f"المسار يبتعد {nearest:.0f}م عن نقطة الإغلاق")

    # معرّفات الطرق: بلاها ما في تلوين زحام ولا حدّ سرعة. نفحصها صراحةً
    # لأن غيابها يمرّ صامتاً — المسار يشتغل والميزتان تختفيان
    maneuvers = trip["legs"][0]["maneuvers"]
    with_ways = [m for m in maneuvers if m.get("way_ids")]
    if not with_ways:
        die("معرّفات طرق المسار",
            "ولا مناورة فيها way_ids — مطابقة المسار على الطرق فشلت، "
            "فما راح يشتغل تلوين الزحام ولا حدّ السرعة")
    ok("معرّفات طرق المسار",
       f"{len(with_ways)}/{len(maneuvers)} مناورة")

    with_limit = [m for m in maneuvers if m.get("speed_limit")]
    if with_limit:
        ok("حدود السرعة",
           f"{len(with_limit)}/{len(maneuvers)} مناورة — "
           f"{sorted({int(m['speed_limit']) for m in with_limit})} كم/س")
    else:
        # ناقصة في أكثر طرق العراق. ما نموت عليها — نعرضها حين توجد
        warn("حدود السرعة", "ما في maxspeed على هذا المسار في OSM")

    traffic = trip.get("traffic", {})
    if traffic.get("available"):
        ok("الزحام على المسار",
           f"تغطية {int(traffic['coverage'] * 100)}%، "
           f"أضاف {traffic['added_seconds']}s")
    else:
        # الصراحة مقصودة — خط ملوّن بتخمين أسوأ من خط بلا لون
        ok("إعلان غياب الزحام",
           f"«{traffic.get('reason', '؟')}» — صريح لا مخمَّن")


# ── ٦. الزحام والخصوصية ────────────────────────────────────────────────────

def check_traffic() -> None:
    # رحلة اصطناعية على طريق حقيقي: نولّدها من خط مسار ڤالهالا نفسه كي
    # تنطبق على طرق موجودة. رحلة بإحداثيات عشوائية ما تطابق شيئاً
    body = {"locations": [{"lat": _TAHRIR[0], "lon": _TAHRIR[1]},
                          {"lat": _MANSOUR[0], "lon": _MANSOUR[1]}],
            "costing": "auto"}
    shape = requests.post(f"{VALHALLA_URL}/route", json=body,
                          timeout=25).json()["trip"]["legs"][0]["shape"]
    pts = _decode_all(shape)

    now = time.time()
    trace = [{"lat": la, "lon": lo, "time": now + i * 2, "speed_kmh": 18.0}
             for i, (la, lo) in enumerate(pts[:60])]

    r = requests.post(f"{API_URL}/traffic/trace", json={"points": trace},
                      timeout=25)
    if r.status_code != 202:
        die("إرسال رحلة", f"HTTP {r.status_code} — {r.text[:200]}")

    res = r.json()
    if res["stored"] == 0:
        warn("مطابقة الرحلة", f"ما خزّنّا أي قراءة — {res.get('reason', '')}")
    else:
        ok("إرسال رحلة مجهولة",
           f"{res['stored']} قراءة على {res['matched_edges']} قطعة طريق")

    # الخصوصية: رحلة أقصر من قصّ الأطراف لازم تُحذف كاملة
    tiny = [{"lat": _TAHRIR[0] + i * 0.00005, "lon": _TAHRIR[1],
             "time": now + i, "speed_kmh": 10.0} for i in range(8)]
    r = requests.post(f"{API_URL}/traffic/trace", json={"points": tiny},
                      timeout=15).json()
    if r["stored"] != 0:
        die("قصّ أطراف الرحلة",
            f"رحلة طولها ~45م خزّنت {r['stored']} قراءة — "
            f"المفروض تُحذف كاملة لأن أقل من "
            f"{TRACE_TRIM_ENDPOINTS_M}م كلها «قرب البيت»")
    ok("قصّ أطراف الرحلة", "الرحلة القصيرة تُحذف كاملة")

    # التجميع ثم التلوين: نرسل رحلة بطيئة مراراً لنتجاوز عتبة
    # TRAFFIC_MIN_SAMPLES، ثم نتأكد أن المسار يتلوّن فعلاً ويرتفع زمنه.
    # بلا هذا كان الفحص يمرّ على حالة «ما عندنا قراءات» ولا يختبر الميزة
    slow = [{"lat": la, "lon": lo, "time": now + i * 4 + 900,
             "speed_kmh": 8.0}
            for i, (la, lo) in enumerate(pts[:80])]
    for _ in range(3):
        requests.post(f"{API_URL}/traffic/trace", json={"points": slow},
                      timeout=30)

    agg = requests.post(f"{API_URL}/traffic/aggregate", timeout=20).json()
    ok("تجميع الزحام",
       f"حدّثنا {agg['updated']} قطعة، نسينا {agg['forgotten']}")

    if agg["updated"] == 0:
        warn("تلوين المسار", "ما تجمّعت قطع — نتخطّى فحص التلوين")
        return

    colored = requests.post(f"{API_URL}/route", json={
        "locations": [{"lat": _TAHRIR[0], "lon": _TAHRIR[1]},
                      {"lat": _MANSOUR[0], "lon": _MANSOUR[1]}],
        "alternates": 0}, timeout=40).json()["trip"]

    traffic = colored.get("traffic", {})
    if not traffic.get("available"):
        die("تلوين المسار بالزحام",
            f"جمّعنا {agg['updated']} قطعة والمسار يقول "
            f"«{traffic.get('reason')}» — السلسلة مقطوعة بين "
            f"traffic_state ومعرّفات طرق المسار")

    levels = [m.get("traffic_level")
              for m in colored["legs"][0]["maneuvers"]
              if m.get("traffic_level")]
    base = colored["summary"]["time"]
    withjam = colored["summary"].get("time_with_traffic", base)

    if withjam <= base:
        die("تصحيح الـETA",
            f"المسار ملوّن بـ{levels} والزمن ما تغيّر ({base}s)")

    ok("تلوين المسار بالزحام",
       f"{len(levels)} مناورة ملوّنة، تغطية "
       f"{int(traffic['coverage'] * 100)}%")
    ok("تصحيح الـETA بالزحام",
       f"{round(base / 60)} دقيقة → {round(withjam / 60)} دقيقة")

    check_road_candidates(pts, now)
    check_long_route()


def check_long_route() -> None:
    """مسار بين محافظتين — يكشف حدود المطابقة.

    انهار فعلاً قبل الإصلاح: 1200 نقطة من مسار البصرة ← دهوك = 284 كم،
    وValhalla يرفض /trace_attributes فوق حدّ المسافة (error_code 154).
    فكانت المسارات الطويلة تفقد حدود السرعة وتلوين الزحام كلياً وصامتاً
    — المسار يصل سليماً والميزتان تختفيان.
    """
    r = requests.post(f"{API_URL}/route", json={
        "locations": [{"lat": 30.5085, "lon": 47.7804},   # البصرة
                      {"lat": 36.8670, "lon": 42.9880}],  # دهوك
        "alternates": 0}, timeout=180)

    if r.status_code != 200:
        die("مسار بين محافظتين", f"HTTP {r.status_code} — {r.text[:150]}")

    trip = r.json()["trip"]
    km = trip["summary"]["length"]
    maneuvers = trip["legs"][0]["maneuvers"]
    with_ways = [m for m in maneuvers if m.get("way_ids")]
    traffic = trip.get("traffic", {})

    if km < 800:
        die("مسار البصرة ← دهوك", f"{km:.0f} كم — أقصر من المعقول")

    if not with_ways:
        die("مطابقة المسار الطويل",
            f"مسار {km:.0f} كم وصفر مناورة لها معرّفات طرق — "
            f"المطابقة تجاوزت حدّ مسافة ڤالهالا. افحص _MAX_TRACE_KM")

    frac = traffic.get("matched_fraction")
    if frac is None:
        die("إعلان نسبة المطابقة",
            "الرد ما فيه matched_fraction — التطبيق ما يقدر يفرّق بين "
            "«ما طابقنا» و«طابقنا وما عندنا قراءات»")

    ok("مسار بين محافظتين",
       f"{km:.0f} كم، {len(with_ways)}/{len(maneuvers)} مناورة لها "
       f"معرّفات، طابقنا {int(frac * 100)}% من المسافة")


def check_road_candidates(route_pts: list, now: float) -> None:
    """كشف الطرق الناقصة من الآثار.

    فحصان متقابلان، والثاني أهمّ: أثر في الصحراء لازم يُكتشف، وأثر على
    طريق معروف لازم **لا** يُكتشف. بلا الثاني يصير الكشف مولّد ضجيج —
    يرشّح كل طريق في البلد ويضيع الحقيقي بينها.
    """
    # نقيس أعلى عدّاد لا عدد المرشّحين: المرور الثاني على نفس المكان
    # يرفع عدّاد المرشّح الموجود ولا ينشئ جديداً — وهو السلوك الصحيح،
    # فعدّ المرشّحين لا يتغيّر ويبدو كأن الكشف معطّل
    def _max_hits() -> int:
        d = requests.get(f"{API_URL}/roads/candidates", timeout=20).json()
        return max((c["hits"] for c in d["candidates"]), default=0)

    before_hits = _max_hits()

    # ١. أثر على طريق معروف — ما يصير مرشّحاً
    known = [{"lat": la, "lon": lo, "time": now + i * 3, "speed_kmh": 40.0}
             for i, (la, lo) in enumerate(route_pts[:100])]
    res = requests.post(f"{API_URL}/traffic/trace", json={"points": known},
                        timeout=40).json()

    if res.get("road_candidates", 0) != 0:
        die("إنذار كاذب في كشف الطرق",
            f"أثر على مسار ڤالهالا نفسه ولّد "
            f"{res['road_candidates']} مرشّحاً — المطابقة أو العتبات غلط")
    ok("كشف الطرق: بلا إنذار كاذب",
       f"{res['matched_edges']} حافة مطابَقة، صفر مرشّحين")

    # ٢. أثر في الصحراء غرب بغداد — لازم يُكتشف ويرتفع عدّاده
    desert = [{"lat": 33.15 + i * 0.0012, "lon": 43.80 + i * 0.0004,
               "time": now + i * 6, "speed_kmh": 55.0} for i in range(40)]

    need = ROAD_CANDIDATE_PROMOTE_HITS
    for _ in range(need + 1):
        requests.post(f"{API_URL}/traffic/trace", json={"points": desert},
                      timeout=40)

    data = requests.get(f"{API_URL}/roads/candidates", timeout=20).json()

    if _max_hits() <= before_hits:
        die("كشف الطرق الناقصة",
            "أثر 4كم في الصحراء ما ولّد مرشّحاً ولا رفع عدّاد موجود — "
            "الكشف معطّل")

    if data["stats"]["promoted"] < 1:
        die("ترقية المرشّح",
            f"مرّ {need + 1} مرة وما وصل العتبة "
            f"({ROAD_CANDIDATE_PROMOTE_HITS})")

    top = data["candidates"][0]
    ok("كشف الطرق الناقصة",
       f"{data['stats']['promoted']} مرشّحاً مرقّى، "
       f"{data['stats']['promoted_km']} كم — أطولها {top['length_m']}م "
       f"مرّ به {top['hits']} جهازاً")


def _decode_all(enc: str) -> list[tuple[float, float]]:
    pts, i, lat, lon = [], 0, 0, 0
    while i < len(enc):
        for which in range(2):
            shift = result = 0
            while True:
                b = ord(enc[i]) - 63
                i += 1
                result |= (b & 0x1f) << shift
                shift += 5
                if b < 0x20:
                    break
            dv = ~(result >> 1) if result & 1 else result >> 1
            if which == 0:
                lat += dv
            else:
                lon += dv
        pts.append((lat / 1e6, lon / 1e6))
    return pts


def main() -> None:
    ap = argparse.ArgumentParser(description="فحص السلسلة من طرف لطرف")
    ap.add_argument("--skip-backend", action="store_true",
                    help="افحص البلاطات والبحث وڤالهالا فقط")
    args = ap.parse_args()

    print("─ المرحلة ٠٦: فحص من طرف لطرف ─")

    print("\n١. البلاطات")
    check_tiles()

    print("\n١ب. نمط الخريطة")
    check_style()

    print("\n٢. البحث المحلي")
    check_search()

    print("\n٣. محرّك التوجيه")
    check_valhalla()

    if not args.skip_backend:
        print("\n٤. الباكند")
        ctx = check_backend()

        print("\n٥. البلاغات")
        check_reports(ctx)

        print("\n٦. التوجيه عبر الباكند")
        check_routing(ctx)

        print("\n٧. الزحام والخصوصية")
        check_traffic()

    print(f"\n{'─' * 50}")
    print(f"✓ نجح {len(_passed)} فحصاً")
    if _warned:
        print(f"⚠ {len(_warned)} تنبيهاً:")
        for w in _warned:
            print(f"    {w}")


if __name__ == "__main__":
    main()
