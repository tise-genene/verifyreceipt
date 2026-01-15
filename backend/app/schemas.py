from __future__ import annotations

from enum import Enum
from typing import Any, Literal, Optional

from pydantic import BaseModel, Field


class Provider(str, Enum):
    telebirr = "telebirr"
    cbe = "cbe"
    dashen = "dashen"
    abyssinia = "abyssinia"
    cbebirr = "cbebirr"


class VerifyReferenceRequest(BaseModel):
    provider: Provider
    reference: str = Field(min_length=3)

    # Provider-specific optional fields
    suffix: Optional[str] = None
    phone: Optional[str] = None


NormalizedStatus = Literal["SUCCESS", "FAILED", "PENDING"]

VerificationSource = Literal["upstream", "local"]
VerificationConfidence = Literal["high", "medium", "low"]


class NormalizedVerification(BaseModel):
    status: NormalizedStatus
    provider: Optional[str] = None
    reference: Optional[str] = None
    amount: Optional[float] = None
    payer: Optional[str] = None
    date: Optional[str] = None

    source: Optional[VerificationSource] = None
    confidence: Optional[VerificationConfidence] = None

    raw: dict[str, Any] = Field(default_factory=dict)
