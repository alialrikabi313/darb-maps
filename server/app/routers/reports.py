# -*- coding: utf-8 -*-
"""البلاغات: إرسال، جوار، تصويت.

التجميع يصير وقت الكتابة لا وقت القراءة: «حولي» أكثر طلب حرارةً في النظام
(كل بضع ثوان أثناء الملاحة)، وتجميع البلاغات في كل مرة يقتل القاعدة.
فنختار قائد المجموعة مرة عند الإرسال ونخزّنه.
"""

import uuid
from datetime import datetime, timezone

from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlalchemy import text
from sqlalchemy.engine import Connection

from .. import trust
from ..auth import current_device
from ..db import get_conn
from ..schemas import ReportIn, ReportOut, VoteIn
from ..settings import (
    REPORT_TYPES, REPORT_SEARCH_RADIUS_M, REPORT_CLUSTER_RADIUS_M,
)

router = APIRouter(prefix="/reports", tags=["بلاغات"])


def _to_out(row, distance_m: float | None = None, cluster_size: int = 1,
            up: int | None = None, down: int | None = None) -> ReportOut:
    """يحوّل صفّاً إلى رد.

    up/down يسمحان بتمرير أصوات المجموعة كلها بدل أصوات القائد وحده.
    بلاهما كان الرد يتناقض مع نفسه: ثلاثة بلاغات حادث متجاورة بصوت
    لكلٍّ منها تُعرض لأن أصوات المجموعة 3 (فوق عتبة التأكيد 2)، ويقول
    نفس الرد `confirmed: false` لأن القائد وحده عنده صوت.
    """
    age_min = (datetime.now(timezone.utc) - row.created_at).total_seconds() / 60
    up = row.up_votes if up is None else up
    down = row.down_votes if down is None else down

    return ReportOut(
        id=row.id, kind=row.kind, label=REPORT_TYPES[row.kind]["label"],
        lat=row.lat, lon=row.lon, heading=row.heading, note=row.note,
        created_at=row.created_at, expires_at=row.expires_at,
        up_votes=up, down_votes=down,
        confirmed=trust.is_confirmed(row.kind, up, down),
        confidence=trust.confidence(row.kind, up, down, age_min),
        cluster_size=cluster_size, distance_m=distance_m,
    )


@router.post("", response_model=ReportOut, status_code=status.HTTP_201_CREATED)
def create_report(
    body: ReportIn,
    device_id: uuid.UUID = Depends(current_device),
    conn: Connection = Depends(get_conn),
) -> ReportOut:
    rep = conn.execute(
        text("SELECT reputation FROM device WHERE id = :d"),
        {"d": device_id}).scalar_one()

    expires = trust.initial_expiry(body.kind, rep)

    # قائد المجموعة: أحدث بلاغ حيّ من نفس النوع داخل نصف قطر التجميع.
    # نأخذ الأقرب لا الأحدث: بلاغان على طرفي نصف القطر ينتميان لمجموعتين
    # مختلفتين منطقياً، والأقرب هو الأرجح أنه نفس الحادث
    leader = conn.execute(text("""
        SELECT COALESCE(cluster_id, id) AS cid
        FROM report
        WHERE kind = :kind
          AND NOT is_removed
          AND expires_at > now()
          AND ST_DWithin(geom, ST_MakePoint(:lon, :lat)::geography, :radius)
        ORDER BY ST_Distance(geom, ST_MakePoint(:lon, :lat)::geography)
        LIMIT 1
    """), {"kind": body.kind, "lon": body.lon, "lat": body.lat,
           "radius": REPORT_CLUSTER_RADIUS_M}).scalar()

    row = conn.execute(text("""
        INSERT INTO report (kind, geom, heading, device_id, note, expires_at,
                            cluster_id)
        VALUES (:kind, ST_MakePoint(:lon, :lat)::geography, :heading, :dev,
                :note, :expires, :cid)
        RETURNING id, kind, heading, note, created_at, expires_at,
                  up_votes, down_votes,
                  ST_Y(geom::geometry) AS lat, ST_X(geom::geometry) AS lon
    """), {"kind": body.kind, "lon": body.lon, "lat": body.lat,
           "heading": body.heading, "dev": device_id, "note": body.note,
           "expires": expires, "cid": leader}).one()

    # بلاغ بلا مجموعة سابقة يصير قائد نفسه — نحتاج id الذي ما نعرفه قبل
    # الإدخال، فنحدّثه بعده. UPDATE واحد أرخص من دورة قراءة ثانية
    if leader is None:
        conn.execute(text("UPDATE report SET cluster_id = id WHERE id = :i"),
                     {"i": row.id})

    conn.execute(text("UPDATE device SET reports_made = reports_made + 1 "
                      "WHERE id = :d"), {"d": device_id})

    # الإغلاق يدخل جدول الإغلاقات عند تأكيده بالتصويت لا عند إنشائه:
    # إغلاق خاطئ يطوّح السائق كيلومترات، وكلفة الخطأ أعلى بكثير من
    # كلفة تفويت إغلاق حقيقي لدقائق.
    # كان هنا شرط `is_confirmed(kind, 1, 0)` ثابت الكذب لكل نوع
    # (1 >= 3 مستحيل) — فرعٌ ميت يوهم القارئ أن للإنشاء مساراً

    return _to_out(row)


def _sync_closure(conn: Connection, report_id: int, lat: float, lon: float,
                  expires: datetime) -> None:
    conn.execute(text("""
        INSERT INTO road_closure (report_id, geom, expires_at)
        VALUES (:r, ST_MakePoint(:lon, :lat)::geography, :e)
    """), {"r": report_id, "lon": lon, "lat": lat, "e": expires})


@router.get("/near", response_model=list[ReportOut])
def reports_near(
    lat: float = Query(ge=-90, le=90),
    lon: float = Query(ge=-180, le=180),
    radius_m: int = Query(default=REPORT_SEARCH_RADIUS_M, ge=50, le=20000),
    heading: float | None = Query(default=None, ge=0, lt=360,
                                  description="اتجاه السائق — يفلتر البلاغات "
                                              "الموجّهة للجهة المعاكسة"),
    conn: Connection = Depends(get_conn),
) -> list[ReportOut]:
    # نرجّع قائد كل مجموعة مع حجمها: الواجهة تعرض أيقونة واحدة بعدّاد لا
    # أيقونات متراكبة على نفس التقاطع
    rows = conn.execute(text("""
        WITH live AS (
            SELECT r.*,
                   ST_Y(r.geom::geometry) AS lat,
                   ST_X(r.geom::geometry) AS lon,
                   ST_Distance(r.geom, ST_MakePoint(:lon, :lat)::geography)
                       AS distance_m
            FROM report r
            WHERE NOT r.is_removed
              AND r.expires_at > now()
              AND ST_DWithin(r.geom, ST_MakePoint(:lon, :lat)::geography,
                             :radius)
        ),
        sized AS (
            SELECT cluster_id, COUNT(*) AS n,
                   SUM(up_votes) AS cluster_up,
                   SUM(down_votes) AS cluster_down
            FROM live GROUP BY cluster_id
        )
        SELECT l.*, s.n AS cluster_size,
               s.cluster_up, s.cluster_down
        FROM live l
        JOIN sized s ON s.cluster_id = l.cluster_id
        -- قائد المجموعة هو الأقرب للمستخدم: هو الذي سيراه أولاً
        WHERE l.id = (
            SELECT id FROM live l2 WHERE l2.cluster_id = l.cluster_id
            ORDER BY l2.distance_m LIMIT 1
        )
        ORDER BY l.distance_m
        LIMIT 200
    """), {"lon": lon, "lat": lat, "radius": radius_m}).fetchall()

    out: list[ReportOut] = []
    for row in rows:
        # أصوات المجموعة كلها تحكم العرض لا أصوات القائد وحده: ثلاثة
        # بلاغات بصوت واحد لكل منها هي تأكيد ثلاثي لا ثلاث شكوك
        if not trust.should_show(row.kind, row.cluster_up, row.cluster_down):
            continue

        # الرادار والسيطرة على جهة واحدة من الطريق. 90 درجة سماحية: السائق
        # في منحنى يختلف اتجاهه عن اتجاه المُبلِّغ وهما على نفس الجهة
        if (heading is not None and row.heading is not None
                and _heading_diff(heading, row.heading) > 90):
            continue

        # نفس أصوات المجموعة التي حكمت الظهور تحكم التأكيد والثقة
        out.append(_to_out(row, distance_m=round(row.distance_m, 1),
                           cluster_size=row.cluster_size,
                           up=row.cluster_up, down=row.cluster_down))
    return out


def _heading_diff(a: float, b: float) -> float:
    """أصغر فرق زاوي بين اتجاهين بالدرجات (0–180)."""
    d = abs(a - b) % 360
    return min(d, 360 - d)


@router.post("/{report_id}/vote", response_model=ReportOut)
def vote(
    report_id: int,
    body: VoteIn,
    device_id: uuid.UUID = Depends(current_device),
    conn: Connection = Depends(get_conn),
) -> ReportOut:
    row = conn.execute(text("""
        SELECT id, kind, heading, note, created_at, expires_at, up_votes,
               down_votes, device_id,
               ST_Y(geom::geometry) AS lat, ST_X(geom::geometry) AS lon
        FROM report WHERE id = :i AND NOT is_removed
    """), {"i": report_id}).fetchone()

    if row is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND,
                            "البلاغ غير موجود أو انتهى")

    if row.device_id == device_id:
        raise HTTPException(status.HTTP_409_CONFLICT,
                            "ما تقدر تصوّت على بلاغك")

    # المفتاح المركّب في القاعدة يفرض صوتاً واحداً لكل جهاز. ON CONFLICT
    # يرجّع صفر صفوف فنعرف أنه صوّت سابقاً — بلا حاجة لقراءة قبل الكتابة،
    # وهي قراءة تنكسر مع طلبين متوازيين
    inserted = conn.execute(text("""
        INSERT INTO report_vote (report_id, device_id, is_up)
        VALUES (:r, :d, :u)
        ON CONFLICT (report_id, device_id) DO NOTHING
        RETURNING 1
    """), {"r": report_id, "d": device_id, "u": body.is_up}).fetchone()

    if inserted is None:
        raise HTTPException(status.HTTP_409_CONFLICT,
                            "صوّتت على هذا البلاغ سابقاً")

    # نقفل صفّ البلاغ قبل الحساب: صوتان متزامنان كانا يقرآن نفس
    # expires_at ويكتبان نفس الخصم، فينطبق خصم واحد بدل اثنين — وثلاثة
    # نفي كان المفروض تقتل البلاغ تتركه حيّاً بـ65% من عمره
    locked = conn.execute(text("""
        SELECT created_at, up_votes, down_votes FROM report
         WHERE id = :i FOR UPDATE
    """), {"i": report_id}).one()

    up = locked.up_votes + (1 if body.is_up else 0)
    down = locked.down_votes + (0 if body.is_up else 1)

    new_expiry = trust.expiry_after_downvote(row.kind, locked.created_at,
                                             up, down)

    updated = conn.execute(text("""
        UPDATE report
           SET up_votes = :up,
               down_votes = :down,
               expires_at = :e,
               -- clock_timestamp لا now(): now() هي بداية المعاملة،
               -- و:e مأخوذ من ساعة التطبيق بعدها بميلي ثانية، فالشرط
               -- ما كان يصدق أبداً والبلاغ المقتول يبقى is_removed=false
               is_removed = (:e <= clock_timestamp())
         WHERE id = :i
        RETURNING id, kind, heading, note, created_at, expires_at,
                  up_votes, down_votes,
                  ST_Y(geom::geometry) AS lat, ST_X(geom::geometry) AS lon
    """), {"i": report_id, "up": up, "down": down,
           "e": new_expiry}).one()

    if row.device_id is not None:
        conn.execute(text("UPDATE device SET reputation = reputation + :d "
                          "WHERE id = :i"),
                     {"d": trust.reputation_delta(body.is_up),
                      "i": row.device_id})

    # الإغلاق يتبع بلاغه: صار مؤكّداً فيدخل، أو مات فيخرج
    if updated.kind == "road_closed":
        if trust.is_confirmed("road_closed", updated.up_votes,
                              updated.down_votes):
            conn.execute(text("""
                INSERT INTO road_closure (report_id, geom, expires_at)
                SELECT id, geom, expires_at FROM report WHERE id = :i
                ON CONFLICT DO NOTHING
            """), {"i": report_id})
        else:
            conn.execute(text("DELETE FROM road_closure WHERE report_id = :i"),
                         {"i": report_id})

    return _to_out(updated)


@router.get("/types")
def report_types() -> dict:
    """أنواع البلاغات وصلاحياتها — التطبيق يبني منها قائمة الإبلاغ.

    ليش من السيرفر لا مكتوبة في التطبيق: إضافة نوع بلاغ تصير بتعديل
    config.py وإعادة تشغيل السيرفر، بلا نشر إصدار جديد من التطبيق.
    """
    return {k: {"label": v["label"], "ttl_min": v["ttl_min"],
                "votes_to_confirm": v["votes_to_confirm"]}
            for k, v in REPORT_TYPES.items()}
