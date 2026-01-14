from __future__ import annotations

import hashlib
import logging
import time
import uuid

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

app = FastAPI(title="verifyreceipt-backend", version="0.1.0")

# For MVP/dev. In production, restrict allow_origins.
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=False,
    allow_methods=["*"],
    allow_headers=["*"],
)

cache = TtlCache(ttl_seconds=60.0)

logger = logging.getLogger("verifyreceipt")
rate_limiter = FixedWindowRateLimiter(limit=settings.rate_limit_per_minute, window_seconds=60)


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
async def api_verify_reference(req: VerifyReferenceRequest) -> NormalizedVerification:
    cache_key = f"ref:{req.provider.value}:{req.reference}:{req.suffix or ''}:{req.phone or ''}"
    cached = cache.get(cache_key)
    if cached:
        return cached

    # basic validation
    if req.provider in (Provider.cbe, Provider.abyssinia) and not req.suffix:
        raise HTTPException(status_code=400, detail="suffix is required for this provider")
    if req.provider == Provider.cbebirr and not req.phone:
        raise HTTPException(status_code=400, detail="phone is required for cbebirr")

    try:
        raw = await verify_by_reference(
            provider=req.provider.value,
            reference=req.reference,
            suffix=req.suffix,
            phone=req.phone,
        )
    except UpstreamTimeout:
        raise HTTPException(
            status_code=504,
            detail="Upstream verification timed out. Please try again.",
        )
    except UpstreamConnectionError:
        raise HTTPException(
            status_code=502,
            detail="Cannot reach upstream verification service. Please try again.",
        )
    except UpstreamError as e:
        raise HTTPException(status_code=502, detail={"upstream": e.body})
    except Exception as e:
        raise HTTPException(status_code=400, detail=str(e))

    status = normalize_status(raw)
    amount, payer, date, reference = normalize_fields(raw)

    out = NormalizedVerification(
        status=status,
        provider=req.provider.value,
        reference=reference or req.reference,
        amount=amount,
        payer=payer,
        date=date,
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
    except UpstreamTimeout:
        raise HTTPException(
            status_code=504,
            detail="Upstream verification timed out. Please try again.",
        )
    except UpstreamConnectionError:
        raise HTTPException(
            status_code=502,
            detail="Cannot reach upstream verification service. Please try again.",
        )
    except UpstreamError as e:
        raise HTTPException(status_code=502, detail={"upstream": e.body})
    except Exception as e:
        raise HTTPException(status_code=400, detail=str(e))

    status = normalize_status(raw)
    amount, payer, date, reference = normalize_fields(raw)

    out = NormalizedVerification(
        status=status,
        provider=provider,
        reference=reference,
        amount=amount,
        payer=payer,
        date=date,
        raw=raw,
    )

    cache.set(cache_key, out)
    return out
