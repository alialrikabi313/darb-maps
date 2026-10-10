# -*- coding: utf-8 -*-
"""الزحام الحيّ من قراءات GPS مجهولة.

كيف يشتغل: التطبيق يرسل قطعة من مسار السائق (نقاط + أوقات + سرعات).
السيرفر يمرّرها على Valhalla /trace_attributes فيحوّلها إلى way_id لكل
قطعة طريق، ويخزّن سرعة لكل قطعة. ثم يُجمَّع دورياً إلى حالة واحدة لكل قطعة.

الصادق: الزحام يحتاج كتلة مستخدمين. العتبة TRAFFIC_MIN_SAMPLES تمنعنا من
إعلان زحام من سيارة واحدة واقفة لإنزال راكب، لكنها تعني أيضاً أن الميزة
صامتة حتى يكبر العدد. تُبنى الآن وتنمو بعد الإطلاق.

الخصوصية: ما نخزّن معرّف جهاز ولا معرّف رحلة. قطعة طريق وسرعة ووقت. حتى
ترتيب القطع ما يُحفظ — المسار الكامل يعرّف صاحبه حتى بلا اسم.
"""

import math
import random
from datetime import datetime, timezone

from fastapi import APIRouter, Depends, Query
from sqlalchemy import bindparam, text
from sqlalchemy.engine import Connection

from .. import roads, valhalla
from ..db import get_conn
from ..guards import require_admin
from ..schemas import TraceIn, TrafficSegment
from ..settings import (
    TRAFFIC_LEVELS, DEFAULT_FREE_SPEED_KMH, TRAFFIC_MIN_SAMPLES,
    TRAFFIC_SAMPLE_TTL_MIN, TRACE_TRIM_ENDPOINTS_M, TRACE_RETENTION_DAYS,
)

router = APIRouter(prefix="/traffic", tags=["زحام"])

# سقف المعرّفات في طلب واحد. بلاه يقبل الطلب قائمة بمئة ألف معرّف
# وتبني منها قاعدة البيانات IN ضخمة
_MAX_SEGMENT_IDS = 500

# صنف الطريق عند Valhalla رقم لا نصّ. الترتيب من أعلى صنف لأدناه
_ROAD_CLASS_NAMES = {
    0: "motorway", 1: "trunk", 2: "primary", 3: "secondary", 4: "tertiary",
    5: "unclassified", 6: "residential", 7: "service",
}


def free_speed_for(road_class: int | None,
                   valhalla_speed: float | None) -> float:
    """السرعة الحرّة المرجعية لقطعة.

    نفضّل سرعة Valhalla إذا كانت موجودة لأنها من maxspeed في OSM؛ وإذا ما
    كانت نرجع لافتراضنا حسب صنف الطريق. maxspeed ناقص في أكثر طرق بغداد
    فالافتراض هو الحالة الغالبة لا الاستثناء.
    """
    if valhalla_speed and valhalla_speed > 5:
        return float(valhalla_speed)
    name = _ROAD_CLASS_NAMES.get(road_class, "residential")
    return float(DEFAULT_FREE_SPEED_KMH.get(name, 30))


def level_for(avg_kmh: float, free_kmh: float) -> str:
    ratio = avg_kmh / free_kmh if free_kmh > 0 else 1.0
    if ratio >= TRAFFIC_LEVELS["free"]:
        return "free"
    if ratio >= TRAFFIC_LEVELS["moderate"]:
        return "moderate"
    if ratio >= TRAFFIC_LEVELS["heavy"]:
        return "heavy"
    return "jam"


def _trim_endpoints(points: list) -> list:
    """يحذف بداية الرحلة ونهايتها.

    أول نقطة هي البيت وآخرها الوجهة، وهما أخطر نقطتين على خصوصية المستخدم.
    نحذف بالمسافة لا بعدد النقاط: GPS يرسل نقاطاً متقاربة حين تكون السيارة
    بطيئة، فحذف «أول خمس نقاط» قد لا يحرّكنا عشرة أمتار.
    """
    if len(points) < 6:
        return []

    def cut_from_start(pts: list) -> list:
        # الرحلة القصيرة يفرغها القصّ الأول، فيستلم القصّ الثاني قائمة
        # فارغة — انهار عليها فعلاً برحلة طولها 45 متراً
        if not pts:
            return []
        base = pts[0]
        for i, p in enumerate(pts):
            if _rough_meters(base.lat, base.lon, p.lat, p.lon) >= \
                    TRACE_TRIM_ENDPOINTS_M:
                return pts[i:]
        return []

    trimmed = cut_from_start(points)
    trimmed = list(reversed(cut_from_start(list(reversed(trimmed)))))
    return trimmed


def _rough_meters(lat1: float, lon1: float, lat2: float, lon2: float) -> float:
    # تقريب مستوٍ: على مسافات مئات الأمتار خطؤه سنتمترات، وأرخص من haversine
    # ونُناديه لكل نقطة في كل رحلة
    dlat = (lat2 - lat1) * 111_320.0
    dlon = (lon2 - lon1) * 111_320.0 * math.cos(math.radians((lat1 + lat2) / 2))
    return math.hypot(dlat, dlon)


@router.post("/trace", status_code=202)
async def submit_trace(body: TraceIn,
                       conn: Connection = Depends(get_conn)) -> dict:
    """يستقبل قطعة مسار مجهولة ويحوّلها قراءات سرعة لكل قطعة طريق.

    لا يحتاج توكن جهاز بقصد: ربط القراءة بجهاز هو بالضبط ما نتجنّبه.
    """
    points = _trim_endpoints(body.points)
    if len(points) < 4:
        # الرحلة القصيرة تُحذف كاملة بعد قصّ الأطراف — وهذا صحيح: رحلة
        # 400 متر كلها «قرب البيت»
        return {"stored": 0, "reason": "الرحلة أقصر من أن تُجهَّل"}

    shape = [{"lat": p.lat, "lon": p.lon, "time": p.time} for p in points]
    matched = await valhalla.trace_attributes(shape)

    edges = matched.get("edges", [])
    if not edges:
        return {"stored": 0, "reason": "ما طابقنا الرحلة على أي طريق"}

    # سرعة كل قطعة: متوسط سرعات نقاط GPS التي تقع عليها. نستخدم سرعة GPS
    # لا المسافة÷الزمن لأن دوبلر أدقّ من تفاضل موقعين مضطربين.
    #
    # الختم يُقرَّب للدقيقة ويُبعثَر: ختم واحد بدقّة الميكروثانية على كل
    # صفوف الإرسالة كان مفتاح رحلة — استعلام واحد بـobserved_at يجمع
    # قطع السائق، وترتيب id التسلسلي يعيد بناء مساره. وهذا ينقض وعد
    # «لا معرّف رحلة» الذي بُنيت عليه الميزة
    minute = datetime.now(timezone.utc).replace(second=0, microsecond=0)
    rows = []
    for e in edges:
        i0 = e.get("begin_shape_index")
        i1 = e.get("end_shape_index")
        way_id = e.get("way_id")
        if way_id is None or i0 is None or i1 is None:
            continue

        speeds = [p.speed_kmh for p in points[i0:i1 + 1]
                  if p.speed_kmh is not None]
        if not speeds:
            continue

        # السرعة الحرّة المرجعية تُلتقط هنا من الحافة نفسها.
        # كانت تُثبَّت على 30 للأبد في التجميع، فيُصنَّف زحام طريق
        # المطار (حرّ 100) عند 25 كم/س «سالكاً» لأن 25/30 = 0.83 —
        # والميزة تقول عكس الحقيقة في أهمّ مكان
        rows.append({"way_id": way_id,
                     "speed": sum(speeds) / len(speeds),
                     "free": free_speed_for(e.get("road_class"),
                                            e.get("speed_limit")
                                            or e.get("speed")),
                     "at": minute})

    if rows:
        # نبعثر الترتيب قبل الإدخال: معرّفات bigserial متتالية كانت
        # تحفظ ترتيب القطع، وهو مسار الرحلة بعينه
        random.shuffle(rows)
        conn.execute(text("""
            INSERT INTO traffic_sample (way_id, speed_kmh, free_speed_kmh,
                                        observed_at)
            VALUES (:way_id, :speed, :free, :at)
        """), rows)

    # الجزء من الأثر الذي ما غطّته أي حافة = طريق ناقص من الخريطة.
    # نفس الطلب الذي حسبنا به الزحام يعطينا هذا مجّاناً
    candidates = roads.record_candidates(conn, points, edges)

    return {"stored": len(rows), "matched_edges": len(edges),
            "road_candidates": candidates}


@router.post("/aggregate", dependencies=[Depends(require_admin)])
def aggregate(conn: Connection = Depends(get_conn)) -> dict:
    """يجمّع القراءات الحديثة إلى حالة واحدة لكل قطعة.

    تُنادى من وظيفة دورية كل دقيقة. ما جعلناها حسابياً وقت القراءة لأن
    التطبيق يطلب حالة الزحام عشرات المرات في الدقيقة أثناء الملاحة،
    وتجميعها في كل طلب يحرق القاعدة.

    السرعة الحرّة المرجعية تجي مع القراءة نفسها (التُقطت من حافة
    ڤالهالا وقت الاستقبال). كانت تُثبَّت على 30 هنا فيُصنَّف زحام
    الطريق السريع «سالكاً».
    """
    rows = conn.execute(text("""
        SELECT way_id,
               AVG(speed_kmh) AS avg_kmh,
               -- الوسيط أمتن من المتوسط لمرجع ثابت: قراءة شاذة واحدة
               -- بسرعة 200 تُفسد المتوسط وتجعل الطريق «مزدحماً» دائماً
               percentile_disc(0.5) WITHIN GROUP (ORDER BY free_speed_kmh)
                   AS free_kmh,
               COUNT(*) AS n
        FROM traffic_sample
        WHERE observed_at > now() - make_interval(mins => :ttl)
        GROUP BY way_id
        HAVING COUNT(*) >= :minn
    """), {"ttl": TRAFFIC_SAMPLE_TTL_MIN,
           "minn": TRAFFIC_MIN_SAMPLES}).fetchall()

    payload = []
    for r in rows:
        free = float(r.free_kmh or DEFAULT_FREE_SPEED_KMH["residential"])
        payload.append({
            "way_id": r.way_id, "avg": r.avg_kmh, "free": free,
            "level": level_for(r.avg_kmh, free), "n": r.n,
        })

    if payload:
        conn.execute(text("""
            INSERT INTO traffic_state (way_id, level, avg_speed_kmh,
                                       free_speed_kmh, samples, updated_at)
            VALUES (:way_id, :level, :avg, :free, :n, now())
            ON CONFLICT (way_id) DO UPDATE SET
                level = EXCLUDED.level,
                avg_speed_kmh = EXCLUDED.avg_speed_kmh,
                -- المرجع يُحدَّث أيضاً: تثبيته من أول مرة كان يعني أن
                -- تصحيح maxspeed في OSM لا يصل إلينا أبداً
                free_speed_kmh = EXCLUDED.free_speed_kmh,
                samples = EXCLUDED.samples,
                updated_at = now()
        """), payload)

    # القطع التي ما وصلتها قراءات حديثة تُنسى: حالة زحام عمرها ساعة أسوأ
    # من لا حالة، لأن السائق يثق بها ويتجنّب طريقاً صار سالكاً
    stale = conn.execute(text("""
        DELETE FROM traffic_state
        WHERE updated_at < now() - make_interval(mins => :ttl)
        RETURNING way_id
    """), {"ttl": TRAFFIC_SAMPLE_TTL_MIN * 2}).rowcount

    return {"updated": len(payload), "forgotten": stale}


@router.get("/segments", response_model=list[TrafficSegment])
def segments(
    way_ids: str = Query(description="معرّفات OSM مفصولة بفاصلة"),
    conn: Connection = Depends(get_conn),
) -> list[TrafficSegment]:
    """حالة الزحام لقطع بعينها — التطبيق يسألها لقطع مساره فقط.

    ليش بـway_id لا بـbbox: مسار السائق معروف، وتلوين كل قطع المدينة
    ينقل ميغابايتات ما يرسم منها إلا خطّه
    """
    # الفحص بـlstrip("-") كان يقبل «--5» ثم ينهار int() عليه بـ500.
    # نحوّل ونتجاهل الفاشل بدل ما نفحص بالشكل
    ids: list[int] = []
    for token in way_ids.split(",")[:_MAX_SEGMENT_IDS]:
        try:
            ids.append(int(token.strip()))
        except ValueError:
            continue

    if not ids:
        return []

    # expanding لا ANY: ANY يحتاج نوع مصفوفة معلَناً، و text() ما يعرف نوع
    # العمود فيمرّر القائمة نصّاً ويفشل الاستعلام
    stmt = text("""
        SELECT way_id, level, avg_speed_kmh, free_speed_kmh, samples,
               updated_at
        FROM traffic_state
        WHERE way_id IN :ids
    """).bindparams(bindparam("ids", expanding=True))
    rows = conn.execute(stmt, {"ids": ids}).fetchall()

    return [TrafficSegment(way_id=r.way_id, level=r.level,
                           avg_speed_kmh=round(r.avg_speed_kmh, 1),
                           free_speed_kmh=r.free_speed_kmh,
                           samples=r.samples, updated_at=r.updated_at)
            for r in rows]


# أقلّ عدد قراءات تُصدَّق عليه ساعة في المنحنى اليومي. تحت هذا الحد
# نرجّع null لا صفراً: «ما نعرف» غير «سالك»، وعمود أخضر على ساعة بلا
# قراءات يطلّع السائق خامسة الصبح على وعد كاذب.
_PROFILE_MIN_SAMPLES = 20


@router.get("/profile")
def profile(conn: Connection = Depends(get_conn)) -> dict:
    """منحنى الزحام بساعات اليوم — «أفضل أوقات الانطلاق».

    مُجمَّع على كل القراءات لا على منطقة: القراءة عندنا ما تحمل موقعاً
    أصلاً (way_id وحده)، وهذا وعدُ خصوصية لا نقضه لأجل رسم بياني. فالمنحنى
    وطنيّ، والواجهة تقوله صراحة بدل ما تكتب اسم مدينة ما نعرفها.

    القيمة = 1 − (متوسط السرعة ÷ السرعة الحرّة) مقصوصة في [0,1]: صفر طريق
    سالك وواحد واقف. النسبة لا السرعة المطلقة، وإلا طغى الطريق السريع على
    كل شيء بمجرّد أن سرعته أعلى.
    """
    rows = conn.execute(text("""
        SELECT EXTRACT(HOUR FROM observed_at AT TIME ZONE 'Asia/Baghdad')::int
                   AS hour,
               AVG(speed_kmh / NULLIF(free_speed_kmh, 0)) AS ratio,
               COUNT(*) AS n
        FROM traffic_sample
        WHERE observed_at > now() - make_interval(days => :days)
          AND free_speed_kmh > 0
        GROUP BY 1
    """), {"days": TRACE_RETENTION_DAYS}).fetchall()

    hours: list[float | None] = [None] * 24
    counts = [0] * 24
    for r in rows:
        counts[r.hour] = r.n
        if r.n >= _PROFILE_MIN_SAMPLES and r.ratio is not None:
            hours[r.hour] = round(max(0.0, min(1.0, 1.0 - float(r.ratio))), 2)

    return {
        "hours": hours,
        "samples": counts,
        "window_days": TRACE_RETENTION_DAYS,
        "min_samples": _PROFILE_MIN_SAMPLES,
    }
