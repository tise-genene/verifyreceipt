from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", extra="ignore")

    verify_api_key: str
    verify_api_base_url: str = "https://verifyapi.leulzenebe.pro"
    upstream_timeout_seconds: float = 60.0
    upstream_connect_timeout_seconds: float = 20.0
    port: int = 8080

    # Simple per-IP fixed-window rate limit (in-memory).
    # For multi-instance scaling, replace with Redis.
    rate_limit_enabled: bool = True
    rate_limit_per_minute: int = 60


settings = Settings()  # type: ignore[call-arg]
