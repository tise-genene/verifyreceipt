from __future__ import annotations

import json
import re
from typing import Any, Optional

import httpx
from bs4 import BeautifulSoup

from .settings import settings
from .resilience import CircuitBreaker, RetryConfig, CircuitOpen, retry_async


class TelebirrReceiptNotFound(RuntimeError):
    pass


_breaker = CircuitBreaker(
    name="telebirr_receipt",
    enabled=settings.local_circuit_breaker_enabled,
    failure_threshold=settings.local_circuit_failure_threshold,
    reset_seconds=settings.local_circuit_reset_seconds,
)


def _clean(s: str) -> str:
    return re.sub(r"\s+", " ", s).strip()


def _capture_between(text: str, start_label: str, end_label: str) -> Optional[str]:
    pattern = re.escape(start_label) + r"\s+(?P<val>.+?)\s+" + re.escape(end_label)
    m = re.search(pattern, text, flags=re.IGNORECASE)
    if not m:
        return None
    return _clean(m.group("val"))


def _parse_amount_birr(text: str, label: str) -> Optional[float]:
    # Matches patterns like: "Total Paid Amount 2.00 Birr"
    m = re.search(
        re.escape(label) + r"\s+([0-9][0-9,]*(?:\.[0-9]{1,2})?)\s*Birr\b",
        text,
        flags=re.IGNORECASE,
    )
    if not m:
        return None
    raw = m.group(1).replace(",", "")
    try:
        return float(raw)
    except Exception:
        return None


def _parse_status(text: str) -> Optional[str]:
    # "transaction status Completed" (also possibly Failed/Pending)
    m = re.search(r"transaction\s+status\s+([A-Za-z]+)", text, flags=re.IGNORECASE)
    if m:
        return _clean(m.group(1)).capitalize()
    return None


def _parse_invoice_no(text: str) -> Optional[str]:
    for pat in [r"Invoice\s*No\.?\s*([A-Z0-9]{6,})\b", r"Invoice\s*No\s*[:#]?\s*([A-Z0-9]{6,})\b"]:
        m = re.search(pat, text, flags=re.IGNORECASE)
        if m:
            return m.group(1).upper()
    return None


def _parse_payment_date(text: str) -> Optional[str]:
    # Example: 15-01-2026 16:24:00
    m = re.search(r"\b(\d{2}-\d{2}-\d{4}\s+\d{2}:\d{2}:\d{2})\b", text)
    if m:
        return m.group(1)
    return None


def _parse_birr_value(value: Any) -> Optional[float]:
    if value is None:
        return None
    if isinstance(value, (int, float)):
        return float(value)
    if not isinstance(value, str):
        return None
    m = re.search(r"([0-9][0-9,]*(?:\.[0-9]{1,2})?)", value)
    if not m:
        return None
    try:
        return float(m.group(1).replace(",", ""))
    except Exception:
        return None


def _extract_json_payload(text: str) -> Optional[dict[str, Any]]:
    # Some pages embed the same JSON payload in a <script> tag.
    # Try to locate the first JSON object containing "success".
    idx = text.find("{\"success\"")
    if idx == -1:
        idx = text.find("{'success'")
    if idx == -1:
        return None

    # Best-effort brace matching.
    depth = 0
    start = None
    for i in range(idx, len(text)):
        ch = text[i]
        if ch == "{":
            if start is None:
                start = i
            depth += 1
        elif ch == "}":
            depth -= 1
            if start is not None and depth == 0:
                snippet = text[start : i + 1]
                # Normalize quotes if needed.
                try:
                    return json.loads(snippet)
                except Exception:
                    pass
                try:
                    return json.loads(snippet.replace("'", '"'))
                except Exception:
                    return None
    return None


async def verify_telebirr_receipt_html(*, reference: str) -> dict[str, Any]:
    ref = reference.strip()
    if not re.fullmatch(r"[A-Za-z0-9]+", ref):
        raise ValueError("reference must be alphanumeric")

    base = settings.telebirr_receipt_base_url.rstrip("/")
    url = f"{base}/{ref}"

    headers = {
        "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
        "User-Agent": "verifyreceipt-better-verifier/0.1",
    }

    timeout = httpx.Timeout(
        settings.upstream_timeout_seconds,
        connect=min(settings.upstream_connect_timeout_seconds, settings.upstream_timeout_seconds),
    )

    async def _fetch() -> httpx.Response:
        async with httpx.AsyncClient(timeout=timeout, follow_redirects=True) as client:
            return await client.get(url, headers=headers)

    def _retry_if(e: Exception) -> bool:
        return isinstance(e, (httpx.TimeoutException, httpx.RequestError, RuntimeError))

    _breaker.before_call()
    try:
        resp = await retry_async(
            _fetch,
            config=RetryConfig(
                attempts=settings.local_retry_attempts,
                base_delay_ms=settings.local_retry_base_delay_ms,
                max_delay_ms=settings.local_retry_max_delay_ms,
            ),
            retry_if=_retry_if,
        )
    except TelebirrReceiptNotFound:
        _breaker.record_success()
        raise
    except CircuitOpen:
        raise RuntimeError("Telebirr receipt service temporarily unavailable")
    except Exception:
        _breaker.record_failure()
        raise
    else:
        _breaker.record_success()

    if resp.status_code == 404:
        raise TelebirrReceiptNotFound("Receipt not found")
    if resp.status_code in (429, 500, 502, 503, 504):
        raise RuntimeError(f"Telebirr receipt fetch transient failure: {resp.status_code}")
    if resp.status_code >= 400:
        raise RuntimeError(f"Telebirr receipt fetch failed: {resp.status_code}")

    ctype = (resp.headers.get("content-type") or "").lower()

    # First: handle JSON responses directly.
    if "json" in ctype:
        payload = resp.json()
    else:
        # Otherwise treat as HTML/text and also try to extract embedded JSON.
        soup = BeautifulSoup(resp.text, "html.parser")
        text = _clean(soup.get_text(" ", strip=True))
        if not text:
            raise RuntimeError("Empty Telebirr receipt")
        payload = _extract_json_payload(resp.text) or _extract_json_payload(text)

    if isinstance(payload, dict) and isinstance(payload.get("data"), dict):
        data_in = payload["data"]
        payer_name = data_in.get("payerName")
        payer_telebirr_no = data_in.get("payerTelebirrNo")
        credited_name = data_in.get("creditedPartyName")
        credited_account_no = data_in.get("creditedPartyAccountNo")
        status = data_in.get("transactionStatus")
        receipt_no = data_in.get("receiptNo")
        payment_date = data_in.get("paymentDate")

        settled_amount_text = data_in.get("settledAmount")
        service_fee_text = data_in.get("serviceFee")
        service_fee_vat_text = data_in.get("serviceFeeVAT")
        total_paid_text = data_in.get("totalPaidAmount")
        bank_name = data_in.get("bankName")

        amount = _parse_birr_value(total_paid_text) or _parse_birr_value(settled_amount_text)

        success = bool(payload.get("success", True))
        if isinstance(status, str) and status.lower() not in ("completed", "success", "successful"):
            success = False

        out_data: dict[str, Any] = {
            "reference": ref,
            "transactionId": (receipt_no or ref),
            "payerName": payer_name,
            "payerTelebirrNo": payer_telebirr_no,
            "creditedPartyName": credited_name,
            "creditedPartyAccountNo": credited_account_no,
            "transactionStatus": status,
            "receiptNo": receipt_no,
            "paymentDate": payment_date,
            "settledAmount": settled_amount_text,
            "serviceFee": service_fee_text,
            "serviceFeeVAT": service_fee_vat_text,
            "totalPaidAmount": total_paid_text,
            "bankName": bank_name,
            "amount": amount,
            "source": "telebirr_receipt",
            "receiptUrl": url,
        }

        # rawText isn't meaningful in JSON mode; omit it.
        return {"success": success, "data": out_data}

    # Fallback: extract fields based on visible English labels in the receipt page.
    if "html" not in ctype and "text" not in ctype:
        raise TelebirrReceiptNotFound("Receipt not found")

    soup = BeautifulSoup(resp.text, "html.parser")
    text = _clean(soup.get_text(" ", strip=True))
    if not text:
        raise RuntimeError("Empty Telebirr receipt")

    # Extract fields based on the visible English labels used in the receipt page.
    payer_name = _capture_between(text, "Payer Name", "Payer telebirr no.")
    payer_phone = _capture_between(text, "Payer telebirr no.", "Payer account type")
    credited_name = _capture_between(text, "Credited Party name", "Credited telebirr account no")
    credited_account = _capture_between(text, "Credited telebirr account no", "transaction status")

    status = _parse_status(text)
    invoice_no = _parse_invoice_no(text) or ref
    payment_date = _parse_payment_date(text)

    total_paid = _parse_amount_birr(text, "Total Paid Amount")
    settled_amount = _parse_amount_birr(text, "Settled Amount")

    amount = total_paid if total_paid is not None else settled_amount

    success = True
    if status and status.lower() not in ("completed", "success", "successful"):
        success = False

    data: dict[str, Any] = {
        "reference": ref,
        "invoiceNo": invoice_no,
        "transactionId": invoice_no,
        "transactionStatus": status,
        "payerName": payer_name,
        "payerTelebirrNo": payer_phone,
        "creditedPartyName": credited_name,
        "creditedPartyAccountNo": credited_account,
        "paymentDate": payment_date,
        "amount": amount,
        "source": "telebirr_receipt_html",
        "receiptUrl": url,
    }

    return {"success": success, "data": data, "rawText": text}
