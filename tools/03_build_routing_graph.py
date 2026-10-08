# -*- coding: utf-8 -*-
"""المرحلة ٠٣: بناء رسم التوجيه بـValhalla وتشغيل خدمته.

يقرأ: darb-data/osm/{baghdad|iraq-latest}.osm.pbf
ينتج: darb-data/valhalla/ (رسم التوجيه) + حاوية تخدم على المنفذ 8002

الخطوات:
  ١. نسخ الـPBF إلى custom_files اللي تقرأه الحاوية
  ٢. تشغيل الحاوية — تبني الرسم أول مرة ثم تخدمه
  ٣. انتظار /status حتى تجهز
  ٤. تجربة مسار الكاظمية ← المنصور وطباعة مناوراته
  ٥. قياس حجم الرسم — الرقم يحسم قرار التوجيه أوفلاين (المرحلة ١٣)

    python 03_build_routing_graph.py            # العيّنة
    python 03_build_routing_graph.py --full      # العراق كامل
    python 03_build_routing_graph.py --rebuild   # أعد بناء الرسم من الصفر
"""

import sys
import json
import time
import shutil
import argparse
import subprocess

import requests

from config import (
    IRAQ_PBF, SAMPLE_PBF, VALHALLA_DIR, VALHALLA_IMAGE, VALHALLA_PORT,
    VALHALLA_URL, VALHALLA_SERVER_THREADS, ensure_dirs,
)

_CONTAINER = "darb-valhalla"

# رسم Valhalla يُكتب في volume من Docker لا في مجلد على قرص ويندوز.
# قِسناه: بناء بغداد (7.5MB) على bind mount أخذ 13 دقيقة لطبقة اختصارات
# واحدة، والرسم ألوف ملفات صغيرة وطبقة ترجمة الملفات في Docker Desktop
# تخنقها. العراق كامل على نفس المسار يعني ساعات.
# المقايضة: الرسم ما يبقى مرئياً على القرص. نقيس حجمه بـdocker exec،
# ونصدّره صريحاً عند الحاجة (المرحلة ١٣، التوجيه أوفلاين).
_VOLUME = "darb_valhalla_tiles"

# مسارات تجربة من بغداد — نقاط حقيقية لا عشوائية، ونعرف الجواب الصحيح
# فنكتشف لو الرسم مبني غلط
_TEST_ROUTES = [
    ("الكاظمية ← المنصور", (33.3799, 44.3375), (33.3094, 44.3384)),
    ("ساحة التحرير ← مطار بغداد", (33.3074, 44.4009), (33.2625, 44.2346)),
    ("الأعظمية ← الكرادة", (33.3843, 44.3700), (33.2940, 44.4190)),
]


def human(n: float) -> str:
    for unit in ("B", "KB", "MB", "GB"):
        if n < 1024:
            return f"{n:.1f}{unit}"
        n /= 1024.0
    return f"{n:.1f}TB"


def graph_size_bytes() -> int | None:
    """حجم الرسم مقيساً داخل الحاوية — الرسم في volume لا على القرص."""
    res = docker("exec", _CONTAINER, "du", "-sb",
                 "/custom_files/valhalla_tiles", check=False)
    if res.returncode != 0:
        return None
    return int(res.stdout.split()[0])


def docker(*args, check: bool = True, capture: bool = True):
    res = subprocess.run(["docker", *args], capture_output=capture, text=True,
                         encoding="utf-8", errors="replace")
    if check and res.returncode != 0:
        sys.exit(f"فشل docker {' '.join(args)}:\n{res.stderr or res.stdout}")
    return res


def container_state() -> str:
    """running / exited / absent"""
    res = docker("inspect", "-f", "{{.State.Status}}", _CONTAINER, check=False)
    return res.stdout.strip() if res.returncode == 0 else "absent"


def stage_pbf(pbf) -> None:
    """ينسخ الـPBF إلى مجلد مدخل صغير يُربط داخل الحاوية.

    مجلد منفصل عن الرسم: الـPBF ملف واحد كبير (bind mount يناسبه)، والرسم
    ألوف ملفات صغيرة (volume يناسبه). خلطهما في مجلد واحد كان سبب البطء.
    """
    inp = VALHALLA_DIR / "input"
    inp.mkdir(parents=True, exist_ok=True)

    # نمسح أي pbf قديم: الحاوية تبني من كل ما تجده، ووجود بغداد والعراق
    # معاً يبني رسماً مضاعفاً بلا أي رسالة خطأ
    for old in inp.glob("*.pbf"):
        if old.name != pbf.name:
            print(f"    نمسح {old.name} (مدخل قديم)")
            old.unlink()

    dest = inp / pbf.name
    if dest.exists() and dest.stat().st_size == pbf.stat().st_size:
        print(f"  ✓ {pbf.name} مهيَّأ")
        return

    print(f"  ◄ نسخ {pbf.name} ({human(pbf.stat().st_size)})")
    shutil.copy2(pbf, dest)


def start_container(rebuild: bool, bind_tiles: bool = False) -> None:
    state = container_state()
    if state == "running" and not rebuild:
        print(f"  ✓ الحاوية {_CONTAINER} تشتغل")
        return

    if state != "absent":
        print(f"  ◄ إزالة الحاوية السابقة ({state})")
        docker("rm", "-f", _CONTAINER)

    if rebuild and not bind_tiles:
        # الـvolume يحمل رسماً قديماً وforce_rebuild وحده ما يمسح كل أثر
        print(f"  ◄ مسح volume الرسم {_VOLUME}")
        docker("volume", "rm", "-f", _VOLUME, check=False)

    pbf_name = next((VALHALLA_DIR / "input").glob("*.pbf")).name
    pbf_host = (VALHALLA_DIR / "input" / pbf_name).resolve()

    env = {
        # أهم متغيّر هنا: الافتراضي nproc والخدمة تنهار عنده — انظر
        # التعليق في config.py
        "server_threads": str(VALHALLA_SERVER_THREADS),
        # تبني من الـPBF الموجود في custom_files
        "use_tiles_ignore_pbf": "False",
        "serve_tiles": "True",
        # الارتفاعات تضيف ~2GB تنزيلاً وتفيد الدراجات والمشي فقط — نحن
        # للسيارات، ومنحدرات العراق مهملة أصلاً
        "build_elevation": "False",
        # الحدود الإدارية: نبيها لأن Valhalla يحتاجها لقواعد المرور
        # (جهة السير، حدود السرعة الافتراضية لكل دولة)
        "build_admins": "True",
        # المناطق الزمنية: تلزم لحساب ETA بوقت محلي صحيح
        "build_time_zones": "True",
        "force_rebuild": "True" if rebuild else "False",
    }

    cmd = ["run", "-d", "--name", _CONTAINER,
           "-p", f"{VALHALLA_PORT}:8002",
           # بلا رفع الحدّ ينهار البناء بـ«Too many open files»: Valhalla
           # يبني بـ32 خيطاً وكل خيط يفتح بلاطات كثيرة، والحدّ الافتراضي
           # في الحاوية 1024. صادفناه فعلاً وأسقط بناء بغداد بعد 15 دقيقة
           "--ulimit", "nofile=65536:65536"]

    if bind_tiles:
        # الرسم على القرص: أبطأ بكثير، ونبيه فقط حين نصدّر الرسم للجهاز
        cmd += ["-v", f"{(VALHALLA_DIR / 'custom_files').resolve()}:/custom_files"]
    else:
        # الرسم في volume، والـPBF ملف واحد مربوط داخله. Docker يسمح
        # بربط ملف فوق volume ويبقى الباقي داخل الـvolume
        cmd += ["-v", f"{_VOLUME}:/custom_files",
                "-v", f"{pbf_host}:/custom_files/{pbf_name}:ro"]

    for k, v in env.items():
        cmd += ["-e", f"{k}={v}"]
    cmd.append(VALHALLA_IMAGE)

    print(f"  ◄ تشغيل {_CONTAINER} "
          f"({'قرص' if bind_tiles else 'volume'}؛ البناء أول مرة يأخذ دقائق)")
    docker(*cmd)


def wait_ready(timeout_s: int = 3600) -> None:
    """ينتظر /status. البناء أول مرة طويل فالمهلة ساعة."""
    t0 = time.time()
    last_log = 0.0
    while time.time() - t0 < timeout_s:
        if container_state() == "exited":
            logs = docker("logs", "--tail", "40", _CONTAINER, check=False)
            sys.exit(f"الحاوية توقّفت أثناء البناء:\n{logs.stdout}{logs.stderr}")

        try:
            r = requests.get(f"{VALHALLA_URL}/status", timeout=5)
            if r.status_code == 200:
                print(f"  ✓ الخدمة جاهزة بعد {time.time() - t0:.0f}s")
                print(f"    {json.dumps(r.json(), ensure_ascii=False)[:200]}")
                return
        except requests.RequestException:
            pass

        now = time.time()
        if now - last_log > 30:
            logs = docker("logs", "--tail", "3", _CONTAINER, check=False)
            tail = (logs.stdout or logs.stderr).strip().splitlines()
            msg = tail[-1][:120] if tail else "…"
            print(f"    [{now - t0:5.0f}s] {msg}", flush=True)
            last_log = now
        time.sleep(5)

    sys.exit(f"الخدمة ما جهزت خلال {timeout_s}s — افحص: docker logs {_CONTAINER}")


def test_route(label: str, src: tuple[float, float],
               dst: tuple[float, float]) -> bool:
    """يطلب مساراً ويطبع مناوراته. يرجّع True إذا نجح."""
    body = {
        "locations": [{"lat": src[0], "lon": src[1]},
                      {"lat": dst[0], "lon": dst[1]}],
        "costing": "auto",
        "directions_options": {"units": "kilometers"},
    }
    r = requests.post(f"{VALHALLA_URL}/route", json=body, timeout=30)

    if r.status_code != 200:
        print(f"  ✗ {label}: HTTP {r.status_code} — "
              f"{r.text[:200]}")
        return False

    leg = r.json()["trip"]["legs"][0]
    summ = r.json()["trip"]["summary"]
    print(f"\n  ✓ {label}")
    print(f"    {summ['length']:.1f} كم  —  {summ['time'] / 60:.0f} دقيقة  —  "
          f"{len(leg['maneuvers'])} مناورة")

    for m in leg["maneuvers"][:6]:
        streets = "، ".join(m.get("street_names", [])) or "—"
        print(f"      type={m['type']:<3} {m['length']:5.2f}كم  {streets[:45]}")
    if len(leg["maneuvers"]) > 6:
        print(f"      … و{len(leg['maneuvers']) - 6} مناورة أخرى")
    return True


def main() -> None:
    ap = argparse.ArgumentParser(description="بناء رسم التوجيه وتشغيل Valhalla")
    ap.add_argument("--full", action="store_true", help="العراق كامل")
    ap.add_argument("--rebuild", action="store_true",
                    help="أعد بناء الرسم من الصفر")
    ap.add_argument("--bind-tiles", action="store_true",
                    help="اكتب الرسم على القرص بدل volume — أبطأ بمراتب على "
                         "ويندوز، ويلزم فقط عند تصدير الرسم للجهاز")
    args = ap.parse_args()

    ensure_dirs()
    pbf = IRAQ_PBF if args.full else SAMPLE_PBF
    if not pbf.exists():
        sys.exit(f"{pbf} غير موجود — شغّل 01_fetch_osm.py أولاً")

    print(f"─ المرحلة ٠٣: رسم التوجيه ({pbf.name}) ─")

    print("\n١. تهيئة المدخل")
    stage_pbf(pbf)

    print("\n٢. الحاوية")
    start_container(args.rebuild, bind_tiles=args.bind_tiles)

    print("\n٣. الانتظار")
    wait_ready()

    print("\n٤. مسارات تجربة")
    ok = sum(test_route(*t) for t in _TEST_ROUTES)
    if ok == 0:
        sys.exit("كل مسارات التجربة فشلت — الرسم مبني لكنه فارغ أو ما يغطّي بغداد")

    print("\n٥. حجم الرسم")
    size = graph_size_bytes()
    if size is None:
        print("    (ما قدرنا نقيس حجم الرسم داخل الحاوية)")
    else:
        print(f"    رسم {pbf.stem}: {human(size)}")
        if not args.full:
            # تقدير خطّي من نسبة حجم الـPBF — تقديري لا مقيس، والنسبة
            # الحقيقية أقل لأن أرياف العراق أخفّ من بغداد
            ratio = IRAQ_PBF.stat().st_size / pbf.stat().st_size
            print(f"    تقدير العراق كامل: ~{human(size * ratio)} "
                  f"(خطّي، والحقيقي أقل)")
            print("    ◄ هذا الرقم يحسم قرار التوجيه أوفلاين في المرحلة ١٣")

    print(f"\n✓ المرحلة ٠٣ تمّت. الخدمة على {VALHALLA_URL}")
    print("  التالي: 04_extract_pois.py")


if __name__ == "__main__":
    main()
