from __future__ import annotations

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
    amount = raw.get("amount") or raw.get("total") or raw.get("totalAmount")
    try:
        amount_f = float(amount) if amount is not None else None
    except Exception:
        amount_f = None

    payer = _as_str(raw.get("payer") or raw.get("payerName") or raw.get("from") or raw.get("sender"))
    date = _as_str(raw.get("date") or raw.get("time") or raw.get("timestamp"))
    reference = _as_str(raw.get("reference") or raw.get("ref") or raw.get("transactionId") or raw.get("txId"))

    return amount_f, payer, date, reference
