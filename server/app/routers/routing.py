# -*- coding: utf-8 -*-
"""التوجيه: وسيط بين التطبيق وValhalla يحقن ما لا يعرفه Valhalla.

ليش ما يكلّم التطبيق Valhalla مباشرة: Valhalla يعرف الخريطة ولا يعرف
بلاغاتنا. نحقن الإغلاقات المؤكّدة قبل الحساب، ونعلّق حالة الزحام وحدود
السرعة على كل مناورة بعده، فيصل التطبيق مساراً كاملاً بطلب واحد.

كيف نعرف معرّفات الطرق: /route ما يرجّعها أصلاً. فنمرّر خط المسار على
/trace_attributes مرة واحدة بعد الحساب، فنأخذ way_id و speed_limit لكل
حافة ونربطها بالمناورات بفهارس الشكل. طلب إضافي واحد لكل مسار، لا لكل
قراءة موقع.
"""

import httpx
from fastapi import APIRouter, Depends
from sqlalchemy import bindparam, text
from sqlalchemy.engine import Connection

from .. import valhalla
from ..db import get_conn
from ..schemas import RouteIn

router = APIRouter(prefix="/route", tags=["توجيه"])

# نسبة تصحيح الزمن لكل مستوى زحام: مقلوب نسبة السرعة تقريباً — زحام يعني
# ربع السرعة فأربعة أضعاف الزمن
_TIME_FACTOR = {"free": 1.0, "moderate": 1.4, "heavy": 2.2, "jam": 3.5}

# سقف نقاط المطابقة. المسارات الطويلة (بغداد ← البصرة) تتجاوز آلاف
# النقاط، وValhalla يرفض فوق حدّه ويتأخّر قبله. نطابق أول هذا العدد —
# وهو الجزء الذي يسوقه السائق الآن، وسيُعاد الحساب قبل ما يصل آخره
_MAX_TRACE_POINTS = 1200

_TRACE_TIMEOUT = httpx.Timeout(12.0, connect=3.0)


def _decode_polyline6(encoded: str) -> list[dict]:
    """يفكّ خط ڤالهالا. دقة ست منازل لا خمس — القاسم 1e6."""
    points: list[dict] = []
    index = lat = lon = 0

    while index < len(encoded):
        for which in range(2):
            shift = result = 0
            while True:
                byte = ord(encoded[index]) - 63
                index += 1
                result |= (byte & 0x1F) << shift
                shift += 5
                if byte < 0x20:
                    break
            delta = ~(result >> 1) if result & 1 else result >> 1
            if which == 0:
                lat += delta
            else:
                lon += delta
        points.append({"lat": lat / 1e6, "lon": lon / 1e6})

    return points


async def _attach_edges(trip: dict) -> float:
    """يعلّق way_id و speed_limit على كل مناورة.

    يرجّع نسبة نقاط الشكل التي طابقناها (0–1). الفشل ليس قاتلاً: المسار
    صالح بلا معرّفات، فنرجّع صفراً ويُعلن التطبيق غياب الزحام بصراحة.
    """
    legs = trip.get("legs") or []
    if not legs:
        return 0.0

    shape = _decode_polyline6(legs[0].get("shape", ""))
    if len(shape) < 2:
        return 0.0

    traced = shape[:_MAX_TRACE_POINTS]

    try:
        matched = await valhalla.trace_attributes(traced,
                                                  timeout=_TRACE_TIMEOUT)
    except Exception:
        # المطابقة تحسين لا شرط. فشلها (مهلة، رفض، مسار على طريق لا
        # تغطّيه قواعد المطابقة) ما يمنع تسليم المسار نفسه
        return 0.0

    edges = matched.get("edges") or []
    if not edges:
        return 0.0

    # نربط الحواف بالمناورات بتقاطع فهارس الشكل: المناورة تمتد من
    # begin_shape_index إلى end_shape_index، والحافة كذلك
    for m in legs[0].get("maneuvers", []):
        m0 = m.get("begin_shape_index", 0)
        m1 = m.get("end_shape_index", m0)

        way_ids: list[int] = []
        limits: list[float] = []

        for e in edges:
            e0 = e.get("begin_shape_index")
            e1 = e.get("end_shape_index")
            if e0 is None or e1 is None or e1 < m0 or e0 > m1:
                continue
            wid = e.get("way_id")
            if wid is not None and wid not in way_ids:
                way_ids.append(wid)
            lim = e.get("speed_limit")
            if lim:
                limits.append(float(lim))

        if way_ids:
            m["way_ids"] = way_ids
        # حدّ السرعة الأدنى على المناورة: المناورة قد تمرّ على حافتين
        # بحدّين، والأدنى هو الملزِم
        if limits:
            m["speed_limit"] = min(limits)

    return len(traced) / len(shape)


def _closure_polygons(conn: Connection) -> list:
    """الإغلاقات المؤكّدة كمضلّعات يتجنّبها Valhalla.

    مربّع حول كل نقطة لا دائرة: الدائرة تحتاج نقاطاً كثيرة وما تزيد دقة
    على 50 متراً.
    """
    rows = conn.execute(text("""
        SELECT ST_Y(geom::geometry) AS lat, ST_X(geom::geometry) AS lon,
               radius_m
        FROM road_closure
        WHERE expires_at > now()
        LIMIT 500
    """)).fetchall()

    polys = []
    for r in rows:
        # درجة عرض ≈ 111.32 كم؛ درجة طول تتقلّص بـcos(lat) لكن على 50
        # متراً في خطوط عرض العراق الفرق أقل من متر فنهمله
        d = r.radius_m / 111_320.0
        polys.append([
            [r.lon - d, r.lat - d], [r.lon + d, r.lat - d],
            [r.lon + d, r.lat + d], [r.lon - d, r.lat + d],
            [r.lon - d, r.lat - d],
        ])
    return polys


def _annotate_traffic(conn: Connection, trip: dict,
                      traced_fraction: float) -> dict:
    """يعلّق حالة الزحام على كل مناورة ويصحّح الـETA."""
    way_ids: set[int] = set()
    for leg in trip.get("legs", []):
        for m in leg.get("maneuvers", []):
            way_ids.update(m.get("way_ids") or [])

    if not way_ids:
        trip["traffic"] = {"available": False,
                           "reason": "ما قدرنا نطابق المسار على الطرق"}
        return trip

    stmt = text("""
        SELECT way_id, level, avg_speed_kmh FROM traffic_state
        WHERE way_id IN :ids
    """).bindparams(bindparam("ids", expanding=True))
    states = {r.way_id: r for r in
              conn.execute(stmt, {"ids": list(way_ids)}).fetchall()}

    if not states:
        trip["traffic"] = {
            "available": False,
            "reason": "ما عندنا قراءات حديثة على هذا المسار",
            "matched_ways": len(way_ids),
        }
        return trip

    covered = 0.0
    extra_s = 0.0
    for leg in trip.get("legs", []):
        for m in leg.get("maneuvers", []):
            wids = [w for w in (m.get("way_ids") or []) if w in states]
            if not wids:
                continue
            # أسوأ حالة على المناورة تحكمها: قطعة مزدحمة واحدة تكفي
            # لتعطيل المناورة كلها
            worst_level = max(
                (states[w].level for w in wids),
                key=lambda lv: _TIME_FACTOR.get(lv, 1.0))
            m["traffic_level"] = worst_level
            extra_s += m.get("time", 0) * (
                _TIME_FACTOR.get(worst_level, 1.0) - 1.0)
            covered += m.get("length", 0)

    total_len = trip.get("summary", {}).get("length", 0) or 1
    trip["traffic"] = {
        "available": True,
        "coverage": round(min(1.0, covered / total_len), 2),
        "matched_fraction": round(traced_fraction, 2),
        "added_seconds": round(extra_s),
    }
    trip["summary"]["time_with_traffic"] = round(
        trip.get("summary", {}).get("time", 0) + extra_s)
    return trip


@router.post("")
async def compute_route(body: RouteIn,
                        conn: Connection = Depends(get_conn)) -> dict:
    locations = [{"lat": c.lat, "lon": c.lon} for c in body.locations]
    polys = _closure_polygons(conn) if body.avoid_closures else None

    result = await valhalla.route(locations, costing=body.costing,
                                  exclude_polygons=polys,
                                  alternates=body.alternates)

    trip = result.get("trip", {})
    fraction = await _attach_edges(trip)
    trip = _annotate_traffic(conn, trip, fraction)

    out = {"trip": trip, "closures_avoided": len(polys or [])}

    # البدائل ما نطابقها: مطابقة كل بديل تضاعف زمن الرد ثلاث مرات،
    # والمستخدم يرى منها المدة والمسافة فقط قبل أن يختار
    if "alternates" in result:
        out["alternates"] = [a.get("trip", {}) for a in result["alternates"]]

    return out
