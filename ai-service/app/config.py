from pydantic_settings import BaseSettings, SettingsConfigDict
from pydantic import Field


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", extra="ignore")

    APP_NAME: str = "AuraCommerce AI Copilot Service"
    APP_ENV: str = Field(default="development", validation_alias="APP_ENV")
    DEBUG: bool = Field(default=False, validation_alias="DEBUG")
    PORT: int = Field(default=8010, validation_alias="PORT")

    # Models / Local LLM Settings (Ollama)
    LLM_PROVIDER: str = Field(default="ollama", validation_alias="LLM_PROVIDER")
    OLLAMA_BASE_URL: str = Field(default="http://ollama:11434", validation_alias="OLLAMA_BASE_URL")
    OLLAMA_MODEL: str = Field(default="llama3.1:8b", validation_alias="OLLAMA_MODEL")
    OLLAMA_TEMPERATURE: float = 0.2

    # Optional Cloud fallback
    OPENAI_API_KEY: str = Field(default="", validation_alias="OPENAI_API_KEY")
    OPENAI_MODEL: str = Field(default="gpt-4o-mini", validation_alias="OPENAI_MODEL")

    # Knowledge / RAG Settings
    EMBEDDING_PROVIDER: str = Field(default="local", validation_alias="EMBEDDING_PROVIDER")
    EMBEDDING_MODEL: str = "all-MiniLM-L6-v2"
    CHROMA_PERSIST_DIR: str = Field(default="./data/chroma_db", validation_alias="CHROMA_PERSIST_DIR")

    # Microservices URLs for MCP Tools Integration
    ORDERS_SERVICE_URL: str = Field(default="http://orders-service:8003", validation_alias="ORDERS_SERVICE_URL")
    PRODUCTS_SERVICE_URL: str = Field(default="http://products-service:8004", validation_alias="PRODUCTS_SERVICE_URL")
    INVENTORY_SERVICE_URL: str = Field(default="http://inventory-service:8001", validation_alias="INVENTORY_SERVICE_URL")
    COSMO_ROUTER_URL: str = Field(default="http://cosmo-router:8080/graphql", validation_alias="COSMO_ROUTER_URL")

    # Shared Platform Redis Cache & Checkpoint State
    REDIS_URL: str = Field(default="redis://redis:6379/0", validation_alias="REDIS_URL")

    # Observability & Evals (Arize Phoenix)
    ENABLE_OBSERVABILITY: bool = Field(default=True, validation_alias="ENABLE_OBSERVABILITY")
    PHOENIX_COLLECTOR_ENDPOINT: str = Field(default="http://phoenix:6006/v1/traces", validation_alias="PHOENIX_COLLECTOR_ENDPOINT")

    # Human-in-the-Loop Policies
    REFUND_AUTO_APPROVE_LIMIT: float = 50.0

    # Keycloak / OAuth2 Security
    SECURITY_ENABLED: bool = Field(default=False, validation_alias="SECURITY_ENABLED")
    KEYCLOAK_ISSUER: str = Field(default="http://localhost:8181/realms/microservices-realm", validation_alias="KEYCLOAK_ISSUER")
    KEYCLOAK_JWKS_URI: str = Field(default="http://keycloak:8181/realms/microservices-realm/protocol/openid-connect/certs", validation_alias="KEYCLOAK_JWKS_URI")


settings = Settings()
