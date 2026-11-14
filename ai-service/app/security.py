import functools
import logging
from typing import Optional, Dict, Any, Annotated, List
import jwt
from jwt import PyJWKClient
from fastapi import Depends, HTTPException, status
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials
from app.config import settings

logger = logging.getLogger("ai_service.security")
security_bearer = HTTPBearer(auto_error=False)


@functools.lru_cache(maxsize=4)
def _get_jwk_client(jwks_uri: str) -> PyJWKClient:
    return PyJWKClient(jwks_uri, cache_keys=True, lifespan=300)


def _extract_roles_from_dict(container: Any) -> List[str]:
    if not isinstance(container, dict):
        return []
    roles = container.get("roles")
    return [str(r) for r in roles] if isinstance(roles, list) else []


def _normalize_roles(payload: Dict[str, Any]) -> List[str]:
    raw_roles: List[str] = []
    raw_roles.extend(_extract_roles_from_dict(payload.get("realm_access")))
    raw_roles.extend(_extract_roles_from_dict(payload))

    resource_access = payload.get("resource_access")
    if isinstance(resource_access, dict):
        for client_data in resource_access.values():
            raw_roles.extend(_extract_roles_from_dict(client_data))

    normalized = set()
    for role in raw_roles:
        upper = role.strip().upper()
        if not upper:
            continue
        normalized.add(upper)
        if not upper.startswith("ROLE_"):
            normalized.add(f"ROLE_{upper}")

    return sorted(normalized) if normalized else ["ROLE_USER"]


def _validate_issuer(issuer: str) -> bool:
    if not issuer:
        return False
    expected = (settings.KEYCLOAK_ISSUER or "").rstrip("/")
    actual = issuer.rstrip("/")
    if expected and actual == expected:
        return True
    return actual.endswith("/realms/microservices-realm")


def verify_jwt_token(token: str) -> Dict[str, Any]:
    """
    Cryptographically validates a Keycloak RS256 JWT against the configured JWKS endpoint,
    enforcing signature verification, expiration, not-before, issuer, and optional audience.
    """
    try:
        jwk_client = _get_jwk_client(settings.KEYCLOAK_JWKS_URI)
        signing_key = jwk_client.get_signing_key_from_jwt(token)

        decode_options = {
            "verify_signature": True,
            "verify_exp": True,
            "verify_nbf": True,
            "verify_iat": True,
            "verify_aud": bool(settings.KEYCLOAK_AUDIENCE),
            "require": ["exp", "iss", "sub"],
        }
        audience = settings.KEYCLOAK_AUDIENCE if settings.KEYCLOAK_AUDIENCE else None

        payload = jwt.decode(
            token,
            signing_key.key,
            algorithms=["RS256"],
            audience=audience,
            options=decode_options,
        )
    except jwt.ExpiredSignatureError as exc:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Authentication token has expired.",
            headers={"WWW-Authenticate": "Bearer"},
        ) from exc
    except Exception as exc:
        logger.warning("JWT validation failed: %s", exc)
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid or unverifiable authentication token.",
            headers={"WWW-Authenticate": "Bearer"},
        ) from exc

    issuer = str(payload.get("iss", ""))
    if not _validate_issuer(issuer):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Untrusted token issuer.",
            headers={"WWW-Authenticate": "Bearer"},
        )

    roles = _normalize_roles(payload)
    return {
        "sub": payload.get("sub"),
        "preferred_username": payload.get("preferred_username") or payload.get("sub") or "authenticated-user",
        "email": payload.get("email"),
        "roles": roles,
        "claims": payload,
    }


def get_current_user(
    credentials: Annotated[Optional[HTTPAuthorizationCredentials], Depends(security_bearer)] = None
) -> Dict[str, Any]:
    """
    Validates Keycloak JWT Bearer token.
    In explicit non-production development bypass mode, returns a least-privilege customer identity
    (never automatic supervisor or admin privileges) if no Bearer token is supplied.
    """
    if credentials and credentials.credentials:
        return verify_jwt_token(credentials.credentials)

    if settings.is_dev_bypass_active():
        return {
            "sub": "dev-user",
            "preferred_username": "dev-user",
            "roles": ["ROLE_USER"],
        }

    raise HTTPException(
        status_code=status.HTTP_401_UNAUTHORIZED,
        detail="Authorization header with Bearer token is required.",
        headers={"WWW-Authenticate": "Bearer"},
    )


def require_role(role: str):
    """
    Dependency factory to enforce role-based access control (RBAC) across all environments.
    """
    required_upper = role.strip().upper()
    if not required_upper.startswith("ROLE_"):
        required_upper = f"ROLE_{required_upper}"

    def role_checker(
        user: Annotated[Dict[str, Any], Depends(get_current_user)]
    ) -> Dict[str, Any]:
        roles = [str(r).upper() for r in (user.get("roles") or [])]
        if required_upper not in roles and "ROLE_ADMIN" not in roles:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail=f"Insufficient permissions: required role '{required_upper}'.",
            )
        return user

    return role_checker
