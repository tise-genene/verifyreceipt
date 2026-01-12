from __future__ import annotations

from fastapi import Request


def get_client_ip(request: Request) -> str:
    # Render sits behind a proxy and will typically send X-Forwarded-For.
    forwarded = request.headers.get("x-forwarded-for")
    if forwarded:
        # first IP is the original client
        return forwarded.split(",")[0].strip()

    if request.client and request.client.host:
        return request.client.host

    return "unknown"
