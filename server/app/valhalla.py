# -*- coding: utf-8 -*-
"""عميل Valhalla.

ليش يمرّ التوجيه بالباكند ولا يكلّم التطبيق Valhalla مباشرة: نحقن في الطلب
ما لا يعرفه Valhalla — إغلاقات الطرق المؤكّدة من بلاغاتنا، وأزمنة المرور
الحيّة. التطبيق يستدعي مرة واحدة ويصل مسار يعرف الزحام.

نستخدم من Valhalla ثلاث خدمات:
  /route            — المسار والمناورات
  /trace_attributes — مطابقة مسار GPS على الطرق، ترجّع way_id لكل قطعة
  /locate           — أقرب طريق لنقطة، نحتاجه لتثبيت البلاغ على طريق
"""

import httpx
from fastapi import HTTPException

from .settings import VALHALLA_URL

# مهلة طويلة للمسارات الطويلة (بغداد ← البصرة) ومهلة قصيرة للبقية:
# طلب يأخذ أكثر من ثانيتين أثناء الملاحة لا قيمة له — السائق تجاوز
# التقاطع قبل ما يوصل الجواب
_TIMEOUT_ROUTE = httpx.Timeout(20.0, connect=3.0)
_TIMEOUT_LIVE = httpx.Timeout(4.0, connect=2.0)

_client = httpx.AsyncClient(base_url=VALHALLA_URL, timeout=_TIMEOUT_ROUTE)


async def _post(path: str, body: dict, timeout=None) -> dict:
    try:
        r = await _client.post(path, json=body, timeout=timeout)
    except httpx.ConnectError:
        raise HTTPException(503, "محرّك التوجيه مو شغّال — شغّل حاوية Valhalla")
    except httpx.TimeoutException:
        raise HTTPException(504, "محرّك التوجيه تأخّر عن الرد")

    if r.status_code != 200:
        # Valhalla يرجّع رسالة مفيدة في error_code — نمرّرها كما هي لأنها
        # تفرّق بين «ما لقيت طريقاً» و«الإحداثيات خارج الخريطة»
        detail = r.text[:300]
        try:
            j = r.json()
            detail = f"{j.get('error_code')}: {j.get('error', detail)}"
        except ValueError:
            pass
        raise HTTPException(502, f"محرّك التوجيه رفض الطلب — {detail}")

    return r.json()


async def route(locations: list[dict], costing: str = "auto",
                exclude_polygons: list | None = None,
                alternates: int = 2,
                avoid: dict[str, bool] | None = None) -> dict:
    """يحسب المسار. exclude_polygons هي إغلاقات الطرق من بلاغاتنا."""
    options: dict = {"maneuver_penalty": 5}

    # «التجنّب» رغبة لا منع: 0.0 تعني اسلكه فقط إذا ما في بديل. المشاة
    # والدراجة ما عندهم use_highways/use_tolls فنتجاهلها لهم
    if avoid and costing in ("auto", "bus", "motorcycle", "taxi"):
        if avoid.get("highways"):
            options["use_highways"] = 0.0
        if avoid.get("tolls"):
            options["use_tolls"] = 0.0
    if avoid and avoid.get("ferries"):
        options["use_ferry"] = 0.0

    body: dict = {
        "locations": locations,
        "costing": costing,
        "alternates": alternates,
        "directions_options": {"units": "kilometers"},
        # نبي أسماء الشوارع في كل مناورة: صياغة الجملة العربية في التطبيق
        # تحتاج الاسم، وبلا manoeuvre instructions نوفّر نطاقاً ما نحتاجه
        # لأننا نصيغ الجمل بأنفسنا
        "costing_options": {costing: options},
    }
    if exclude_polygons:
        body["exclude_polygons"] = exclude_polygons
    return await _post("/route", body)


_TRACE_ATTRS = ["edge.way_id", "edge.length", "edge.speed",
                "edge.speed_limit", "edge.road_class",
                "edge.begin_shape_index", "edge.end_shape_index"]


async def trace_attributes(shape: list[dict], costing: str = "auto",
                           timeout=None) -> dict:
    """يطابق مساراً على الطرق ويرجّع صفات كل قطعة.

    هذا ما يحوّل الإحداثيات الخام إلى way_id فعلي. نستخدمه لأمرين:
      ١. قراءات سرعة المستخدمين → زحام لكل قطعة طريق
      ٢. خط المسار المحسوب → معرّفات طرقه وحدود سرعتها

    الثاني هو السبيل الوحيد لمعرفة way_id من مسار: /route ما يرجّعها.
    """
    body = {
        "shape": shape,
        "costing": costing,
        "shape_match": "map_snap",
        "filters": {"attributes": _TRACE_ATTRS, "action": "include"},
    }
    return await _post("/trace_attributes", body,
                       timeout=timeout or _TIMEOUT_LIVE)


async def locate(lat: float, lon: float) -> dict:
    """أقرب طريق لنقطة. نستخدمه لتثبيت البلاغ على طريق لا على بناية جانبه."""
    body = {"locations": [{"lat": lat, "lon": lon}], "costing": "auto",
            "verbose": True}
    return await _post("/locate", body, timeout=_TIMEOUT_LIVE)


async def close() -> None:
    await _client.aclose()
