from __future__ import annotations

import json
import hashlib
import logging
import time
import uuid
from typing import Any

import httpx
from fastapi import FastAPI, File, Form, HTTPException, Request, UploadFile
from fastapi.middleware.cors import CORSMiddleware
from starlette.responses import JSONResponse

from .cache import TtlCache
from .normalize import normalize_fields, normalize_status
from .schemas import NormalizedVerification, Provider, VerifyReferenceRequest
from .settings import settings
from .rate_limit import FixedWindowRateLimiter
from .request_utils import get_client_ip
from .verifier_api import (
    UpstreamConnectionError,
    UpstreamError,
    UpstreamTimeout,
    verify_by_image,
    verify_by_reference,
)

from .cbe_receipt import CbeReceiptNotFound, verify_cbe_receipt_pdf
from .telebirr_receipt import TelebirrReceiptNotFound, verify_telebirr_receipt_html


def _contains_puppeteer_error(value: Any, depth: int = 0) -> bool:
    if depth > 4:
        return False
    if value is None:
        return False
    if isinstance(value, str):
        v = value.lower()
        return (
            "puppeteer" in v
            or "could not find chrome" in v
            or "chrome (ver." in v
            or "browsers install" in v
            or "pptr.dev" in v
            or "cache path" in v
        )
    if isinstance(value, dict):
        for k, v in value.items():
            if _contains_puppeteer_error(k, depth + 1) or _contains_puppeteer_error(v, depth + 1):
                return True
        return False
    if isinstance(value, (list, tuple)):
        return any(_contains_puppeteer_error(v, depth + 1) for v in value)
    return False


def _looks_like_automation_error(raw: object) -> bool:
    try:
        text = json.dumps(raw).lower()
    except (TypeError, ValueError):
        text = str(raw).lower()

    needles = [
        "puppeteer",
        "could not find chrome",
        "chromium",
        "browser install",
        "pptr.dev",
    ]
    return any(n in text for n in needles)


def _looks_like_not_found(raw: object) -> bool:
    if raw is None:
        return False
    if isinstance(raw, str):
        return "not found" in raw.lower() or "receipt not found" in raw.lower()
    if isinstance(raw, dict):
        msg = raw.get("message") or raw.get("detail")
        if isinstance(msg, str) and ("not found" in msg.lower() or "receipt not found" in msg.lower()):
            return True
        # Sometimes the message is nested.
        data = raw.get("data")
        if isinstance(data, dict):
            for k in ("message", "detail", "error", "reason"):
                v = data.get(k)
                if isinstance(v, str) and ("not found" in v.lower() or "receipt not found" in v.lower()):
                    return True
    return False


def _compute_confidence(*, status: str, amount: float | None, payer: str | None, date: str | None) -> str:
    if status != "SUCCESS":
        return "low"
    filled = sum(
        1
        for v in (
            amount,
            payer,
            date,
        )
        if v is not None and (not isinstance(v, str) or v.strip() != "")
    )
    if filled >= 3:
        return "high"
    if filled >= 1:
        return "medium"
    return "low"

app = FastAPI(title="verifyreceipt-backend", version="0.1.0")

# For MVP/dev. In production, restrict allow_origins.
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=False,
    allow_methods=["*"],
    allow_headers=["*"],
)

cache = TtlCache(ttl_seconds=float(settings.cache_ttl_seconds))

logger = logging.getLogger("verifyreceipt")
rate_limiter = FixedWindowRateLimiter(limit=settings.rate_limit_per_minute, window_seconds=60)
local_rate_limiters: dict[str, FixedWindowRateLimiter] = {
    "cbe": FixedWindowRateLimiter(limit=settings.local_rate_limit_cbe_per_minute, window_seconds=60),
    "telebirr": FixedWindowRateLimiter(limit=settings.local_rate_limit_telebirr_per_minute, window_seconds=60),
}


@app.middleware("http")
async def request_logging_and_rate_limit(request: Request, call_next):
    request_id = uuid.uuid4().hex
    ip = get_client_ip(request)
    start = time.perf_counter()

    decision = None

    # Don't rate-limit health checks.
    if settings.rate_limit_enabled and request.url.path != "/health":
        decision = rate_limiter.hit(ip)
        if not decision.allowed:
            duration_ms = int((time.perf_counter() - start) * 1000)
            logger.warning(
                "rate_limited request_id=%s ip=%s method=%s path=%s status=429 duration_ms=%s",
                request_id,
                ip,
                request.method,
                request.url.path,
                duration_ms,
            )
            return JSONResponse(
                status_code=429,
                content={"detail": "Too many requests"},
                headers={
                    "x-request-id": request_id,
                    "x-ratelimit-limit": str(decision.limit),
                    "x-ratelimit-remaining": str(decision.remaining),
                    "x-ratelimit-reset": str(decision.reset_epoch_seconds),
                },
            )

    response = await call_next(request)

    duration_ms = int((time.perf_counter() - start) * 1000)
    response.headers["x-request-id"] = request_id
    if decision is not None:
        response.headers["x-ratelimit-limit"] = str(decision.limit)
        response.headers["x-ratelimit-remaining"] = str(decision.remaining)
        response.headers["x-ratelimit-reset"] = str(decision.reset_epoch_seconds)

    logger.info(
        "request_id=%s ip=%s method=%s path=%s status=%s duration_ms=%s",
        request_id,
        ip,
        request.method,
        request.url.path,
        response.status_code,
        duration_ms,
    )
    return response


@app.get("/health")
async def health() -> dict[str, str]:
    return {"status": "ok"}


@app.post("/api/verify/reference", response_model=NormalizedVerification)
async def api_verify_reference(req: VerifyReferenceRequest, request: Request) -> NormalizedVerification:
    cache_key = f"ref:{req.provider.value}:{req.reference}:{req.suffix or ''}:{req.phone or ''}"
    cached = cache.get(cache_key)
    if cached:
        return cached
    ip = get_client_ip(request)

    async def _try_local() -> dict[str, Any] | None:
        if settings.local_rate_limit_enabled:
            limiter = local_rate_limiters.get(req.provider.value)
            if limiter is not None:
                decision = limiter.hit(f"{ip}:{req.provider.value}:local")
                if not decision.allowed:
                    raise HTTPException(
                        status_code=429,
                        detail="Too many requests for this provider. Please try again shortly.",
                        headers={
                            "x-ratelimit-limit": str(decision.limit),
                            "x-ratelimit-remaining": str(decision.remaining),
                            "x-ratelimit-reset": str(decision.reset_epoch_seconds),
                        },
                    )
        if req.provider == Provider.cbe and settings.local_cbe_receipt_enabled:
            try:
                return await verify_cbe_receipt_pdf(reference=req.reference)
            except CbeReceiptNotFound:
                return {"success": False, "message": "Receipt not found"}
        if req.provider == Provider.telebirr and settings.local_telebirr_receipt_enabled:
            try:
                return await verify_telebirr_receipt_html(reference=req.reference)
            except TelebirrReceiptNotFound:
                return {"success": False, "message": "Receipt not found"}
        return None

    upstream_raw: dict[str, Any] | None = None
    upstream_error: Exception | None = None

    # Try upstream first (verify.leul.et via proxy upstream), then fall back to local.
    try:
        upstream_raw = await verify_by_reference(
            provider=req.provider.value,
            reference=req.reference,
            suffix=req.suffix,
            phone=req.phone,
        )
    except (UpstreamTimeout, UpstreamConnectionError, UpstreamError, ValueError) as e:
        upstream_error = e

    # Decide whether upstream looks good.
    should_fallback = False
    if upstream_raw is None:
        # Upstream call failed; try local if enabled.
        should_fallback = True
    else:
        if _contains_puppeteer_error(upstream_raw) or _looks_like_automation_error(upstream_raw):
            should_fallback = True
        else:
            upstream_status = normalize_status(upstream_raw)
            # Only fall back on an explicit "not found" result (avoid falling back on PENDING).
            if upstream_status == "FAILED" and _looks_like_not_found(upstream_raw):
                should_fallback = True

    # If the upstream returns a 404 error, treat it as not found and fall back.
    if not should_fallback and isinstance(upstream_error, UpstreamError):
        if upstream_error.status_code == 404 or _looks_like_not_found(upstream_error.body):
            should_fallback = True

    local_raw: dict[str, Any] | None = None
    if should_fallback:
        local_raw = await _try_local()

    # Choose the best available result.
    raw: dict[str, Any] | None = None
    if local_raw is not None and normalize_status(local_raw) == "SUCCESS":
        raw = local_raw
    elif upstream_raw is not None:
        raw = upstream_raw
    elif local_raw is not None:
        raw = local_raw

    source: str | None = None
    if raw is not None:
        if local_raw is not None and raw is local_raw:
            source = "local"
        elif upstream_raw is not None and raw is upstream_raw:
            source = "upstream"

    if raw is None:
        # No local adapter for this provider; surface upstream error.
        if isinstance(upstream_error, UpstreamTimeout):
            raise HTTPException(status_code=504, detail="Upstream verification timed out. Please try again.")
        if isinstance(upstream_error, UpstreamConnectionError):
            raise HTTPException(status_code=502, detail="Cannot reach upstream verification service. Please try again.")
        if isinstance(upstream_error, UpstreamError):
            logger.warning("upstream_error provider=%s body=%s", req.provider.value, upstream_error.body)
            raise HTTPException(status_code=502, detail="Upstream verification failed. Please try again.")
        if isinstance(upstream_error, httpx.TimeoutException):
            raise HTTPException(status_code=504, detail="Verification timed out. Please try again.")

        # Common case: missing VERIFY_API_KEY.
        if upstream_error is not None:
            raise HTTPException(status_code=400, detail=str(upstream_error))

        raise HTTPException(status_code=502, detail="Verification failed. Please try again.")

    # Some upstream providers may fail due to their own automation/runtime issues
    # (e.g. Puppeteer/Chrome missing). Don't show the dev error to end users.
    if _looks_like_automation_error(raw):
        raise HTTPException(
            status_code=503,
            detail="Verification is temporarily unavailable for this provider. Please try again later.",
        )

    status = normalize_status(raw)
    amount, payer, date, reference = normalize_fields(raw)

    confidence = _compute_confidence(status=status, amount=amount, payer=payer, date=date)

    out = NormalizedVerification(
        status=status,
        provider=req.provider.value,
        reference=reference or req.reference,
        amount=amount,
        payer=payer,
        date=date,
        source=source,
        confidence=confidence,
        raw=raw,
    )

    cache.set(cache_key, out)
    return out


@app.post("/api/verify/receipt", response_model=NormalizedVerification)
async def api_verify_receipt(
    image: UploadFile = File(...),
    provider: str | None = Form(default=None),
    suffix: str | None = Form(default=None),
) -> NormalizedVerification:
    # Upstream /verify-image is mainly for Telebirr + CBE.
    if provider and provider not in ("telebirr", "cbe"):
        raise HTTPException(status_code=400, detail="receipt upload supports provider telebirr or cbe")

    if provider == "cbe" and not suffix:
        raise HTTPException(status_code=400, detail="suffix is required for CBE receipt verification")

    image_bytes = await image.read()
    digest = hashlib.sha256(image_bytes).hexdigest()[:16]
    cache_key = f"img:{digest}:{provider or ''}:{suffix or ''}"

    cached = cache.get(cache_key)
    if cached:
        return cached

    try:
        raw = await verify_by_image(
            image_bytes=image_bytes,
            filename=image.filename or "receipt.jpg",
            suffix=suffix,
        )
        if _contains_puppeteer_error(raw):
            raise HTTPException(
                status_code=503,
                detail="Verification service is temporarily unavailable. Please try again later.",
            )
    except UpstreamTimeout as exc:
        raise HTTPException(
            status_code=504,
            detail="Upstream verification timed out. Please try again.",
        ) from exc
    except UpstreamConnectionError as exc:
        raise HTTPException(
            status_code=502,
            detail="Cannot reach upstream verification service. Please try again.",
        ) from exc
    except UpstreamError as e:
        logger.warning("upstream_error provider=%s body=%s", provider, e.body)
        raise HTTPException(
            status_code=502,
            detail="Upstream verification failed. Please try again.",
        ) from e
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e)) from e

    if _looks_like_automation_error(raw):
        raise HTTPException(
            status_code=503,
            detail="Verification is temporarily unavailable for this provider. Please try again later.",
        )

    status = normalize_status(raw)
    amount, payer, date, reference = normalize_fields(raw)

    confidence = _compute_confidence(status=status, amount=amount, payer=payer, date=date)

    out = NormalizedVerification(
        status=status,
        provider=provider,
        reference=reference,
        amount=amount,
        payer=payer,
        date=date,
        source="upstream",
        confidence=confidence,
        raw=raw,
    )

    cache.set(cache_key, out)
    return out
