# -*- coding: utf-8 -*-
"""إعدادات الباكند.

قيم المجال (أنواع البلاغات، عتبات الزحام، الخصوصية) ما تُنسخ هنا — تُقرأ من
tools/config.py وهو مصدرها الوحيد في المشروع. السبب: نسخة ثانية تفترق عن
الأولى بعد أول تعديل، وتصير القاعدة تحسب عتبة والتطبيق يعرض غيرها.

ما يخصّ السيرفر وحده (السرّ، أصل الطلبات المسموح) من متغيّرات البيئة.
"""

import os
import sys
from pathlib import Path

_REPO = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(_REPO / "tools"))

from config import (  # noqa: E402  — لازم بعد تعديل sys.path
    REPORT_TYPES, REPORT_DOWNVOTE_DECAY, REPORT_SHOW_UNCONFIRMED,
    REPORT_SEARCH_RADIUS_M, REPORT_CLUSTER_RADIUS_M,
    TRAFFIC_LEVELS, DEFAULT_FREE_SPEED_KMH, TRAFFIC_MIN_SAMPLES,
    TRAFFIC_SAMPLE_TTL_MIN, TRACE_RETENTION_DAYS, TRACE_TRIM_ENDPOINTS_M,
    ROAD_CANDIDATE_MIN_LENGTH_M, ROAD_CANDIDATE_MIN_OFFSET_M,
    ROAD_CANDIDATE_MERGE_RADIUS_M, ROAD_CANDIDATE_PROMOTE_HITS,
    VALHALLA_URL, API_PORT, pg_dsn,
)

# سرّ توقيع التوكن.
#
# الفحص معكوس عمداً: التطوير هو ما يحتاج إعلاناً صريحاً، لا الإنتاج.
# كان `IS_PROD = DARB_ENV == "production"` فأي نشر بـDARB_ENV غير مضبوط
# أو مكتوب «prod» أو «Production» يسقط على السرّ المكتوب في هذا الملف
# داخل الريبو — وبه يُزوَّر توكن أي جهاز، ويُتجاوَز الحظر، ويُفتح CORS
# للجميع. أي أن الخطأ الأشيع (نسيان متغيّر) كان يعطي أسوأ نتيجة.
IS_DEV = os.getenv("DARB_DEV") == "1"
JWT_SECRET = os.getenv("DARB_JWT_SECRET", "dev-secret-darb" if IS_DEV else "")

if not JWT_SECRET:
    sys.exit(
        "DARB_JWT_SECRET مطلوب.\n"
        "  للإنتاج:  اضبط DARB_JWT_SECRET بسرّ عشوائي طويل\n"
        "  للتطوير:  اضبط DARB_DEV=1 لاستخدام سرّ التطوير المعروف"
    )

IS_PROD = not IS_DEV

JWT_ALG = "HS256"
# التوكن طويل العمر: الجهاز ما عنده كلمة مرور يجدّد بها، وانتهاؤه يعني
# فقدان سمعة الجهاز وتاريخ بلاغاته
JWT_TTL_DAYS = 365

DB_DSN = os.getenv("DARB_DB_DSN", pg_dsn())

# أصل الطلبات: التطبيق جوّال فما يرسل Origin، والسماح الكامل هنا يخصّ
# صفحة المعاينة في التطوير فقط
CORS_ORIGINS = ["*"] if IS_DEV else [
    o for o in os.getenv("DARB_CORS_ORIGINS", "").split(",") if o
]

__all__ = [
    "REPORT_TYPES", "REPORT_DOWNVOTE_DECAY", "REPORT_SHOW_UNCONFIRMED",
    "REPORT_SEARCH_RADIUS_M", "REPORT_CLUSTER_RADIUS_M", "TRAFFIC_LEVELS",
    "DEFAULT_FREE_SPEED_KMH", "TRAFFIC_MIN_SAMPLES", "TRAFFIC_SAMPLE_TTL_MIN",
    "TRACE_RETENTION_DAYS", "TRACE_TRIM_ENDPOINTS_M", "VALHALLA_URL",
    "ROAD_CANDIDATE_MIN_LENGTH_M", "ROAD_CANDIDATE_MIN_OFFSET_M",
    "ROAD_CANDIDATE_MERGE_RADIUS_M", "ROAD_CANDIDATE_PROMOTE_HITS",
    "API_PORT", "IS_PROD", "JWT_SECRET", "JWT_ALG", "JWT_TTL_DAYS", "DB_DSN",
    "CORS_ORIGINS",
]
