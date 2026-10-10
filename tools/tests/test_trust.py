# -*- coding: utf-8 -*-
"""اختبارات ثقة البلاغات.

الحالات من سلوك اتفقنا عليه في app/trust.py، وكل واحدة تحمي قراراً:
النفي يخصم أكثر مما يضيف التأييد، والسمعة تُبنى ببطء وتُهدم بسرعة،
وغير المؤكّد يُعرض ولا يُخفى.

    cd tools && python -m pytest tests/ -v
"""

import sys
from pathlib import Path
from datetime import datetime, timedelta, timezone

_REPO = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(_REPO / "tools"))
sys.path.insert(0, str(_REPO / "server"))

from config import REPORT_TYPES, REPORT_DOWNVOTE_DECAY  # noqa: E402
from app import trust  # noqa: E402


def _now():
    return datetime.now(timezone.utc)


class TestInitialExpiry:
    def test_matches_type_ttl(self):
        exp = trust.initial_expiry("jam", reputation=0)
        minutes = (exp - _now()).total_seconds() / 60
        assert abs(minutes - REPORT_TYPES["jam"]["ttl_min"]) < 1

    def test_reputation_extends_life(self):
        plain = trust.initial_expiry("crash", reputation=0)
        trusted = trust.initial_expiry("crash", reputation=100)
        assert trusted > plain

    def test_reputation_bonus_is_capped(self):
        # السمعة ما تصير سلطة مطلقة: جهاز حسن السمعة قد يبلّغ خطأ بنيّة
        # سليمة، فنسقف الإضافة عند ×1.5
        huge = trust.initial_expiry("crash", reputation=10_000)
        minutes = (huge - _now()).total_seconds() / 60
        assert minutes <= REPORT_TYPES["crash"]["ttl_min"] * 1.5 + 1

    def test_negative_reputation_does_not_shorten(self):
        # الجهاز سيّئ السمعة بلاغه يعيش عمره الطبيعي؛ الأصوات هي التي
        # تقتله. تقصير العمر مسبقاً عقاب مزدوج
        bad = trust.initial_expiry("crash", reputation=-50)
        minutes = (bad - _now()).total_seconds() / 60
        assert minutes >= REPORT_TYPES["crash"]["ttl_min"] - 1


class TestDownvoteDecay:
    """الحساب من وقت الإنشاء وبصافي الأصوات.

    خللان كانا هنا واكتشفهما التدقيق:
    ١. الخصم من **المتبقّي** يجعل نفياً واحداً يقتل أي بلاغ قديم.
    ٢. التأييد ما كان يدخل الحساب إطلاقاً.
    """

    def test_one_downvote_cuts_fraction_of_ttl(self):
        ttl = REPORT_TYPES["pothole"]["ttl_min"]
        created = _now()

        after = trust.expiry_after_downvote("pothole", created, 1, 1)
        life_min = (after - created).total_seconds() / 60

        # صوت صاحب البلاغ لا يحميه، فالصافي = 1 نفي كامل
        expected = ttl * (1 - REPORT_DOWNVOTE_DECAY)
        assert abs(life_min - expected) < 1

    def test_old_backed_report_survives_one_downvote(self):
        """الخلل الأصلي: حفرة عمرها عشرة أيام يقتلها نفي واحد مهما
        كان عدد مؤيّديها.

        الخصم كان 0.35 × 14 يوماً = 4.9 يوم من **المتبقّي** (4 أيام)،
        فتموت فوراً — والتأييد لم يكن يدخل الحساب إطلاقاً.

        الآن: البلاغ القديم المؤيَّد يصمد، وغير المؤيَّد يموت. وهذا
        هو المقصود — نفيٌ لم يعارضه أحد حكمٌ مقبول.
        """
        ttl = REPORT_TYPES["pothole"]["ttl_min"]
        created = _now() - timedelta(minutes=ttl * 0.7)

        backed = trust.expiry_after_downvote("pothole", created, 6, 1)
        assert backed > _now() + timedelta(hours=1),             "بلاغ قديم أيّده خمسة مستقلّين مات بنفي واحد"

        lonely = trust.expiry_after_downvote("pothole", created, 1, 1)
        assert lonely <= _now() + timedelta(seconds=2),             "بلاغ قديم بلا تأييد نجا من النفي"

    def test_author_vote_does_not_protect(self):
        """صاحب البلاغ لا يحمي بلاغه من تكذيب غيره.

        البلاغ يبدأ بـup_votes=1 وهو صوت صاحبه. عدّه حمايةً كان يجعل
        ثلاثة نفي لا تكفي لقتل بلاغ لم يؤيّده أحد غير صاحبه.
        """
        created = _now()
        alone = trust.expiry_after_downvote("jam", created, 1, 2)
        backed = trust.expiry_after_downvote("jam", created, 3, 2)
        assert backed > alone

    def test_upvotes_protect_against_downvotes(self):
        """رادار أكّده عشرون سائقاً لا يقتله جهاز واحد."""
        ttl = REPORT_TYPES["speed_camera"]["ttl_min"]
        created = _now() - timedelta(minutes=ttl * 0.3)

        lonely = trust.expiry_after_downvote("speed_camera", created, 1, 1)
        backed = trust.expiry_after_downvote("speed_camera", created, 20, 1)

        assert backed > lonely
        assert backed > _now() + timedelta(days=1)

    def test_enough_downvotes_kill_immediately(self):
        # ثلاثة نفي بلا تأييد تقتل بلاغاً جديداً (0.35 × 3 > 1)
        created = _now()
        assert trust.expiry_after_downvote("jam", created, 1, 3)             <= _now() + timedelta(seconds=2)

    def test_never_returns_past_time(self):
        # وقت انتهاء في الماضي يفسد فرز القاعدة. نرجّع «الآن» لا قبله
        created = _now() - timedelta(days=30)
        assert trust.expiry_after_downvote("crash", created, 1, 1) >=             _now() - timedelta(seconds=2)

    def test_downvotes_accumulate(self):
        created = _now()
        one = trust.expiry_after_downvote("pothole", created, 1, 1)
        two = trust.expiry_after_downvote("pothole", created, 1, 2)
        assert two < one, "النفي الثاني ما أثّر"


class TestConfirmation:
    def test_needs_type_threshold(self):
        need = REPORT_TYPES["jam"]["votes_to_confirm"]
        assert not trust.is_confirmed("jam", need - 1, 0)
        assert trust.is_confirmed("jam", need, 0)

    def test_downvotes_offset_upvotes(self):
        need = REPORT_TYPES["jam"]["votes_to_confirm"]
        assert not trust.is_confirmed("jam", need, 1)

    def test_crash_confirms_with_two(self):
        # الحادث عتبته أقل من الزحام: أظهر وأسهل تمييزاً، والزحام يختلف
        # تقديره بين سائق وسائق
        assert trust.is_confirmed("crash", 2, 0)


class TestConfidence:
    def test_between_zero_and_one(self):
        for up, down, age in [(1, 0, 0), (5, 0, 10), (1, 5, 100), (0, 0, 0)]:
            c = trust.confidence("crash", up, down, age)
            assert 0.0 <= c <= 1.0

    def test_downvote_hurts_more_than_upvote_helps(self):
        # بلاغ خاطئ يُخرج السائق من طريقه، وبلاغ فائت يكلّفه دقائق — فالخطأ
        # أغلى، والنفي يخصم 1.5 مقابل تأييد 1
        base = trust.confidence("crash", 2, 0, 0)
        with_up = trust.confidence("crash", 3, 0, 0)
        with_down = trust.confidence("crash", 2, 1, 0)

        gained = with_up - base
        lost = base - with_down
        assert lost > gained

    def test_age_lowers_confidence(self):
        fresh = trust.confidence("jam", 3, 0, 0)
        stale = trust.confidence("jam", 3, 0, REPORT_TYPES["jam"]["ttl_min"])
        assert stale < fresh

    def test_freshness_has_a_floor(self):
        # بلاغ الحفرة بعد أسبوع صحيح غالباً — الحفرة ما تمتلئ وحدها.
        # فالطزاجة ما تنزل تحت 0.2
        old = trust.confidence("pothole", 5, 0, 100_000)
        assert old > 0.0


class TestShouldShow:
    def test_confirmed_always_shows(self):
        assert trust.should_show("crash", 5, 0)

    def test_unconfirmed_shows_by_policy(self):
        # إخفاء غير المؤكّد يعني أن أول مُبلِّغ لا يفيد أحداً، وهي حلقة
        # مفرغة تقتل التطبيق في أول شهر
        assert trust.should_show("jam", 1, 0)

    def test_explicit_denial_hides(self):
        # «غير مؤكّد» ليس «نفاه غيري»
        assert not trust.should_show("jam", 1, 1)
        assert not trust.should_show("jam", 1, 3)


class TestReputation:
    def test_asymmetric_by_design(self):
        # التناظر يسمح لمن يرسل بلاغات عشوائية بأن يربح بالحجم
        up = trust.reputation_delta(True)
        down = trust.reputation_delta(False)
        assert up > 0 > down
        assert abs(down) > up
