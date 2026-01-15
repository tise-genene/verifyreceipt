from __future__ import annotations

import asyncio
import random
import time
from dataclasses import dataclass
from typing import Awaitable, Callable, TypeVar


class CircuitOpen(RuntimeError):
    pass


T = TypeVar("T")


@dataclass
class RetryConfig:
    attempts: int
    base_delay_ms: int
    max_delay_ms: int


class CircuitBreaker:
    def __init__(
        self,
        *,
        name: str,
        enabled: bool,
        failure_threshold: int,
        reset_seconds: int,
    ):
        self._name = name
        self._enabled = enabled
        self._failure_threshold = max(1, int(failure_threshold))
        self._reset_seconds = max(1, int(reset_seconds))

        self._consecutive_failures = 0
        self._open_until = 0.0

    def before_call(self) -> None:
        if not self._enabled:
            return
        now = time.monotonic()
        if now < self._open_until:
            raise CircuitOpen(f"Circuit open for {self._name}")

    def record_success(self) -> None:
        self._consecutive_failures = 0
        self._open_until = 0.0

    def record_failure(self) -> None:
        if not self._enabled:
            return
        self._consecutive_failures += 1
        if self._consecutive_failures >= self._failure_threshold:
            self._open_until = time.monotonic() + self._reset_seconds


async def retry_async(
    fn: Callable[[], Awaitable[T]],
    *,
    config: RetryConfig,
    retry_if: Callable[[Exception], bool],
) -> T:
    attempts = max(1, int(config.attempts))
    base = max(0, int(config.base_delay_ms)) / 1000.0
    max_delay = max(0, int(config.max_delay_ms)) / 1000.0

    last_exc: Exception | None = None
    for attempt in range(1, attempts + 1):
        try:
            return await fn()
        except Exception as e:
            last_exc = e
            if attempt >= attempts or not retry_if(e):
                raise

            # Exponential backoff with full jitter.
            delay = min(max_delay, base * (2 ** (attempt - 1)))
            delay = delay * random.random()  # full jitter
            if delay > 0:
                await asyncio.sleep(delay)

    # Should never reach here.
    raise last_exc  # type: ignore[misc]
