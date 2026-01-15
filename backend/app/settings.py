from pydantic_settings import BaseSettings, SettingsConfigDict
from pydantic import Field


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", extra="ignore")

    verify_api_key: str = Field(default="", validation_alias="VERIFY_API_KEY")
    verify_api_base_url: str = Field(
        default="https://verifyapi.leulzenebe.pro",
        validation_alias="VERIFY_API_BASE_URL",
    )
    upstream_timeout_seconds: float = 60.0
    upstream_connect_timeout_seconds: float = 20.0
    port: int = 8080

    # Caching
    cache_ttl_seconds: float = Field(default=1800.0, validation_alias="CACHE_TTL_SECONDS")

    # Local verification (better-verifier) toggles
    local_cbe_receipt_enabled: bool = Field(
        default=False,
        validation_alias="LOCAL_CBE_RECEIPT_ENABLED",
    )
    cbe_receipt_base_url: str = Field(
        default="https://apps.cbe.com.et:100/",
        validation_alias="CBE_RECEIPT_BASE_URL",
    )

    local_telebirr_receipt_enabled: bool = Field(
        default=False,
        validation_alias="LOCAL_TELEBIRR_RECEIPT_ENABLED",
    )
    telebirr_receipt_base_url: str = Field(
        default="https://transactioninfo.ethiotelecom.et/receipt/",
        validation_alias="TELEBIRR_RECEIPT_BASE_URL",
    )

    # Simple per-IP fixed-window rate limit (in-memory).
    # For multi-instance scaling, replace with Redis.
    rate_limit_enabled: bool = True
    rate_limit_per_minute: int = 60

    # Per-provider rate limits for LOCAL fetches (in-memory)
    local_rate_limit_enabled: bool = Field(default=True, validation_alias="LOCAL_RATE_LIMIT_ENABLED")
    local_rate_limit_cbe_per_minute: int = Field(default=20, validation_alias="LOCAL_RATE_LIMIT_CBE_PER_MINUTE")
    local_rate_limit_telebirr_per_minute: int = Field(
        default=20,
        validation_alias="LOCAL_RATE_LIMIT_TELEBIRR_PER_MINUTE",
    )

    # Local fetch resilience
    local_retry_attempts: int = Field(default=3, validation_alias="LOCAL_RETRY_ATTEMPTS")
    local_retry_base_delay_ms: int = Field(default=200, validation_alias="LOCAL_RETRY_BASE_DELAY_MS")
    local_retry_max_delay_ms: int = Field(default=1500, validation_alias="LOCAL_RETRY_MAX_DELAY_MS")
    local_circuit_breaker_enabled: bool = Field(default=True, validation_alias="LOCAL_CIRCUIT_BREAKER_ENABLED")
    local_circuit_failure_threshold: int = Field(default=5, validation_alias="LOCAL_CIRCUIT_FAILURE_THRESHOLD")
    local_circuit_reset_seconds: int = Field(default=90, validation_alias="LOCAL_CIRCUIT_RESET_SECONDS")


settings = Settings()  # type: ignore[call-arg]
