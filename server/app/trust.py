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


def expiry_after_downvote(kind: str, created_at: datetime,
                          up_votes: int, down_votes: int) -> datetime:
    """وقت الانتهاء الجديد بعد صوت نفي.

    نحسبه من وقت الإنشاء لا من المتبقّي، وبصافي الأصوات لا بعدد النفي
    وحده. السبب خللان كانا هنا:

    ١. طرح مقدار ثابت من **المتبقّي** يجعل النفي الواحد قاتلاً لأي بلاغ
       قديم: حفرة عمرها عشرة أيام بقي لها أربعة، والخصم 4.9 يوم — فنفي
       واحد يقتلها. جرّبناه فماتت فوراً.
    ٢. التأييد ما كان يدخل الحساب إطلاقاً، فرادار أكّده عشرون سائقاً
       يقتله جهاز واحد مجهول.

    الآن: العمر المسموح = الصلاحية الأصلية مضروبة في معامل صافي الأصوات،
    محسوبة من وقت الإنشاء. فالبلاغ المؤيَّد يصمد، والمنفيّ بلا تأييد
    يموت بعد عدد النفي الذي قرّرناه في REPORT_DOWNVOTE_DECAY.
    """
    ttl = ttl_minutes(kind)

    # صافي النفي: كل تأييد مستقلّ يلغي نصف نفي. نستثني صوت صاحب البلاغ
    # (البلاغ يبدأ بـup_votes=1 وهو صوته) — لا يحمي نفسه من تكذيب غيره،
    # وبلا الاستثناء كانت ثلاثة نفي لا تكفي لقتل بلاغ لم يؤيّده أحد.
    # ونصف التأثير كي يبقى النفي أقوى: بلاغ خاطئ يُخرج السائق من طريقه
    independent_up = max(0, up_votes - 1)
    net_down = max(0.0, down_votes - independent_up * 0.5)

    factor = max(0.0, 1.0 - net_down * REPORT_DOWNVOTE_DECAY)
    allowed = timedelta(minutes=ttl * factor)

    now = datetime.now(timezone.utc)
    new = created_at + allowed

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
