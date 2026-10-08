# -*- coding: utf-8 -*-
"""الاتصال بالقاعدة.

SQLAlchemy Core لا ORM: كل استعلام هنا مكاني (ST_DWithin، ST_MakePoint)
والـORM يخفي الـSQL الفعلي ويصعّب قراءة خطة التنفيذ، وهو أهم ما نقرأه حين
يبطّئ استعلام «البلاغات حولي».
"""

from collections.abc import Iterator

from sqlalchemy import create_engine, text
from sqlalchemy.engine import Connection

from .settings import DB_DSN

# pool_pre_ping: الحاوية تُعاد تشغيلها كثيراً في التطوير، وبلا الفحص
# يرمي أول طلب بعدها خطأ اتصال ميت مرة واحدة ثم يشتغل — سلوك يضيّع وقتاً
# في التشخيص أكثر من كلفة الفحص
_engine = create_engine(DB_DSN, pool_pre_ping=True, pool_size=10,
                        max_overflow=20, future=True)


def get_conn() -> Iterator[Connection]:
    """تبعية FastAPI: اتصال مع معاملة تُثبَّت عند نجاح الطلب."""
    with _engine.begin() as conn:
        yield conn


def ping() -> str:
    """يرجّع إصدار PostGIS، أو يرمي إذا القاعدة مو جاهزة."""
    with _engine.connect() as conn:
        return conn.execute(text("SELECT PostGIS_Lib_Version()")).scalar_one()
