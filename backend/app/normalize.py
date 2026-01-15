from __future__ import annotations

import re
from typing import Any, Optional, Tuple


def _as_str(value: Any) -> Optional[str]:
    if value is None:
        return None
    if isinstance(value, str):
        return value
    return str(value)


def normalize_status(raw: dict[str, Any]) -> str:
    for key in ("status", "result", "state"):
        val = raw.get(key)
        if isinstance(val, str):
            v = val.strip().lower()
            if v in ("success", "successful", "verified", "paid", "ok"):
                return "SUCCESS"
            if v in ("failed", "invalid", "not_found", "not found", "unverified", "error"):
                return "FAILED"
            if v in ("pending", "processing", "unknown"):
                return "PENDING"

    for key in ("success", "verified", "isVerified", "is_verified"):
        val = raw.get(key)
        if isinstance(val, bool):
            return "SUCCESS" if val else "FAILED"

    msg = raw.get("message") or raw.get("detail")
    if isinstance(msg, str):
        m = msg.lower()
        if "pending" in m or "processing" in m or "try again" in m:
            return "PENDING"
        if "invalid" in m or "not found" in m or "failed" in m:
            return "FAILED"
        if "success" in m or "verified" in m:
            return "SUCCESS"

    return "PENDING"


def normalize_fields(raw: dict[str, Any]) -> Tuple[Optional[float], Optional[str], Optional[str], Optional[str]]:
    src: dict[str, Any] = raw
    if isinstance(raw.get("data"), dict):
        src = raw["data"]  # type: ignore[assignment]

    amount = src.get("amount") or src.get("total") or src.get("totalAmount")
    try:
        amount_f = float(amount) if amount is not None else None
    except Exception:
        amount_f = None
        if isinstance(amount, str):
            m = re.search(r"([0-9][0-9,]*(?:\.[0-9]{1,2})?)", amount)
            if m:
                try:
                    amount_f = float(m.group(1).replace(",", ""))
                except Exception:
                    amount_f = None

    payer = _as_str(
        src.get("payer")
        or src.get("payerName")
        or src.get("from")
        or src.get("sender")
        or src.get("debitedFrom")
    )
    date = _as_str(src.get("date") or src.get("time") or src.get("timestamp") or src.get("paymentDate"))
    reference = _as_str(
        src.get("reference")
        or src.get("ref")
        or src.get("transactionId")
        or src.get("transactionID")
        or src.get("txId")
    )

    return amount_f, payer, date, reference
