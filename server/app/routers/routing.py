# -*- coding: utf-8 -*-
"""التوجيه: وسيط بين التطبيق وValhalla يحقن ما لا يعرفه Valhalla.

ليش ما يكلّم التطبيق Valhalla مباشرة: Valhalla يعرف الخريطة ولا يعرف
بلاغاتنا. نحقن الإغلاقات المؤكّدة قبل الحساب، ونعلّق حالة الزحام على كل
قطعة بعد الحساب فيعرض التطبيق مساراً ملوّناً وETA واقعياً بطلب واحد.

ما نحقن الزحام في أوزان Valhalla نفسها: يحتاج إعادة بناء الرسم أو خدمة
traffic منفصلة، وكلفتها لا تستحق قبل ما تكبر كتلة المستخدمين. الآن نصحّح
الـETA حساباً بعد المسار ونعلن الفرق — انظر decisions.md.
"""

from fastapi import APIRouter, Depends
from sqlalchemy import bindparam, text
from sqlalchemy.engine import Connection

from .. import valhalla
from ..db import get_conn
from ..schemas import RouteIn

router = APIRouter(prefix="/route", tags=["توجيه"])

# نسبة تصحيح الزمن لكل مستوى زحام. ضرب الزمن الحرّ في المقلوب التقريبي
# لنسبة السرعة: زحام يعني ربع السرعة فأربعة أضعاف الزمن
_TIME_FACTOR = {"free": 1.0, "moderate": 1.4, "heavy": 2.2, "jam": 3.5}


def _closure_polygons(conn: Connection) -> list:
    """الإغلاقات المؤكّدة كمضلّعات يتجنّبها Valhalla.

    Valhalla يبي exclude_polygons حلقات من [lon, lat]. نحوّل كل إغلاق إلى
    مربّع حول نقطته — الدائرة تحتاج نقاطاً كثيرة وما تزيد دقة على 50 متراً.
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
        # درجة عرض ≈ 111.32 كم؛ درجة طول تتقلّص بـcos(lat) لكن على 50 متراً
        # في خطوط عرض العراق الفرق أقل من متر فنهمله
        d = r.radius_m / 111_320.0
        polys.append([
            [r.lon - d, r.lat - d], [r.lon + d, r.lat - d],
            [r.lon + d, r.lat + d], [r.lon - d, r.lat + d],
            [r.lon - d, r.lat - d],
        ])
    return polys


def _annotate_traffic(conn: Connection, trip: dict) -> dict:
    """يعلّق حالة الزحام على كل مناورة ويصحّح الـETA.

    Valhalla ما يرجّع way_id في /route (يرجّعه في /trace_attributes فقط)،
    فنربط بالاسم… لا. نربط بـway_id حين يتوفّر عبر خيار الصفات، وإلا
    نتركها فارغة بصراحة بدل ما نخمّن.
    """
    # نجمع كل معرّفات الطرق التي رجّعها Valhalla في صفات الحواف
    way_ids: set[int] = set()
    for leg in trip.get("legs", []):
        for wid in leg.get("way_ids", []) or []:
            way_ids.add(wid)

    if not way_ids:
        # الحالة الغالبة مع /route الافتراضي. نرجّع المسار بلا تلوين بدل
        # ما نلوّنه بتخمين — خط أحمر خاطئ أسوأ من خط بلا لون
        trip["traffic"] = {"available": False,
                           "reason": "المسار ما رجّع معرّفات طرق"}
        return trip

    stmt = text("""
        SELECT way_id, level, avg_speed_kmh FROM traffic_state
        WHERE way_id IN :ids
    """).bindparams(bindparam("ids", expanding=True))
    states = {r.way_id: r for r in
              conn.execute(stmt, {"ids": list(way_ids)}).fetchall()}

    if not states:
        trip["traffic"] = {"available": False,
                           "reason": "ما عندنا قراءات حديثة على هذا المسار"}
        return trip

    # تصحيح الزمن: نوزّع الفرق على المناورات التي نعرف حالتها فقط، ونعلن
    # نسبة التغطية كي يعرف التطبيق مدى ثقة الـETA
    covered = 0.0
    extra_s = 0.0
    for leg in trip.get("legs", []):
        for m in leg.get("maneuvers", []):
            wids = [w for w in (m.get("way_ids") or []) if w in states]
            if not wids:
                continue
            worst = max(_TIME_FACTOR.get(states[w].level, 1.0) for w in wids)
            m["traffic_level"] = max(
                (states[w].level for w in wids),
                key=lambda lv: _TIME_FACTOR.get(lv, 1.0))
            extra_s += m.get("time", 0) * (worst - 1.0)
            covered += m.get("length", 0)

    total_len = trip.get("summary", {}).get("length", 0) or 1
    trip["traffic"] = {
        "available": True,
        "coverage": round(min(1.0, covered / total_len), 2),
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

    trip = _annotate_traffic(conn, result.get("trip", {}))
    out = {"trip": trip, "closures_avoided": len(polys or [])}

    if "alternates" in result:
        out["alternates"] = [_annotate_traffic(conn, a.get("trip", {}))
                             for a in result["alternates"]]
    return out
