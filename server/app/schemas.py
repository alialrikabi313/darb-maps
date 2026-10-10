# -*- coding: utf-8 -*-
"""أشكال الطلب والرد.

نوع البلاغ يُتحقَّق منه مقابل REPORT_TYPES لا مقابل Enum مكتوب هنا: إضافة
نوع بلاغ قرار صاحب المشروع في config.py، ونسخه Enum ثانية يعني تعديلين
لكل نوع جديد وفرصة نسيان أحدهما.
"""

from datetime import datetime
from typing import Literal

from pydantic import BaseModel, Field, field_validator

from .settings import REPORT_TYPES


class DeviceOut(BaseModel):
    device_id: str
    token: str


class Coord(BaseModel):
    lat: float = Field(ge=-90, le=90)
    lon: float = Field(ge=-180, le=180)


class ReportIn(BaseModel):
    kind: str
    lat: float = Field(ge=-90, le=90)
    lon: float = Field(ge=-180, le=180)
    # اتجاه المُبلِّغ: الرادار والسيطرة على جهة واحدة، وتنبيه السائق
    # المعاكس يفقده الثقة بالتطبيق
    heading: float | None = Field(default=None, ge=0, lt=360)
    note: str | None = Field(default=None, max_length=280)

    @field_validator("kind")
    @classmethod
    def known_kind(cls, v: str) -> str:
        if v not in REPORT_TYPES:
            raise ValueError(
                f"نوع بلاغ غير معروف «{v}» — المتاح: {', '.join(REPORT_TYPES)}")
        return v


class ReportOut(BaseModel):
    id: int
    kind: str
    label: str
    lat: float
    lon: float
    heading: float | None
    note: str | None
    created_at: datetime
    expires_at: datetime
    up_votes: int
    down_votes: int
    confirmed: bool
    confidence: float
    # عدد البلاغات المجمّعة في هذا: الواجهة تعرض «٣ بلاغات» لا ثلاث أيقونات
    # متراكبة على نفس التقاطع
    cluster_size: int = 1
    # مسافة البلاغ من نقطة الاستعلام — الواجهة ترتّب بها، والملاحة تقرّر
    # متى تنبّه
    distance_m: float | None = None


class VoteIn(BaseModel):
    is_up: bool


class TracePoint(BaseModel):
    lat: float = Field(ge=-90, le=90)
    lon: float = Field(ge=-180, le=180)
    # الطابع الزمني بالثواني من عهد يونكس. Valhalla يحتاجه لمطابقة المسار
    time: float
    # سرعة الجهاز من GPS كم/س. نرسلها ولا نحسبها من الفروق لأن GPS أدقّ
    # في السرعة منه في الموقع — دوبلر لا تفاضل
    speed_kmh: float | None = None


class TraceIn(BaseModel):
    # أقل من 4 نقاط ما تنفع للمطابقة، وأكثر من 200 يبطّئ Valhalla ويكبّر
    # الرحلة المرسلة فيضرّ الخصوصية بلا فائدة
    points: list[TracePoint] = Field(min_length=4, max_length=200)


class TrafficSegment(BaseModel):
    way_id: int
    level: str
    avg_speed_kmh: float
    free_speed_kmh: float
    samples: int
    updated_at: datetime


class RouteIn(BaseModel):
    # عشر نقاط سقفاً: البداية والنهاية وثماني محطات بينهما. أكثر من ذلك
    # يخنق ڤالهالا ويطوّل زمن الردّ أكثر مما يحتمله شاشة انتظار
    locations: list[Coord] = Field(min_length=2, max_length=10)

    # نحصر الأنماط بما جرّبناه فعلاً على رسم العراق. القائمة المفتوحة
    # كانت تمرّر أي نصّ لڤالهالا فيرجع 400 بلغة إنجليزية ما نعرضها
    costing: Literal["auto", "bus", "bicycle", "pedestrian",
                     "motorcycle", "taxi"] = "auto"

    # هل نتجنّب الإغلاقات المبلَّغ عنها. نتركها خياراً لأن الإغلاق قد يكون
    # خاطئاً، والمستخدم العارف بطريقه يبي يراه على كل حال
    avoid_closures: bool = True

    # تفضيلات المسار. ڤالهالا ما عنده «امنع» بل «رغبة» بين 0 و1، فالتجنّب
    # عندنا = رغبة صفر: يسلكه فقط إذا ما في بديل إطلاقاً. وهذا هو المطلوب
    # — منعٌ قاطع يرجّع «ما في طريق» لمن يسكن على طريق سريع
    avoid_highways: bool = False
    avoid_tolls: bool = False
    avoid_ferries: bool = False

    alternates: int = Field(default=2, ge=0, le=3)
