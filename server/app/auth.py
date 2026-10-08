# -*- coding: utf-8 -*-
"""هوية الجهاز.

لا حساب ولا بريد: ويز يشتغل بلا تسجيل، وفرض التسجيل على مستخدم عراقي يبي
يعرف الطريق للمستشفى يفقدنا إياه. الجهاز يطلب هوية مرة، ويحملها توكناً
طويل العمر — ما عنده كلمة مرور يجدّد بها، فانتهاء التوكن يعني فقدان سمعته
وتاريخ بلاغاته.

التوكن لا يحمل أي شيء عن المستخدم: معرّف عشوائي صنعته القاعدة، وبس.
"""

import uuid
from datetime import datetime, timedelta, timezone

import jwt
from fastapi import Depends, Header, HTTPException, status
from sqlalchemy import text
from sqlalchemy.engine import Connection

from .db import get_conn
from .settings import JWT_SECRET, JWT_ALG, JWT_TTL_DAYS


def issue_token(device_id: uuid.UUID) -> str:
    now = datetime.now(timezone.utc)
    payload = {
        "sub": str(device_id),
        "iat": int(now.timestamp()),
        "exp": int((now + timedelta(days=JWT_TTL_DAYS)).timestamp()),
    }
    return jwt.encode(payload, JWT_SECRET, algorithm=JWT_ALG)


def register_device(conn: Connection) -> tuple[uuid.UUID, str]:
    did = conn.execute(
        text("INSERT INTO device DEFAULT VALUES RETURNING id")).scalar_one()
    return did, issue_token(did)


def current_device(
    authorization: str | None = Header(default=None),
    conn: Connection = Depends(get_conn),
) -> uuid.UUID:
    """يستخرج معرّف الجهاز من التوكن ويحدّث last_seen.

    ما نتحقق من وجود الجهاز في القاعدة في كل طلب: التوكن موقّع وسرّه عندنا،
    ووجوده إثبات كافٍ. نتحقق من الحظر فقط لأنه الحالة التي تغيّرت بعد الإصدار.
    """
    if not authorization or not authorization.startswith("Bearer "):
        raise HTTPException(status.HTTP_401_UNAUTHORIZED,
                            "ناقص توكن الجهاز — سجّل الجهاز أولاً")

    try:
        payload = jwt.decode(authorization[7:], JWT_SECRET,
                             algorithms=[JWT_ALG])
    except jwt.ExpiredSignatureError:
        raise HTTPException(status.HTTP_401_UNAUTHORIZED,
                            "انتهى توكن الجهاز — سجّل الجهاز من جديد")
    except jwt.InvalidTokenError:
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, "توكن غير صالح")

    did = uuid.UUID(payload["sub"])

    row = conn.execute(
        text("UPDATE device SET last_seen_at = now() WHERE id = :d "
             "RETURNING is_blocked"), {"d": did}).fetchone()

    # صفر صفوف يعني أن الجهاز حُذف من القاعدة بعد إصدار توكنه
    if row is None:
        raise HTTPException(status.HTTP_401_UNAUTHORIZED,
                            "الجهاز غير مسجّل — سجّله من جديد")
    if row.is_blocked:
        raise HTTPException(status.HTTP_403_FORBIDDEN,
                            "هذا الجهاز محظور من الإبلاغ")

    return did
