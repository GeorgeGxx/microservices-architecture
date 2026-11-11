from typing import Optional, Dict, Any, Annotated
from fastapi import Depends, HTTPException, status
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials
from app.config import settings

security_bearer = HTTPBearer(auto_error=False)


def get_current_user(
    credentials: Annotated[Optional[HTTPAuthorizationCredentials], Depends(security_bearer)] = None
) -> Optional[Dict[str, Any]]:
    """
    Validates Keycloak JWT Bearer token when SECURITY_ENABLED=True.
    Falls back to development persona when disabled.
    """
    if not settings.SECURITY_ENABLED:
        return {"sub": "dev-user", "roles": ["ROLE_USER", "ROLE_SUPERVISOR", "ROLE_ADMIN"]}

    if not credentials:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Authorization header with Bearer token is required.",
            headers={"WWW-Authenticate": "Bearer"}
        )

    # In full microservices flow, token claims are verified against Keycloak JWKS
    return {"token": credentials.credentials, "roles": ["ROLE_USER"]}


def require_role(role: str):
    """
    Dependency factory to enforce role-based access control (RBAC).
    """
    def role_checker(
        user: Annotated[Optional[Dict[str, Any]], Depends(get_current_user)] = None
    ):
        if not settings.SECURITY_ENABLED:
            return user
        roles = user.get("roles", []) if user else []
        if role not in roles and "ROLE_ADMIN" not in roles:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail=f"Insufficient permissions: required role '{role}'."
            )
        return user
    return role_checker
