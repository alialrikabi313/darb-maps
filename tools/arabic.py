# -*- coding: utf-8 -*-
"""تطبيع النص العربي للبحث.

المشكلة الفعلية: OSM العراق يكتب نفس الاسم بأشكال مختلفة. صادفنا في بغداد
«الكاظميّة» و«الكاظمية»، و«مستشفى» و«مستشفي»، و«إبراهيم» و«ابراهيم»، و«کربلاء»
بكاف فارسية. والمستخدم يكتب ثالثاً غيرهما. فنطبّع الطرفين لصورة واحدة.

قواعد التطبيع في config.py لا هنا، وتُخزَّن مع القاعدة ليقرأها التطبيق —
بحث الجهاز لازم يطبّع بنفس الطريقة التي فُهرست بها، وإلا ضاعت النتائج بلا
أي خطأ ظاهر.
"""

import re

from config import ARABIC_NORMALIZE_MAP, ARABIC_STRIP_CHARS, SEARCH_STOP_PREFIXES

_STRIP_RE = re.compile(f"[{re.escape(ARABIC_STRIP_CHARS)}]")

# كل ما ليس حرفاً أو رقماً يصير فاصلاً: OSM يستخدم «-» و«/» و«،» بلا اتساق
_SEP_RE = re.compile(r"[^\w؀-ۿ]+", re.UNICODE)

_TRANS = str.maketrans(ARABIC_NORMALIZE_MAP)


def normalize(text: str) -> str:
    """يرجّع الصورة المطبّعة: بلا تشكيل، حروف موحّدة، مسافة واحدة، lowercase."""
    if not text:
        return ""
    t = _STRIP_RE.sub("", text)
    t = t.translate(_TRANS)
    t = _SEP_RE.sub(" ", t)
    return t.strip().lower()


def search_tokens(text: str) -> list[str]:
    """كلمات البحث المطبّعة، مع إضافة صورة بلا البادئات الشائعة.

    من يكتب «يرموك» يقصد «مستشفى اليرموك»، ومن يكتب «كاظمية» يقصد «الكاظمية».
    فنفهرس الاسم كاملاً وكلماته منزوعة البادئة معاً — زيادة في حجم الفهرس
    مقابل بحث يشتغل كما يتوقّعه المستخدم.
    """
    norm = normalize(text)
    if not norm:
        return []

    tokens = set(norm.split())
    tokens.add(norm)

    for w in norm.split():
        for p in SEARCH_STOP_PREFIXES:
            pn = normalize(p)
            if w.startswith(pn) and len(w) > len(pn) + 1:
                tokens.add(w[len(pn):])

    return sorted(tokens)


def fts_text(name_ar: str, name_en: str, category_label: str) -> str:
    """النص الذي يدخل فهرس FTS5 لصفٍّ واحد."""
    parts = search_tokens(name_ar) + search_tokens(name_en)
    if category_label:
        parts += search_tokens(category_label)
    # نكرار الكلمة لا يضرّ FTS5 لكنه يكبّر الفهرس بلا فائدة
    return " ".join(dict.fromkeys(parts))
