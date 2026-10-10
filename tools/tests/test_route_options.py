# -*- coding: utf-8 -*-
"""اختبارات تفضيلات المسار وحدّ الطلبات.

الحالات من أشياء انكسرت فعلاً أو كادت وقت إضافة الخيارات:
«تجنّب الطرق السريعة» على مسار مشاة، والنفس الطويل لقاموس الحدّ.

    cd tools && python -m pytest tests/test_route_options.py -v
"""

import sys
import time
from collections import deque
from pathlib import Path

_REPO = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(_REPO / "tools"))
sys.path.insert(0, str(_REPO / "server"))

from app import valhalla  # noqa: E402


def _options(costing: str, **avoid) -> dict:
    """يبني الجسم بلا شبكة: نستبدل الإرسال ونقرأ ما كان سيُرسَل.

    المنطق الذي نفحصه يسكن داخل route()، وفصله في دالة ثانية كان يعني
    تجريداً لمساعد يُستدعى مرة واحدة. فنعترض الإرسال بدلاً عنه.
    """
    captured: dict = {}

    async def fake_post(path, body):
        captured.update(body)
        return {"trip": {}}

    real = valhalla._post
    valhalla._post = fake_post
    try:
        import asyncio
        asyncio.run(valhalla.route(
            [{"lat": 33.3, "lon": 44.4}, {"lat": 33.2, "lon": 44.3}],
            costing=costing, avoid=avoid))
    finally:
        valhalla._post = real

    return captured["costing_options"][costing]


class TestAvoidOptions:
    def test_highways_become_zero_preference(self):
        # 0.0 رغبةٌ لا منع: ساكن طريق محمد القاسم يبقى له مسار
        assert _options("auto", highways=True)["use_highways"] == 0.0

    def test_nothing_set_when_not_asked(self):
        o = _options("auto")
        assert "use_highways" not in o and "use_tolls" not in o

    def test_pedestrian_ignores_highway_option(self):
        """المشاة ما عندهم use_highways.

        ڤالهالا يرفض الطلب كلّه بـ400 على خيار لا يعرفه النمط — فكان
        «تجنّب السريع» مفعّلاً ثم تبديل النمط لـ«مشياً» يقتل التوجيه.
        """
        o = _options("pedestrian", highways=True, tolls=True)
        assert "use_highways" not in o
        assert "use_tolls" not in o

    def test_ferries_apply_to_every_mode(self):
        # المعدية يركبها الماشي والسائق، فالخيار لكل الأنماط
        assert _options("pedestrian", ferries=True)["use_ferry"] == 0.0
        assert _options("auto", ferries=True)["use_ferry"] == 0.0

    def test_maneuver_penalty_survives(self):
        # الخيارات تُضاف ولا تستبدل: فقدان maneuver_penalty يعني مساراً
        # يلف في الأزقّة لأن اللفّة صارت مجّانية
        assert _options("auto", highways=True)["maneuver_penalty"] == 5


class TestRateWindow:
    """النافذة المنزلقة — منطق guards.RateLimiter بلا ASGI.

    نعيد المنطق هنا لأن اختباره عبر الوسيط يحتاج تطبيقاً كاملاً وخادماً،
    والذي ينكسر فعلاً هو حساب النافذة لا تركيب الوسيط.
    """

    @staticmethod
    def _prune(window: deque, now: float) -> None:
        while window and now - window[0] > 60.0:
            window.popleft()

    def test_old_hits_fall_out_of_the_window(self):
        now = time.monotonic()
        w = deque([now - 61, now - 30, now - 1])
        self._prune(w, now)
        assert len(w) == 2, "القراءة الأقدم من دقيقة بقيت تحسب"

    def test_burst_inside_the_window_counts(self):
        now = time.monotonic()
        w = deque([now - i * 0.1 for i in range(10)])
        self._prune(w, now)
        assert len(w) == 10
