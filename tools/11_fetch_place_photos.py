# -*- coding: utf-8 -*-
"""المرحلة ١١: صور الأماكن من ويكيميديا كومنز.

يقرأ: darb-data/poi/pois.sqlite (بعد ٠٤ و٠٨)
ينتج: نفس القاعدة، ووسم wikimedia_commons مضاف لمن لقينا له صورة.

المسألة: بياناتنا ما فيها صور إطلاقاً. فحصنا 144,659 نقطة فما في واحدة
تحمل وسم image، و11 فقط تحمل wikimedia_commons مباشرة. لكن 2,513 نقطة
تحمل وسم wikidata — ومن هناك نصل للصورة عبر الخاصية P18.

فالنتيجة معالم مشهورة لا مطاعم: جامع، نصب، جسر، جامعة. وهذا صادق —
بطاقة «مقهى بغدادي» تبقى بأيقونة لأن ما في أحد صوّره ورفعه بترخيص حر.
نجلبها مرة واحدة وقت البناء وتُحزَم مع القاعدة، فالتطبيق يبقى أوفلاين
في كل شيء إلا تحميل الصورة نفسها عند فتح البطاقة.

ليش ما نحمّل الصور نفسها ونحزمها: ألفا صورة بعرض 320 بكسل ≈ 60 ميغا
على حزمة هي 221 أصلاً. الرابط وحده يكفي، ومن يفتح بطاقة معلم عنده
اتصال غالباً.

    python 11_fetch_place_photos.py [--dry-run]
"""

import argparse
import json
import sqlite3
import sys
import time

from config import POI_DB

# ويكيداتا تقبل خمسين كياناً في الطلب الواحد. أكثر منها يرجع 400
_BATCH = 50

# مهلة بين الطلبات. بـ0.2 ثانية رجعت 429 عند الكيان 250 — فالحدّ موجود
# وإن ما كان معلناً. ثانية كاملة تعني 45 ثانية لكل البلد، وهي رخيصة
_PAUSE_S = 1.0

# المحاولات عند 429 أو 503، بتراجع أُسّي
_RETRIES = 4

_API = "https://www.wikidata.org/w/api.php"

# ويكيميديا ترفض بـ403 أي طلب بلا User-Agent يعرّف بصاحبه. جرّبناه بلاه
# فرجع 403 من أول دفعة — وسياستهم تطلب اسم المشروع ووسيلة تواصل
_UA = "darb-maps/0.1 (https://github.com/; Iraq OSM navigation app)"


def wikidata_ids(con: sqlite3.Connection) -> dict[str, list[int]]:
    """معرّف ويكيداتا ← صفوف القاعدة التي تحمله.

    قائمة لا صفّ واحد: المعلم الواحد قد يتكرّر (نقطة من OSM وأخرى من
    Overture)، وكلاهما يستحق الصورة نفسها.
    """
    out: dict[str, list[int]] = {}

    for row_id, raw in con.execute(
            "SELECT id, tags FROM poi WHERE tags LIKE '%wikidata%'"):
        tags = json.loads(raw)
        qid = tags.get("wikidata")
        # نتخطّى من عنده صورة أصلاً: الوسم المباشر من OSM أدقّ من
        # P18 لأن المحرّر اختاره لهذا المكان بعينه
        if not qid or tags.get("wikimedia_commons"):
            continue
        out.setdefault(qid, []).append(row_id)

    return out


def _get_batch(chunk: list[str]) -> dict:
    """دفعة واحدة مع تراجع أُسّي على 429/503."""
    import requests

    delay = 2.0
    for attempt in range(_RETRIES):
        r = requests.get(_API, params={
            "action": "wbgetentities",
            "ids": "|".join(chunk),
            "props": "claims",
            "format": "json",
        }, headers={"User-Agent": _UA}, timeout=30)

        if r.status_code == 200:
            return r.json().get("entities", {})

        if r.status_code in (429, 503) and attempt < _RETRIES - 1:
            # Retry-After إن أرسلوه، وإلا تراجع أُسّي
            wait = float(r.headers.get("Retry-After") or delay)
            print(f"\n  حدّ الطلبات — ننتظر {wait:.0f}ث", flush=True)
            time.sleep(wait)
            delay *= 2
            continue

        sys.exit(f"ويكيداتا رفضت الطلب: HTTP {r.status_code}")

    return {}


def fetch_and_store(con: sqlite3.Connection,
                    rows: dict[str, list[int]]) -> int:
    """يسأل دفعةً دفعة ويكتب بعد كل واحدة.

    الكتابة بعد كل دفعة لا في النهاية: أول تشغيل قطعه حدّ الطلبات عند
    الكيان 250 فضاع كل ما جمعناه. والتشغيل التالي يتخطّى من عنده صورة
    أصلاً، فالسكربت يكمل من حيث وقف.
    """
    qids = sorted(rows)
    stored = 0

    for i in range(0, len(qids), _BATCH):
        chunk = qids[i:i + _BATCH]
        entities = _get_batch(chunk)

        for qid, ent in entities.items():
            claims = (ent.get("claims") or {}).get("P18") or []
            if not claims:
                continue
            value = claims[0].get("mainsnak", {}).get("datavalue", {})
            name = value.get("value")
            if not isinstance(name, str) or not name:
                continue

            for row_id in rows.get(qid, []):
                raw = con.execute("SELECT tags FROM poi WHERE id = ?",
                                  (row_id,)).fetchone()[0]
                tags = json.loads(raw)
                tags["wikimedia_commons"] = f"File:{name}"
                con.execute("UPDATE poi SET tags = ? WHERE id = ?",
                            (json.dumps(tags, ensure_ascii=False), row_id))
                stored += 1

        con.commit()
        done = min(i + _BATCH, len(qids))
        print(f"  … {done}/{len(qids)} كياناً، {stored} صفاً بصورة",
              end="\r", flush=True)
        time.sleep(_PAUSE_S)

    print()
    return stored


def main() -> None:
    ap = argparse.ArgumentParser(description="صور الأماكن من كومنز")
    ap.add_argument("--dry-run", action="store_true",
                    help="يعدّ ولا يكتب")
    args = ap.parse_args()

    if not POI_DB.exists():
        sys.exit(f"ما لقينا القاعدة: {POI_DB}\nشغّل 04 و08 أولاً.")

    print("─ المرحلة ١١: صور الأماكن من كومنز ─\n")

    con = sqlite3.connect(POI_DB)

    rows = wikidata_ids(con)
    if not rows:
        print("  ما في نقطة تحمل وسم wikidata — تأكد أن 04 حفظه "
              "في _KEEP_TAGS")
        return

    print(f"١. {len(rows)} معلماً يحمل معرّف ويكيداتا بلا صورة")

    if args.dry_run:
        print("  (تجربة) ما سألنا ولا كتبنا")
        return

    print("\n٢. نسأل ويكيداتا عن P18 ونكتب بعد كل دفعة")
    updated = fetch_and_store(con, rows)

    total = con.execute("SELECT COUNT(*) FROM poi").fetchone()[0]
    with_photo = con.execute(
        "SELECT COUNT(*) FROM poi WHERE tags LIKE '%wikimedia_commons%'"
    ).fetchone()[0]
    con.close()

    print(f"  ✓ {updated} صفاً حدّثناه")
    print(f"\n  صور: {with_photo} من {total} نقطة "
          f"({with_photo / total * 100:.1f}%) — معالم لا مطاعم، وهذا "
          f"سقف ما تعطيه بيانات حرّة")
    print("\n✓ المرحلة ١١ تمّت. التالي: python 07_pack_assets.py iraq")


if __name__ == "__main__":
    main()
