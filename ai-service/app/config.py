import os

try:
    from pydantic_settings import BaseSettings, SettingsConfigDict
    from pydantic import Field

    class Settings(BaseSettings):
        model_config = SettingsConfigDict(env_file=".env", extra="ignore")

        APP_NAME: str = "AuraCommerce AI Copilot Service"
        APP_ENV: str = Field(default="development", validation_alias="APP_ENV")
        DEBUG: bool = True
        PORT: int = Field(default=8010, validation_alias="PORT") # 8010 avoids collision with 8001-8005

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

except ImportError:
    class Settings:
        APP_NAME: str = os.getenv("APP_NAME", "AuraCommerce AI Copilot Service")
        APP_ENV: str = os.getenv("APP_ENV", "development")
        DEBUG: bool = True
        PORT: int = int(os.getenv("PORT", 8010))
        LLM_PROVIDER: str = os.getenv("LLM_PROVIDER", "ollama")
        OLLAMA_BASE_URL: str = os.getenv("OLLAMA_BASE_URL", "http://localhost:11434")
        OLLAMA_MODEL: str = os.getenv("OLLAMA_MODEL", "llama3.1:8b")
        OLLAMA_TEMPERATURE: float = 0.2
        OPENAI_API_KEY: str = os.getenv("OPENAI_API_KEY", "")
        OPENAI_MODEL: str = os.getenv("OPENAI_MODEL", "gpt-4o-mini")
        EMBEDDING_PROVIDER: str = os.getenv("EMBEDDING_PROVIDER", "local")
        EMBEDDING_MODEL: str = "all-MiniLM-L6-v2"
        CHROMA_PERSIST_DIR: str = os.getenv("CHROMA_PERSIST_DIR", "./data/chroma_db")
        ORDERS_SERVICE_URL: str = os.getenv("ORDERS_SERVICE_URL", "http://localhost:8003")
        PRODUCTS_SERVICE_URL: str = os.getenv("PRODUCTS_SERVICE_URL", "http://localhost:8004")
        INVENTORY_SERVICE_URL: str = os.getenv("INVENTORY_SERVICE_URL", "http://localhost:8001")
        COSMO_ROUTER_URL: str = os.getenv("COSMO_ROUTER_URL", "http://localhost:8080/graphql")
        REDIS_URL: str = os.getenv("REDIS_URL", "redis://localhost:6379/0")
        ENABLE_OBSERVABILITY: bool = os.getenv("ENABLE_OBSERVABILITY", "true").lower() == "true"
        PHOENIX_COLLECTOR_ENDPOINT: str = os.getenv("PHOENIX_COLLECTOR_ENDPOINT", "http://localhost:6006/v1/traces")
        REFUND_AUTO_APPROVE_LIMIT: float = 50.0
        SECURITY_ENABLED: bool = os.getenv("SECURITY_ENABLED", "false").lower() == "true"
        KEYCLOAK_ISSUER: str = os.getenv("KEYCLOAK_ISSUER", "http://localhost:8181/realms/microservices-realm")
        KEYCLOAK_JWKS_URI: str = os.getenv("KEYCLOAK_JWKS_URI", "http://keycloak:8181/realms/microservices-realm/protocol/openid-connect/certs")

    settings = Settings()
