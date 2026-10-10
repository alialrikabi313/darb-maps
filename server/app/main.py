# -*- coding: utf-8 -*-
"""باكند darb: البلاغات والزحام والتوجيه.

    cd server
    docker compose up -d
    uvicorn app.main:app --reload --port 8080

التوثيق التفاعلي على /docs.
"""

import uuid
from contextlib import asynccontextmanager

from fastapi import Depends, FastAPI, Query
from fastapi.middleware.cors import CORSMiddleware
from sqlalchemy import text
from sqlalchemy.engine import Connection

from . import roads, valhalla
from .auth import register_device
from .db import get_conn, ping
from .routers import reports, routing, traffic
from .schemas import DeviceOut
from .settings import CORS_ORIGINS, TRACE_RETENTION_DAYS


@asynccontextmanager
async def lifespan(app: FastAPI):
    # نفحص القاعدة عند الإقلاع لا عند أول طلب: الفشل وقت الإقلاع واضح،
    # والفشل وقت أول طلب يظهر للمستخدم خطأ 500 غامضاً
    print(f"◄ PostGIS {ping()}")
    yield
    await valhalla.close()


app = FastAPI(title="darb", description="باكند تطبيق ملاحة darb",
              lifespan=lifespan)

app.add_middleware(CORSMiddleware, allow_origins=CORS_ORIGINS,
                   allow_methods=["*"], allow_headers=["*"])

app.include_router(reports.router)
app.include_router(traffic.router)
app.include_router(routing.router)


@app.get("/health")
def health(conn: Connection = Depends(get_conn)) -> dict:
    counts = conn.execute(text("""
        SELECT
          (SELECT COUNT(*) FROM report WHERE NOT is_removed
             AND expires_at > now()) AS live_reports,
          (SELECT COUNT(*) FROM traffic_state) AS traffic_segments,
          (SELECT COUNT(*) FROM device) AS devices
    """)).one()
    return {"ok": True, "live_reports": counts.live_reports,
            "traffic_segments": counts.traffic_segments,
            "devices": counts.devices}


@app.post("/auth/device", response_model=DeviceOut)
def new_device(conn: Connection = Depends(get_conn)) -> DeviceOut:
    """يسجّل جهازاً جديداً ويرجّع توكنه.

    بلا بريد ولا كلمة مرور: التطبيق يناديها مرة عند أول تشغيل ويحفظ التوكن.
    """
    did, token = register_device(conn)
    return DeviceOut(device_id=str(did), token=token)


@app.get("/roads/candidates")
def road_candidates(
    # بلا حدّ: limit=-1 ينهار على «LIMIT must not be negative» بـ500،
    # وlimit ضخم يرجّع آلاف خطوط GeoJSON
    limit: int = Query(default=100, ge=1, le=500),
    conn: Connection = Depends(get_conn),
) -> dict:
    """الطرق التي يمرّ بها الناس وما تعرفها الخريطة.

    مخرجها مُعدّ للتحرير في OSM: من يفتحها يرى أين يرسم. هذا ما يسدّ
    فجوة الطرق الناقصة التي تجعل خرائط ويز أغنى.
    """
    return {"stats": roads.stats(conn),
            "candidates": roads.promoted(conn, limit)}


@app.post("/maintenance/cleanup")
def cleanup(conn: Connection = Depends(get_conn)) -> dict:
    """ينظّف البلاغات المنتهية والقراءات القديمة.

    تُنادى من وظيفة دورية يومية. مكشوفة كـendpoint لا مربوطة بـcron داخلي
    لأن النشر قد يصير بنُسخ متعددة، وcron في كل نسخة يعني تنظيفاً متزامناً.
    """
    r = conn.execute(text("SELECT * FROM darb_cleanup(:d)"),
                     {"d": TRACE_RETENTION_DAYS}).one()
    return {"removed_reports": r.removed_reports,
            "removed_samples": r.removed_samples}
