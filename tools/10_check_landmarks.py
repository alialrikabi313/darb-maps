# -*- coding: utf-8 -*-
"""المرحلة ١٠: فحص التعليمات كما يسمعها السائق.

يقرأ: Valhalla على 8002 + poi/pois.sqlite
ينتج: تقريراً على الشاشة بنصّ كل تعليمة على مسارات حقيقية

المشكلة التي يقيسها: 9% فقط من طرق العراق مسمّاة، فأكثر المناورات تُنطق
«انعطف يمين» بلا دلالة. الحلّ معالم قريبة — والعراقي يدلّ بها أصلاً.

يحاكي منطق التطبيق حرفاً بحرف (lib/core/search.dart: landmarkNear
و lib/nav/phrases.dart) كي نقرأ الجمل قبل ما نسمعها على الطريق. أي
تعديل في أوزان المعالم أو الصياغة هناك يُراجَع هنا أولاً.

    python 10_check_landmarks.py
    python 10_check_landmarks.py --verbose   # يطبع كل تعليمة
"""

import sys
import math
import sqlite3
import argparse

import requests

from config import VALHALLA_URL, POI_DB

# نفس أوزان lib/core/search.dart — المعلم المفيد ما يراه السائق بطرف
# عينه ويميّزه بلا تدقيق
_WEIGHT = {
    "fuel": 100, "mosque": 95, "hospital": 90, "university": 85,
    "transport": 80, "market": 70, "park": 65, "government": 60,
    "school": 55, "bank": 45, "hotel": 40, "car_service": 35,
    "restaurant": 30, "pharmacy": 25,
}

_RADIUS_M = 180

# أقصى طول لاسم المعلم. الجملة المنطوقة لازم تنتهي قبل التقاطع — قرأنا
# «انعطف يمين عند شركة المسار العالميه للسفر والسياحة» فقصّرناها
_MAX_CHARS = 34
_MAX_WORDS = 5

# الاسم اللاتيني يُنطق مشوّهاً في جملة عربية
_ARABIC = __import__('re').compile(r'[؀-ۿ]')

# نقطع الاسم عند الفاصل: «مصرف الرشيد - فرع الفرات 515» → «مصرف الرشيد».
# السائق يميّز المصرف ولا يميّز رقم الفرع
_CUT = __import__('re').compile(r'\s[-–—/|]\s|\s*[(（]|\s*[،,]\s*')


# أسماء هي كلمة التصنيف وحدها — «انعطف يمين قبل جامع» أسوأ من لا دلالة
_GENERIC = {
    'جامع', 'مسجد', 'حسينية', 'كنيسة', 'مرقد',
    'مدرسة', 'ثانوية', 'اعدادية', 'ابتدائية', 'روضة', 'جامعة', 'كلية',
    'مستشفى', 'عيادة', 'مستوصف', 'مختبر', 'صيدلية',
    'مطعم', 'مقهى', 'كافيه', 'سوق', 'مول', 'محل', 'محلات',
    'فندق', 'مصرف', 'بنك', 'صراف',
    'حديقة', 'متنزه', 'ملعب', 'محطة', 'كراج', 'مرآب', 'موقف',
    'بنزين', 'وقود', 'دائرة', 'مكتب', 'شركة', 'معرض',
}


def trim_landmark(name: str) -> str:
    head = _CUT.split(name)[0].strip()
    return head if head and _ARABIC.search(head) else name

# مسارات في خمس مدن متفاوتة التغطية: بغداد غنية والموصل والناصرية فقيرة
_ROUTES = [
    ("بغداد: التحرير ← المنصور", (33.3074, 44.4009), (33.3094, 44.3384)),
    ("بغداد: الكاظمية ← الكرادة", (33.3799, 44.3375), (33.2940, 44.4190)),
    ("البصرة: المركز ← الجامعة", (30.5085, 47.7804), (30.5600, 47.7400)),
    ("الموصل: شرق ← غرب", (36.3400, 43.1300), (36.3600, 43.0900)),
    ("النجف: المركز ← الكوفة", (31.9960, 44.3148), (32.0300, 44.4000)),
    ("كربلاء: عبور المدينة", (32.6160, 44.0240), (32.5900, 44.0600)),
    ("الناصرية: عبور المدينة", (31.0500, 46.2500), (31.0300, 46.2800)),
    ("أربيل: القلعة ← الجامعة", (36.1911, 44.0092), (36.2300, 43.9800)),
]

# أنواع مناورات ڤالهالا التي نسمّيها — مختصر من phrases.dart
_TITLES = {
    1: "ابدأ السير", 2: "ابدأ السير", 3: "ابدأ السير",
    4: "وصلت", 5: "وصلت — على يمينك", 6: "وصلت — على يسارك",
    7: "كمّل مستقيم", 8: "كمّل مستقيم",
    9: "مِل يمين", 10: "انعطف يمين", 11: "انعطف يمين حاد",
    16: "مِل يسار", 15: "انعطف يسار", 14: "انعطف يسار حاد",
    12: "استدر بالعكس", 13: "استدر بالعكس",
    17: "كمّل على المنحدر", 18: "اطلع على المنحدر يمين",
    19: "اطلع على المنحدر يسار",
    20: "اخرج يمين", 21: "اخرج يسار",
    22: "ابقَ مستقيم", 23: "ابقَ يمين", 24: "ابقَ يسار",
    25: "اندمج", 38: "اندمج يمين", 39: "اندمج يسار",
    26: "ادخل الدوّار", 27: "اخرج من الدوّار",
}

_ARRIVAL = {4, 5, 6}


def meters(lat1, lon1, lat2, lon2) -> float:
    dlat = (lat2 - lat1) * 111_320.0
    dlon = (lon2 - lon1) * 111_320.0 * math.cos(math.radians((lat1 + lat2) / 2))
    return math.hypot(dlat, dlon)


def decode6(enc: str) -> list[tuple[float, float]]:
    pts, i, lat, lon = [], 0, 0, 0
    while i < len(enc):
        for which in range(2):
            shift = result = 0
            while True:
                b = ord(enc[i]) - 63
                i += 1
                result |= (b & 0x1F) << shift
                shift += 5
                if b < 0x20:
                    break
            d = ~(result >> 1) if result & 1 else result >> 1
            if which == 0:
                lat += d
            else:
                lon += d
        pts.append((lat / 1e6, lon / 1e6))
    return pts


def traveled_to(pts, lat, lon) -> float:
    """المسافة المقطوعة على الخط حتى أقرب نقطة من (lat, lon)."""
    best_d, best_t, acc = 1e18, 0.0, 0.0
    for i in range(len(pts) - 1):
        seg = meters(pts[i][0], pts[i][1], pts[i + 1][0], pts[i + 1][1])
        d = meters(lat, lon, pts[i][0], pts[i][1])
        if d < best_d:
            best_d, best_t = d, acc
        acc += seg
    return best_t


def landmark_near(con, lat: float, lon: float):
    """نفس منطق PoiSearch.landmarkNear."""
    d_lat = _RADIUS_M / 111_320.0
    d_lon = d_lat / math.cos(math.radians(lat))

    rows = con.execute("""
        SELECT p.name_ar, p.name_en, p.category, p.lat, p.lon, p.rank
        FROM poi_geo g JOIN poi p ON p.id = g.id
        WHERE g.min_lon >= ? AND g.max_lon <= ?
          AND g.min_lat >= ? AND g.max_lat <= ?
          AND p.category != 'street'
        LIMIT 60
    """, (lon - d_lon, lon + d_lon, lat - d_lat, lat + d_lat)).fetchall()

    best, best_score = None, -1.0
    for name_ar, name_en, cat, plat, plon, rank in rows:
        w = _WEIGHT.get(cat)
        if w is None:
            continue
        if not name_ar or not _ARABIC.search(name_ar):
            continue
        short = trim_landmark(name_ar)
        words = short.split()
        if len(short) > _MAX_CHARS or len(words) > _MAX_WORDS:
            continue
        if len(words) == 1 and words[0] in _GENERIC:
            continue
        dist = meters(lat, lon, plat, plon)
        if dist > _RADIUS_M:
            continue
        # النوع والبروز والقرب — نفس وزن lib/core/search.dart
        score = w + rank * 0.5 - dist * 0.35
        if score > best_score:
            best_score = score
            best = (short, cat, dist, plat, plon)
    return best


def preposition(delta_m: float) -> str:
    """حرف الجرّ حسب موضع المعلم من المناورة على المسار."""
    if delta_m < -35:
        return "بعد"
    if delta_m > 35:
        return "قبل"
    return "عند"


def sentence(mv: dict, landmark, title: str, prep: str = "عند") -> str:
    """نفس صياغة maneuverDetail."""
    streets = mv.get("begin_street_names") or mv.get("street_names") or []
    street = streets[0] if streets else None
    arrival = mv["type"] in _ARRIVAL

    if arrival:
        if street is None and landmark:
            return f"{title} — وجهتك {prep} {landmark[0]}"
        return title

    sign = mv.get("sign") or {}
    exits = sign.get("exit_number_elements") or []
    if exits:
        return f"{title} — مخرج {exits[0]['text']}"

    if street:
        prep = "على" if mv["type"] in (7, 8, 22) else "إلى"
        return f"{title} {prep} {street}"

    if landmark:
        return f"{title} {prep} {landmark[0]}"

    return title


def main() -> None:
    ap = argparse.ArgumentParser(
        description="فحص التعليمات الصوتية على مسارات حقيقية")
    ap.add_argument("--verbose", action="store_true",
                    help="اطبع كل تعليمة لا الملخّص فقط")
    args = ap.parse_args()

    if not POI_DB.exists():
        sys.exit(f"{POI_DB} غير موجود — شغّل 04_extract_pois.py أولاً")

    con = sqlite3.connect(POI_DB)
    print("─ المرحلة ١٠: التعليمات كما يسمعها السائق ─\n")

    tot = named = with_lm = bare = 0
    cats: dict[str, int] = {}

    header = f"{'المسار':<28}{'مناورات':>8}{'بشارع':>7}{'بمعلم':>7}{'عارية':>7}"
    print(header)
    print("─" * len(header))

    for label, src, dst in _ROUTES:
        body = {"locations": [{"lat": src[0], "lon": src[1]},
                              {"lat": dst[0], "lon": dst[1]}],
                "costing": "auto"}
        try:
            r = requests.post(f"{VALHALLA_URL}/route", json=body, timeout=40)
        except requests.RequestException as e:
            sys.exit(f"ما وصلنا ڤالهالا على {VALHALLA_URL} — {e}")

        if r.status_code != 200:
            print(f"{label:<28}  ما في مسار (HTTP {r.status_code})")
            continue

        leg = r.json()["trip"]["legs"][0]
        pts = decode6(leg["shape"])
        n = s = lm = b = 0
        lines = []
        prev_lm = None

        for mv in leg["maneuvers"]:
            n += 1
            title = _TITLES.get(mv["type"], "كمّل")
            streets = mv.get("begin_street_names") or \
                mv.get("street_names") or []

            if streets:
                s += 1
                lines.append(("شارع", sentence(mv, None, title)))
                continue

            i = min(mv.get("begin_shape_index", 0), len(pts) - 1)
            found = landmark_near(con, pts[i][0], pts[i][1])

            # نفس المعلم مرتين يربك — نقارن بآخر مستعمَل لا بآخر مدخل
            if found and found[0] == prev_lm:
                found = None
            if found:
                prev_lm = found[0]

            if found:
                lm += 1
                cats[found[1]] = cats.get(found[1], 0) + 1
                delta = (traveled_to(pts, found[3], found[4])
                         - traveled_to(pts, pts[i][0], pts[i][1]))
                lines.append(("معلم",
                              sentence(mv, found, title,
                                       preposition(delta))))
            else:
                b += 1
                lines.append(("عارية", sentence(mv, None, title)))

        tot += n
        named += s
        with_lm += lm
        bare += b

        print(f"{label:<28}{n:>8}{s:>7}{lm:>7}{b:>7}")

        if args.verbose:
            for kind, text in lines:
                mark = {"شارع": "·", "معلم": "◆", "عارية": "✗"}[kind]
                print(f"      {mark} {text}")
            print()

    print("─" * len(header))
    print(f"{'المجموع':<28}{tot:>8}{named:>7}{with_lm:>7}{bare:>7}")

    if tot == 0:
        sys.exit("ما حصلنا أي مناورة — افحص ڤالهالا")

    only_streets = 100 * named / tot
    covered = 100 * (named + with_lm) / tot

    print(f"\n  بأسماء الشوارع وحدها   {only_streets:5.0f}%")
    print(f"  ★ مع المعالم           {covered:5.0f}%"
          f"   (+{covered - only_streets:.0f} نقطة)")

    if cats:
        print("\n  المعالم المستعملة حسب التصنيف:")
        for cat, c in sorted(cats.items(), key=lambda kv: -kv[1]):
            print(f"      {cat:<12} {c:>4}")

    # تعليمة عارية تعني «انعطف يمين» بلا دلالة — نقبل بعضها ونقلق من
    # كثرتها. الثلث عتبة اجتهادية تُراجَع على طريق حقيقي
    if bare / tot > 0.34:
        print(f"\n  ⚠ {100 * bare / tot:.0f}% من التعليمات عارية — "
              f"فوق الثلث.\n"
              f"    جرّب توسيع نصف قطر المعلم أو إضافة تصنيفات لـ_WEIGHT")

    con.close()
    print("\n✓ المرحلة ١٠ تمّت.")


if __name__ == "__main__":
    main()
