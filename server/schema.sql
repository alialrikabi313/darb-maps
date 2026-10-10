-- -*- coding: utf-8 -*-
-- schema قاعدة darb: البلاغات وقراءات السرعة.
-- يُطبَّق تلقائياً عند أول تشغيل للحاوية (docker-entrypoint-initdb.d).
-- لإعادة التطبيق: docker compose down -v ثم up.

CREATE EXTENSION IF NOT EXISTS postgis;
CREATE EXTENSION IF NOT EXISTS pgcrypto;   -- gen_random_uuid للأجهزة

-- ── الأجهزة ────────────────────────────────────────────────────────────────
-- لا حساب ولا بريد: ويز نفسه يشتغل بلا تسجيل، والتسجيل يطرد المستخدم
-- العراقي أكثر مما يفيدنا. المعرّف يُنشأ على الجهاز ويُسجَّل هنا للتصويت
-- ومنع التلاعب فقط.
CREATE TABLE device (
    id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    created_at    timestamptz NOT NULL DEFAULT now(),
    last_seen_at  timestamptz NOT NULL DEFAULT now(),
    -- سمعة الجهاز: ترتفع ببلاغات يؤكّدها غيره وتنزل بالمنفيّة. تُستخدم
    -- وزناً في ثقة البلاغ — جهاز أثبت صدقه بلاغه يُعتمد بأصوات أقل
    reputation    integer NOT NULL DEFAULT 0,
    reports_made  integer NOT NULL DEFAULT 0,
    is_blocked    boolean NOT NULL DEFAULT false
);

-- ── البلاغات ───────────────────────────────────────────────────────────────
CREATE TABLE report (
    id          bigserial PRIMARY KEY,
    kind        text NOT NULL,
    geom        geography(Point, 4326) NOT NULL,
    -- اتجاه المُبلِّغ بالدرجات. ضروري وليس تجميلاً: الرادار والسيطرة على
    -- جهة واحدة من الطريق، وتنبيه السائق المعاكس خطأ يفقده الثقة بالتطبيق
    heading     real,
    device_id   uuid REFERENCES device(id) ON DELETE SET NULL,
    note        text,
    created_at  timestamptz NOT NULL DEFAULT now(),
    -- expires_at محسوب من ttl النوع عند الإنشاء، ويتقدّم بأصوات النفي.
    -- خزّنّاه عموداً لا دالةً لأن الاستعلام الحارّ «البلاغات الحيّة حولي»
    -- يفلتر عليه، ودالة تمنع استخدام الفهرس
    expires_at  timestamptz NOT NULL,
    up_votes    integer NOT NULL DEFAULT 1,   -- المُبلِّغ نفسه صوت أول
    down_votes  integer NOT NULL DEFAULT 0,
    is_removed  boolean NOT NULL DEFAULT false,
    -- معرّف المجموعة: بلاغات متشابهة متجاورة تُعرض واحداً. أول بلاغ في
    -- المجموعة هو قائدها (cluster_id = id نفسه)
    cluster_id  bigint
);

-- الفهرس المكاني على الحيّ فقط: البلاغات المنتهية تبقى للتحليل لكن
-- استعلام «حولي» ما يمسّها، والفهرس الجزئي يبقى صغيراً مهما كبرت الجداول
CREATE INDEX report_live_geo ON report USING GIST (geom)
    WHERE NOT is_removed;
CREATE INDEX report_expires ON report (expires_at) WHERE NOT is_removed;
CREATE INDEX report_cluster ON report (cluster_id) WHERE NOT is_removed;
CREATE INDEX report_device ON report (device_id, created_at DESC);

-- ── الأصوات ────────────────────────────────────────────────────────────────
-- جهاز واحد صوت واحد لكل بلاغ. المفتاح المركّب يفرضها في القاعدة لا في
-- الكود — الفرض في الكود ينكسر مع أول طلبين متوازيين
CREATE TABLE report_vote (
    report_id  bigint NOT NULL REFERENCES report(id) ON DELETE CASCADE,
    device_id  uuid NOT NULL REFERENCES device(id) ON DELETE CASCADE,
    is_up      boolean NOT NULL,
    voted_at   timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (report_id, device_id)
);

-- ── قراءات السرعة ──────────────────────────────────────────────────────────
-- مجهولة تماماً: لا device_id ولا معرّف رحلة. قطعة طريق وسرعة ووقت.
-- السبب: المسار الكامل يعرّف صاحبه حتى بلا اسم — البيت ثم العمل بصمة فريدة
CREATE TABLE traffic_sample (
    id          bigserial PRIMARY KEY,
    way_id      bigint NOT NULL,          -- معرّف OSM للطريق من Valhalla
    speed_kmh   real NOT NULL,
    -- السرعة الحرّة المرجعية، تُلتقط من حافة Valhalla وقت الاستقبال.
    -- كانت تُثبَّت على 30 في التجميع فيُصنَّف زحام طريق المطار (حرّ 100)
    -- عند 25 كم/س «سالكاً» — الميزة تقول عكس الحقيقة في أهمّ مكان
    free_speed_kmh real,
    observed_at timestamptz NOT NULL
);

CREATE INDEX traffic_sample_way ON traffic_sample (way_id, observed_at DESC);
CREATE INDEX traffic_sample_time ON traffic_sample (observed_at);

-- الحالة الحالية لكل قطعة: مُجمَّعة من القراءات دورياً. جدول منفصل لأن
-- التطبيق يطلبها عشرات المرات في الدقيقة، وتجميعها في كل طلب يقتل القاعدة
CREATE TABLE traffic_state (
    way_id        bigint PRIMARY KEY,
    level         text NOT NULL,          -- free / moderate / heavy / jam
    avg_speed_kmh real NOT NULL,
    free_speed_kmh real NOT NULL,         -- المرجع الذي قُسِم عليه
    samples       integer NOT NULL,
    updated_at    timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX traffic_state_updated ON traffic_state (updated_at);

-- ── إغلاقات الطرق ──────────────────────────────────────────────────────────
-- مستخلَصة من بلاغات road_closed المؤكّدة، وتُحقن في حساب المسار لتجنّبها.
-- جدول منفصل عن report لأن حساب المسار يقرأها في كل طلب وما يبي يفلتر
-- على نوع البلاغ وثقته كل مرة
CREATE TABLE road_closure (
    id         bigserial PRIMARY KEY,
    -- UNIQUE لا مجرد مرجع: التصويت على بلاغ إغلاق يُعيد مزامنته، ومن غير
    -- القيد يتضاعف الإغلاق بعدد الأصوات فيصير الطريق مغلقاً عشر مرات
    report_id  bigint UNIQUE REFERENCES report(id) ON DELETE CASCADE,
    geom       geography(Point, 4326) NOT NULL,
    radius_m   integer NOT NULL DEFAULT 50,
    expires_at timestamptz NOT NULL
);

CREATE INDEX road_closure_geo ON road_closure USING GIST (geom);
-- يُقرأ في كل طلب توجيه (WHERE expires_at > now()) فبلا فهرس مسح كامل
CREATE INDEX road_closure_expires ON road_closure (expires_at);

-- ── طرق مرشّحة ─────────────────────────────────────────────────────────────
-- أثر GPS مرّ من مكان لا يعرف Valhalla فيه طريقاً = طريق ناقص من الخريطة.
-- هذا بالضبط ما يجعل ويز أغنى منّا: ملايين السيارات ترسم الطرق الجديدة.
-- قِسنا الفجوة: 8% فقط من طرق العراق مسمّاة في OSM.
--
-- نخزّن القطعة غير المطابَقة لا الأثر كاملاً، وبلا أي ربط بجهاز — نفس
-- سياسة الخصوصية في traffic_sample.
CREATE TABLE road_candidate (
    id          bigserial PRIMARY KEY,
    -- خطّ القطعة التي ما طابقت. geography لا geometry: نقيس أطوالاً
    -- ومسافات بالأمتار لا بالدرجات
    geom        geography(LineString, 4326) NOT NULL,
    length_m    real NOT NULL,
    -- كم جهازاً مرّ من هنا. طريق حقيقي يمرّ به كثيرون؛ مرّة واحدة قد
    -- تكون سيارة في ساحة ترابية أو خطأ GPS
    hits        integer NOT NULL DEFAULT 1,
    first_seen  timestamptz NOT NULL DEFAULT now(),
    last_seen   timestamptz NOT NULL DEFAULT now(),
    -- صار مؤكّداً ويستحق العرض للتحرير في OSM
    is_promoted boolean NOT NULL DEFAULT false
);

CREATE INDEX road_candidate_geo ON road_candidate USING GIST (geom);
-- الفهرس على المُرقّى لا على غيره: الاستعلام الوحيد الذي يرتّب بـhits
-- هو /roads/candidates وهو WHERE is_promoted. الشرط المعكوس كان يستبعد
-- كل صفّ يطلبه الاستعلام
CREATE INDEX road_candidate_hits ON road_candidate (hits DESC, length_m DESC)
    WHERE is_promoted;

-- ── دالة التنظيف ───────────────────────────────────────────────────────────
-- تُنادى من وظيفة دورية. ما جعلناها trigger لأن الحذف وقت الكتابة يبطّئ
-- أكثر طلب حرارةً في النظام (إرسال بلاغ)
CREATE OR REPLACE FUNCTION darb_cleanup(retention_days integer)
RETURNS TABLE (removed_reports bigint, removed_samples bigint) AS $$
DECLARE
    r bigint;
    s bigint;
BEGIN
    UPDATE report SET is_removed = true
     WHERE NOT is_removed AND expires_at < now();
    GET DIAGNOSTICS r = ROW_COUNT;

    DELETE FROM traffic_sample
     WHERE observed_at < now() - make_interval(days => retention_days);
    GET DIAGNOSTICS s = ROW_COUNT;

    DELETE FROM road_closure WHERE expires_at < now();

    -- المرشّحون يحملون مسار GPS خاماً — أخطر هندسة عندنا. وعد الاحتفاظ
    -- سبعة أيام ما كان يشملهم. نحذف غير المرقّى القديم؛ المرقّى يبقى
    -- لأنه صار معلومة خريطة لا أثر رحلة
    DELETE FROM road_candidate
     WHERE NOT is_promoted
       AND last_seen < now() - make_interval(days => retention_days);

    RETURN QUERY SELECT r, s;
END;
$$ LANGUAGE plpgsql;
