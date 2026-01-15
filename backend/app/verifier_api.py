from __future__ import annotations

from typing import Any, Optional

import httpx

from .settings import settings


PROVIDER_TO_ENDPOINT: dict[str, str] = {
    "telebirr": "/verify-telebirr",
    "cbe": "/verify-cbe",
    "dashen": "/verify-dashen",
    "abyssinia": "/verify-abyssinia",
    "cbebirr": "/verify-cbebirr",
}


class UpstreamError(RuntimeError):
    def __init__(self, status_code: int, body: Any):
        super().__init__(f"Upstream error: {status_code}")
        self.status_code = status_code
        self.body = body


class UpstreamTimeout(RuntimeError):
    pass


class UpstreamConnectionError(RuntimeError):
    pass


def _timeout() -> httpx.Timeout:
    total = settings.upstream_timeout_seconds
    connect = settings.upstream_connect_timeout_seconds
    # Keep connect <= total to avoid confusing configs.
    if connect > total:
        connect = total
    return httpx.Timeout(total, connect=connect)


async def verify_by_reference(
    *, provider: str, reference: str, suffix: Optional[str], phone: Optional[str]
) -> dict[str, Any]:
    if provider not in PROVIDER_TO_ENDPOINT:
        raise ValueError("Unsupported provider")

    if not settings.verify_api_key:
        raise ValueError("VERIFY_API_KEY is not configured")

    payload: dict[str, Any] = {"reference": reference}

    if suffix:
        payload["suffix"] = suffix
        payload["accountSuffix"] = suffix
    if phone:
        payload["phone"] = phone
        payload["phoneNumber"] = phone

    url = settings.verify_api_base_url.rstrip("/") + PROVIDER_TO_ENDPOINT[provider]

    try:
        async with httpx.AsyncClient(timeout=_timeout()) as client:
            resp = await client.post(
                url,
                json=payload,
                headers={"x-api-key": settings.verify_api_key},
            )
    except httpx.TimeoutException as e:
        raise UpstreamTimeout(str(e))
    except httpx.RequestError as e:
        raise UpstreamConnectionError(str(e))

    try:
        data = resp.json()
    except Exception:
        data = {"rawText": resp.text}

    if resp.status_code >= 400:
        raise UpstreamError(resp.status_code, data)

    return data


async def verify_by_image(*, image_bytes: bytes, filename: str, suffix: Optional[str]) -> dict[str, Any]:
    if not settings.verify_api_key:
        raise ValueError("VERIFY_API_KEY is not configured")

    url = settings.verify_api_base_url.rstrip("/") + "/verify-image"

    files = {"image": (filename, image_bytes, "image/jpeg")}
    data: dict[str, Any] = {}
    if suffix:
        data["suffix"] = suffix
        data["accountSuffix"] = suffix

    try:
        async with httpx.AsyncClient(timeout=_timeout()) as client:
            resp = await client.post(
                url,
                data=data,
                files=files,
                headers={"x-api-key": settings.verify_api_key},
            )
    except httpx.TimeoutException as e:
        raise UpstreamTimeout(str(e))
    except httpx.RequestError as e:
        raise UpstreamConnectionError(str(e))

    try:
        out = resp.json()
    except Exception:
        out = {"rawText": resp.text}

    if resp.status_code >= 400:
        raise UpstreamError(resp.status_code, out)

    return out
