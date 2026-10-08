# -*- coding: utf-8 -*-
"""ثقة البلاغ: متى يُعرض، ومتى يُعدّ مؤكّداً، ومتى يموت.

المسألة الحقيقية هنا ليست حسابية بل اجتماعية: بلاغ واحد لا يُثبت شيئاً،
وانتظار التأكيد يعني أن أول مُبلِّغ لا يفيد أحداً فلا يُبلِّغ أحد — حلقة
مفرغة تقتل التطبيق في أول شهر. فنعرض غير المؤكّد موسوماً بأنه غير مؤكّد،
ونترك المستخدم يقرّر.

كل العتبات في tools/config.py لأنها قرارات صاحب المشروع لا قرارات كود.
"""

from datetime import datetime, timedelta, timezone

from .settings import (
    REPORT_TYPES, REPORT_DOWNVOTE_DECAY, REPORT_SHOW_UNCONFIRMED,
)


def ttl_minutes(kind: str) -> int:
    return REPORT_TYPES[kind]["ttl_min"]


def initial_expiry(kind: str, reputation: int = 0) -> datetime:
    """وقت انتهاء البلاغ عند إنشائه.

    جهاز ذو سمعة يعيش بلاغه أطول: أثبت صدقه مراراً فنعطيه مهلة أوسع قبل
    ما يسقط بلا تصويت. السقف ×1.5 كي لا تصير السمعة سلطة مطلقة — جهاز
    حسن السمعة قد يبلّغ خطأ بنيّة سليمة
    """
    ttl = ttl_minutes(kind)
    bonus = min(0.5, max(0.0, reputation / 100.0))
    return datetime.now(timezone.utc) + timedelta(minutes=ttl * (1 + bonus))


def expiry_after_downvote(kind: str, current: datetime,
                          down_votes: int) -> datetime:
    """وقت الانتهاء الجديد بعد صوت نفي.

    كل نفي يسحب نسبة ثابتة من الصلاحية الأصلية لا من المتبقّي: السحب من
    المتبقّي يجعل أول نفي قاتلاً وآخر نفي بلا أثر، وهو مقلوب المطلوب.
    """
    cut = timedelta(minutes=ttl_minutes(kind) * REPORT_DOWNVOTE_DECAY)
    new = current - cut
    now = datetime.now(timezone.utc)

    # النفي الكافي يقتل البلاغ فوراً لا يقرّبه من الموت
    return now if new <= now else new


def is_confirmed(kind: str, up_votes: int, down_votes: int) -> bool:
    need = REPORT_TYPES[kind]["votes_to_confirm"]
    return (up_votes - down_votes) >= need


def confidence(kind: str, up_votes: int, down_votes: int,
               age_minutes: float) -> float:
    """ثقة بين 0 و1 تُعرض للمستخدم نسبةً.

    ثلاثة عوامل: صافي الأصوات نسبةً للعتبة، وعمر البلاغ (القديم أقل ثقة
    حتى بلا نفي لأن الحال يتغيّر)، والنفي يخصم أكثر مما يضيف التأييد —
    بلاغ خاطئ يُخرِج السائق من طريقه، وبلاغ فائت يكلّفه دقائق فقط.
    """
    need = REPORT_TYPES[kind]["votes_to_confirm"]
    ttl = ttl_minutes(kind)

    net = up_votes - 1.5 * down_votes
    vote_score = max(0.0, min(1.0, net / need))

    # الطزاجة تنحدر خطّياً مع العمر نسبةً لصلاحية النوع، ولا تنزل تحت 0.2
    # كي لا يصير بلاغ الحفرة بعد أسبوع بثقة صفر وهو صحيح
    freshness = max(0.2, 1.0 - age_minutes / ttl)

    return round(vote_score * freshness, 2)


def should_show(kind: str, up_votes: int, down_votes: int) -> bool:
    if is_confirmed(kind, up_votes, down_votes):
        return True
    # النفي الصريح يخفي البلاغ حتى لو كانت سياستنا عرض غير المؤكّد:
    # «غير مؤكّد» ليس «نفاه غيري»
    if down_votes >= up_votes:
        return False
    return REPORT_SHOW_UNCONFIRMED


def reputation_delta(is_up: bool) -> int:
    """تغيّر سمعة صاحب البلاغ عند تصويت عليه.

    غير متناظر بقصد: نحتاج بلاغات كثيرة لبناء السمعة، وأخطاء قليلة
    لهدمها. التناظر يسمح لمن يرسل بلاغات عشوائية بأن يربح بالحجم.
    """
    return 1 if is_up else -3
