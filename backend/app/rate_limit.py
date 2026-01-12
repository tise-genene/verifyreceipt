from __future__ import annotations

import time
from dataclasses import dataclass


@dataclass
class RateLimitDecision:
    allowed: bool
    limit: int
    remaining: int
    reset_epoch_seconds: int


class FixedWindowRateLimiter:
    def __init__(self, *, limit: int, window_seconds: int = 60):
        self._limit = max(1, int(limit))
        self._window_seconds = int(window_seconds)
        self._buckets: dict[str, int] = {}

    def hit(self, identity: str) -> RateLimitDecision:
        now = time.time()
        window = int(now // self._window_seconds)
        reset = int((window + 1) * self._window_seconds)

        key = f"{identity}:{window}"
        count = self._buckets.get(key, 0) + 1
        self._buckets[key] = count

        # cheap cleanup: keep only current+previous window when dict grows
        if len(self._buckets) > 10_000:
            keep_prefix = f":{window}"
            keep_prefix_prev = f":{window - 1}"
            self._buckets = {
                k: v
                for k, v in self._buckets.items()
                if k.endswith(keep_prefix) or k.endswith(keep_prefix_prev)
            }

        remaining = max(0, self._limit - count)
        allowed = count <= self._limit
        return RateLimitDecision(
            allowed=allowed,
            limit=self._limit,
            remaining=remaining,
            reset_epoch_seconds=reset,
        )
