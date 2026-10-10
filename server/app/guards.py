# -*- coding: utf-8 -*-
"""حرّاس الطلبات: توكن الصيانة، وحدّ عدد الطلبات.

الاثنان كانا ناقصين كلياً: /maintenance/cleanup و/traffic/aggregate
مكشوفتان لأي أحد على الشبكة، ولا حدّ على أي مسار. من ينادي cleanup
بالتكرار يمسح البلاغات الحيّة، ومن يرسل آثاراً بلا توقّف يملأ القاعدة.
"""

import hmac
import time
from collections import deque

from fastapi import Header, HTTPException, Request
from starlette.middleware.base import BaseHTTPMiddleware
from starlette.responses import JSONResponse

from .settings import ADMIN_TOKEN, RATE_LIMIT_PER_MIN


def require_admin(x_darb_admin: str = Header(default="")) -> None:
    """يحمي مسارات الصيانة.

    compare_digest لا == : المقارنة العادية تنتهي عند أول حرف مختلف،
    فزمنها يسرّب طول البادئة الصحيحة. السرّ هنا قصير ويُخمَّن بذلك.
    """
    if not hmac.compare_digest(x_darb_admin, ADMIN_TOKEN):
        raise HTTPException(401, "هذا المسار للصيانة — يحتاج X-Darb-Admin")


class RateLimiter(BaseHTTPMiddleware):
    """نافذة منزلقة لكل عنوان.

    في الذاكرة لا في Redis: نسخة واحدة من السيرفر هي وضعنا الآن. وإذا
    تعدّدت النسخ يصير الحدّ لكل نسخة — أي أرخى مما يبدو لا أقسى، فالعطل
    في الاتجاه الآمن.

    الصحّة والتوثيق خارج الحدّ: مراقِب يسأل /health كل ثانية سلوك سليم
    ولا يستحق حظراً.
    """

    _EXEMPT = ("/health", "/docs", "/openapi.json", "/redoc")

    def __init__(self, app) -> None:
        super().__init__(app)
        self._hits: dict[str, deque[float]] = {}

    async def dispatch(self, request: Request, call_next):
        if request.url.path.startswith(self._EXEMPT):
            return await call_next(request)

        # العنوان من X-Forwarded-For إن كان خلف وسيط، وإلا من الاتصال.
        # أول عنوان في السلسلة هو العميل
        fwd = request.headers.get("x-forwarded-for", "")
        who = (fwd.split(",")[0].strip() if fwd
               else (request.client.host if request.client else "?"))

        now = time.monotonic()
        window = self._hits.setdefault(who, deque())

        while window and now - window[0] > 60.0:
            window.popleft()

        if len(window) >= RATE_LIMIT_PER_MIN:
            return JSONResponse(
                {"detail": "طلبات كثيرة — جرّب بعد دقيقة"},
                status_code=429,
                headers={"Retry-After": "60"},
            )

        window.append(now)

        # كنس العناوين الخاملة. بلاه ينمو القاموس بعنوان لكل زائر عابر
        # إلى أن تمتلئ الذاكرة — وهو تسريب بطيء لا ينكشف في الاختبار
        if len(self._hits) > 10_000:
            dead = [k for k, v in self._hits.items()
                    if not v or now - v[-1] > 300.0]
            for k in dead:
                self._hits.pop(k, None)

        return await call_next(request)
