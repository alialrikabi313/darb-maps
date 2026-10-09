# -*- coding: utf-8 -*-
"""كشف الطرق الناقصة من آثار المستخدمين.

المشكلة المقيسة: 8% فقط من طرق العراق مسمّاة في OSM، وطرق كاملة ناقصة
في المدن الصغيرة. هذا الفارق هو ما يجعل خرائط ويز أغنى — ملايين
السيارات ترسم عنده الطرق الجديدة تلقائياً.

المنطق: نمرّر أثر GPS على /trace_attributes. Valhalla يرجّع حواف تغطّي
جزءاً من الأثر. الجزء الذي **لا** تغطّيه حافة يعني أن السائق مرّ من
مكان لا طريق فيه عند الخريطة. نخزّنه مرشّحاً، ويرتفع عدّاده كلما مرّ
جهاز آخر، وعند العتبة يصير جديراً بالعرض للتحرير في OSM.

الخصوصية: نخزّن القطعة غير المطابَقة لا الأثر كاملاً، وبلا ربط بجهاز —
نفس سياسة traffic_sample. والقطع التي تمرّ قرب أول الرحلة وآخرها محذوفة
أصلاً قبل أن تصلنا.

ما لا يسويه: لا يسمّي الطريق ولا يحدّد اتجاهه. يقول «هنا طريق ما
يعرفه أحد» — والباقي عمل بشر.
"""

from sqlalchemy import text
from sqlalchemy.engine import Connection

from .settings import (
    ROAD_CANDIDATE_MIN_LENGTH_M, ROAD_CANDIDATE_MIN_OFFSET_M,
    ROAD_CANDIDATE_MERGE_RADIUS_M, ROAD_CANDIDATE_PROMOTE_HITS,
)


def unmatched_runs(points: list, edges: list) -> list[list]:
    """يرجّع سلاسل النقاط التي ما غطّتها أي حافة.

    Valhalla يعطي لكل حافة begin/end_shape_index على الأثر الذي أرسلناه.
    ما بين الحواف فجوات — وهي ما نبحث عنه.
    """
    covered = [False] * len(points)
    for e in edges:
        i0 = e.get("begin_shape_index")
        i1 = e.get("end_shape_index")
        if i0 is None or i1 is None:
            continue
        for i in range(max(0, i0), min(len(points), i1 + 1)):
            covered[i] = True

    runs: list[list] = []
    current: list = []
    for i, p in enumerate(points):
        if covered[i]:
            if len(current) >= 2:
                runs.append(current)
            current = []
        else:
            current.append(p)
    if len(current) >= 2:
        runs.append(current)

    return runs


def _wkt_line(points: list) -> str:
    coords = ", ".join(f"{p.lon} {p.lat}" for p in points)
    return f"LINESTRING({coords})"


def record_candidates(conn: Connection, points: list, edges: list) -> int:
    """يسجّل القطع غير المطابَقة. يرجّع عدد المرشّحين الذين مسّهم.

    المرشّح القريب من مرشّح سابق يرفع عدّاده بدل ما يُضاف جديداً: الطريق
    الواحد تمرّ عليه سيارات بمسارات متفاوتة بعشرات الأمتار.
    """
    runs = unmatched_runs(points, edges)
    if not runs:
        return 0

    touched = 0

    for run in runs:
        wkt = _wkt_line(run)

        # الطول والبعد عن أقرب طريق معروف يُحسبان في القاعدة: PostGIS
        # أدقّ من تقريب مستوٍ على أطوال مئات الأمتار
        length_m = conn.execute(
            text("SELECT ST_Length(ST_GeogFromText(:w))"), {"w": wkt}
        ).scalar_one()

        if length_m < ROAD_CANDIDATE_MIN_LENGTH_M:
            continue

        existing = conn.execute(text("""
            SELECT id FROM road_candidate
            WHERE ST_DWithin(geom, ST_GeogFromText(:w), :r)
            ORDER BY ST_Distance(geom, ST_GeogFromText(:w))
            LIMIT 1
        """), {"w": wkt, "r": ROAD_CANDIDATE_MERGE_RADIUS_M}).scalar()

        if existing is not None:
            conn.execute(text("""
                UPDATE road_candidate
                   SET hits = hits + 1,
                       last_seen = now(),
                       is_promoted = (hits + 1) >= :need
                 WHERE id = :i
            """), {"i": existing, "need": ROAD_CANDIDATE_PROMOTE_HITS})
        else:
            conn.execute(text("""
                INSERT INTO road_candidate (geom, length_m)
                VALUES (ST_GeogFromText(:w), :len)
            """), {"w": wkt, "len": length_m})

        touched += 1

    return touched


def promoted(conn: Connection, limit: int = 100) -> list[dict]:
    """الطرق المرشّحة الجديرة بالتحرير، الأكثر مروراً أولاً."""
    rows = conn.execute(text("""
        SELECT id, hits, length_m, first_seen, last_seen,
               ST_AsGeoJSON(geom::geometry) AS geojson
        FROM road_candidate
        WHERE is_promoted
        ORDER BY hits DESC, length_m DESC
        LIMIT :n
    """), {"n": limit}).fetchall()

    return [{
        "id": r.id,
        "hits": r.hits,
        "length_m": round(r.length_m),
        "first_seen": r.first_seen,
        "last_seen": r.last_seen,
        "geometry": r.geojson,
    } for r in rows]


def stats(conn: Connection) -> dict:
    row = conn.execute(text("""
        SELECT count(*) AS total,
               count(*) FILTER (WHERE is_promoted) AS promoted,
               COALESCE(SUM(length_m) FILTER (WHERE is_promoted), 0) AS km
        FROM road_candidate
    """)).one()

    return {
        "candidates": row.total,
        "promoted": row.promoted,
        "promoted_km": round(row.km / 1000, 1),
        "promote_at_hits": ROAD_CANDIDATE_PROMOTE_HITS,
        "min_length_m": ROAD_CANDIDATE_MIN_LENGTH_M,
        "min_offset_m": ROAD_CANDIDATE_MIN_OFFSET_M,
    }
