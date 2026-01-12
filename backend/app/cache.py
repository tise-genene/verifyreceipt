from __future__ import annotations

import time
from dataclasses import dataclass
from typing import Any, Optional


@dataclass
class CacheItem:
    value: Any
    expires_at: float


class TtlCache:
    def __init__(self, ttl_seconds: float = 60.0):
        self._ttl = ttl_seconds
        self._store: dict[str, CacheItem] = {}

    def get(self, key: str) -> Optional[Any]:
        item = self._store.get(key)
        if not item:
            return None
        if time.time() >= item.expires_at:
            self._store.pop(key, None)
            return None
        return item.value

    def set(self, key: str, value: Any) -> None:
        self._store[key] = CacheItem(value=value, expires_at=time.time() + self._ttl)
