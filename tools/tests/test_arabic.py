# -*- coding: utf-8 -*-
"""اختبارات تطبيع العربية.

كل حالة هنا اسم شاهدناه فعلاً في بيانات OSM لبغداد، أو صيغة يكتبها
المستخدم عند البحث. ما في حالة مخترَعة: الأشكال الغريبة للأسماء العربية
لا تُخترع، تُصادَف.

    cd tools && python -m pytest tests/ -v
"""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from arabic import normalize, search_tokens, fts_text  # noqa: E402


class TestNormalizeAlif:
    """الألف بأشكالها. OSM العراق يخلطها في نفس المدينة."""

    def test_hamza_above(self):
        # «أبو غريب» و«ابو غريب» كلاهما في OSM
        assert normalize("أبو غريب") == normalize("ابو غريب")

    def test_hamza_below(self):
        # «إبراهيم» و«ابراهيم» — شاهدنا الاثنين لنفس الجامع
        assert normalize("إبراهيم") == normalize("ابراهيم")

    def test_madda(self):
        assert normalize("آل البيت") == normalize("ال البيت")


class TestNormalizeTaMarbuta:
    """التاء المربوطة. المستخدم يكتبها هاءً في البحث غالباً."""

    def test_ta_to_ha(self):
        # «جامعة» يكتبها المستخدم «جامعه» — صادفناها في بحث «جامعه بغداد»
        assert normalize("جامعة بغداد") == normalize("جامعه بغداد")

    def test_in_place_name(self):
        assert normalize("الكاظمية") == normalize("الكاظميه")


class TestNormalizeYa:
    """الياء والألف المقصورة والهمزة على نبرة."""

    def test_alif_maqsura(self):
        # «مستشفى» و«مستشفي» — الثانية شائعة في OSM العراق
        assert normalize("مستشفى اليرموك") == normalize("مستشفي اليرموك")

    def test_hamza_on_ya(self):
        # «الرئاسة» و«الرياسة» — الهمزة على نبرة تصير ياءً
        assert normalize("الرئاسة") == normalize("الرياسة")

    def test_hamza_on_waw(self):
        # «المؤتمر» و«الموتمر»
        assert normalize("المؤتمر") == normalize("الموتمر")


class TestNormalizeDiacritics:
    """التشكيل والتطويل. OSM فيه أسماء مشكّلة كاملة."""

    def test_shadda(self):
        # «الكاظميّة» بشدّة — موجودة فعلاً في OSM
        assert normalize("الكاظميّة") == normalize("الكاظمية")

    def test_full_vocalization(self):
        assert normalize("مَدِينَةُ الصَّدْر") == normalize("مدينة الصدر")

    def test_tatweel(self):
        # التطويل يُستخدم للتنسيق في بعض اللوحات
        assert normalize("الســــلام") == normalize("السلام")


class TestNormalizePersianLetters:
    """حروف فارسية تظهر في أسماء عراقية — خصوصاً شمالاً وفي الأسماء
    المنقولة عن الكردية."""

    def test_persian_kaf(self):
        assert normalize("کربلاء") == normalize("كربلاء")

    def test_persian_ya(self):
        assert normalize("علی") == normalize("علي")


class TestNormalizeSeparators:
    """الفواصل. OSM يستخدم «-» و«/» و«،» بلا اتساق في نفس الشارع."""

    def test_dash_becomes_space(self):
        assert normalize("حي-المنصور") == normalize("حي المنصور")

    def test_multiple_spaces_collapse(self):
        # شاهدنا «محطة وقود الكيلاني  الحكومية» بمسافتين
        assert normalize("الكيلاني  الحكومية") == normalize("الكيلاني الحكومية")

    def test_latin_and_arabic_mixed(self):
        # أسماء مثل «شارع 14 تموز» و«226-2» موجودة في بيانات بغداد
        assert normalize("شارع 14 تموز") == "شارع 14 تموز"

    def test_empty_stays_empty(self):
        assert normalize("") == ""
        assert normalize("---") == ""


class TestSearchTokens:
    """كلمات الفهرس. نفهرس الاسم كاملاً وكلماته منزوعة البادئة معاً."""

    def test_strips_definite_article(self):
        # من يكتب «كاظمية» يقصد «الكاظمية» — هذا ما يجعل البحث يشتغل.
        # الكلمات مُطبَّعة أصلاً فالتاء المربوطة صارت هاءً
        assert normalize("كاظمية") in search_tokens("الكاظمية")

    def test_keeps_full_name(self):
        # الاسم كاملاً يبقى في الفهرس كي يرجّحه التطابق التام
        assert normalize("مستشفى اليرموك") in search_tokens("مستشفى اليرموك")

    def test_strips_mustashfa_prefix(self):
        # من يكتب «يرموك» وحدها يجد «مستشفى اليرموك»
        tokens = search_tokens("مستشفى اليرموك")
        assert "يرموك" in tokens

    def test_short_word_keeps_prefix(self):
        # «ال» وحدها مو اسماً، والنزع يخلّيها فارغة فنتجاهله
        assert "" not in search_tokens("ال")

    def test_no_duplicates(self):
        tokens = search_tokens("بغداد بغداد")
        assert len(tokens) == len(set(tokens))


class TestFtsText:
    """النصّ الذي يدخل فهرس FTS5."""

    def test_combines_arabic_and_latin(self):
        text = fts_text("مطار بغداد الدولي", "Baghdad International Airport",
                        "terminal")
        assert "مطار" in text
        assert "baghdad" in text

    def test_includes_category(self):
        text = fts_text("محطة الكيلاني", "", "fuel")
        assert "fuel" in text

    def test_no_repeated_terms(self):
        # التكرار ما يضرّ FTS5 لكنه يكبّر الفهرس بلا فائدة
        text = fts_text("بغداد", "Baghdad", "city")
        words = text.split()
        assert len(words) == len(set(words))

    def test_empty_names_give_category_only(self):
        assert fts_text("", "", "fuel").strip() == "fuel"
