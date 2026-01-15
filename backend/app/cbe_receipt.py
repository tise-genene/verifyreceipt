from __future__ import annotations

import io
import re
from typing import Any, Optional

import httpx
from pypdf import PdfReader

from .settings import settings
from .resilience import CircuitBreaker, RetryConfig, CircuitOpen, retry_async


class CbeReceiptNotFound(RuntimeError):
    pass


_breaker = CircuitBreaker(
    name="cbe_receipt_pdf",
    enabled=settings.local_circuit_breaker_enabled,
    failure_threshold=settings.local_circuit_failure_threshold,
    reset_seconds=settings.local_circuit_reset_seconds,
)


def _clean(s: str) -> str:
    return re.sub(r"\s+", " ", s).strip()


def _parse_amount(text: str) -> Optional[float]:
    # Prefer specific fields from the VAT invoice layout to avoid false matches like "ETB 15%".
    preferred_patterns = [
        r"Transferred\s+Amount\s+([0-9][0-9,]*(?:\.[0-9]{1,2})?)\s*ETB\b",
        r"Total\s+amount\s+debited\s+from\s+customers\s+account\s+([0-9][0-9,]*(?:\.[0-9]{1,2})?)\s*ETB\b",
    ]
    for pat in preferred_patterns:
        m = re.search(pat, text, flags=re.IGNORECASE)
        if m:
            raw = m.group(1).replace(",", "")
            try:
                return float(raw)
            except Exception:
                pass

    # Fallback: use the last numeric amount that is immediately followed by ETB.
    matches = re.findall(r"([0-9][0-9,]*(?:\.[0-9]{1,2})?)\s*ETB\b", text, flags=re.IGNORECASE)
    if not matches:
        return None
    raw = matches[-1].replace(",", "")
    try:
        return float(raw)
    except Exception:
        return None


def _extract_transaction_id(text: str) -> Optional[str]:
    # Common patterns seen in receipts.
    for pat in [
        r"\btransaction\s*id\s*[:#]?\s*([A-Z0-9]{8,})\b",
        r"\btransaction\s*no\s*[:#]?\s*([A-Z0-9]{8,})\b",
        r"\b(FT[0-9A-Z]{6,})\b",
    ]:
        m = re.search(pat, text, flags=re.IGNORECASE)
        if m:
            return m.group(1).upper()
    return None


def _extract_parties_and_date(text: str) -> tuple[Optional[str], Optional[str], Optional[str]]:
    # VAT invoice layout typically contains:
    # "Payer <NAME> Account ... Receiver <NAME> Account ... Payment Date & Time <DATE>"
    payer = None
    payee = None
    date = None

    m = re.search(r"\bPayer\s+(?P<payer>.+?)\s+Account\b", text, flags=re.IGNORECASE)
    if m:
        payer = _clean(m.group("payer"))

    m = re.search(r"\bReceiver\s+(?P<payee>.+?)\s+Account\b", text, flags=re.IGNORECASE)
    if m:
        payee = _clean(m.group("payee"))

    m = re.search(
        r"Payment\s+Date\s*&\s*Time\s+(?P<date>\d{1,2}/\d{1,2}/\d{4},\s*\d{1,2}:\d{2}:\d{2}\s*(?:AM|PM))",
        text,
        flags=re.IGNORECASE,
    )
    if m:
        date = _clean(m.group("date"))

    # Alternative layout seen in some CBE receipts.
    if not (payer and payee and date):
        m = re.search(
            r"debited\s+from\s+(?P<payer>.+?)\s+for\s+(?P<payee>.+?)\s+on\s+(?P<date>\d{1,2}-[A-Za-z]{3}-\d{4})",
            text,
            flags=re.IGNORECASE,
        )
        if m:
            payer = payer or _clean(m.group("payer"))
            payee = payee or _clean(m.group("payee"))
            date = date or _clean(m.group("date"))

    return payer, payee, date


def _extract_reference_no(text: str) -> Optional[str]:
    m = re.search(
        r"Reference\s*No\.?\s*(?:\([^)]*\))?\s*([A-Z0-9]{6,})\b",
        text,
        flags=re.IGNORECASE,
    )
    if m:
        return m.group(1).upper()
    return None


async def verify_cbe_receipt_pdf(*, reference: str) -> dict[str, Any]:
    # Basic input hardening.
    ref = reference.strip()
    if not re.fullmatch(r"[A-Za-z0-9]+", ref):
        raise ValueError("reference must be alphanumeric")

    base = settings.cbe_receipt_base_url.rstrip("/")
    url = f"{base}/?id={ref}"

    headers = {
        "Accept": "application/pdf,*/*",
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
    except CbeReceiptNotFound:
        _breaker.record_success()
        raise
    except CircuitOpen:
        raise RuntimeError("CBE receipt service temporarily unavailable")
    except Exception:
        _breaker.record_failure()
        raise
    else:
        _breaker.record_success()

    if resp.status_code == 404:
        raise CbeReceiptNotFound("Receipt not found")
    if resp.status_code in (429, 500, 502, 503, 504):
        raise RuntimeError(f"CBE receipt fetch transient failure: {resp.status_code}")
    if resp.status_code >= 400:
        raise RuntimeError(f"CBE receipt fetch failed: {resp.status_code}")

    ctype = resp.headers.get("content-type", "").lower()
    if "pdf" not in ctype:
        # Some edge deployments may return HTML; treat as not found.
        raise CbeReceiptNotFound("Receipt not found")

    reader = PdfReader(io.BytesIO(resp.content))
    text = "\n".join([(p.extract_text() or "") for p in reader.pages[:2]])
    text = _clean(text)

    if not text:
        raise RuntimeError("Empty PDF text")

    tx = _extract_reference_no(text) or _extract_transaction_id(text) or ref
    payer, payee, date = _extract_parties_and_date(text)
    amount = _parse_amount(text)

    data: dict[str, Any] = {
        # Preserve the input reference (this is what the user scanned/typed).
        "reference": ref,
        "transactionId": tx,
        "payerName": payer,
        "creditedPartyName": payee,
        "paymentDate": date,
        "amount": amount,
        "source": "cbe_receipt_pdf",
        "receiptUrl": url,
    }

    # Keep the raw text for debugging (backend may log it, UI hides it in release).
    return {"success": True, "data": data, "rawText": text}
