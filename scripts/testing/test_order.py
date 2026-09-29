#!/usr/bin/env python3
"""Read the authenticated order list through the frontend Nginx proxy.

Requires Keycloak to be provisioned with scripts/bootstrap-keycloak.ps1 and
KEYCLOAK_CLIENT_SECRET in the environment or the project .env file.
"""

import json
import os
import urllib.error
import urllib.parse
import urllib.request


def env_value(name, default):
    value = os.getenv(name)
    if value:
        return value
    try:
        with open(".env", "r", encoding="utf-8") as env_file:
            for line in env_file:
                if line.startswith(f"{name}="):
                    return line.split("=", 1)[1].strip().strip('"').strip("'")
    except OSError:
        pass
    return default


keycloak_url = env_value("KEYCLOAK_URL", "http://127.0.0.1:8181").rstrip("/")
frontend_url = env_value("FRONTEND_URL", "http://127.0.0.1:5173").rstrip("/")
client_secret = env_value("KEYCLOAK_CLIENT_SECRET", "")
if not client_secret:
    raise SystemExit("KEYCLOAK_CLIENT_SECRET is missing; run scripts/bootstrap-keycloak.ps1 first.")

token_data = urllib.parse.urlencode({
    "client_id": "microservices_client",
    "client_secret": client_secret,
    "grant_type": "password",
    "username": "admin_user",
    "password": "admin",
}).encode("utf-8")
token_url = f"{keycloak_url}/realms/microservices-realm/protocol/openid-connect/token"
token_request = urllib.request.Request(
    token_url,
    data=token_data,
    headers={"Content-Type": "application/x-www-form-urlencoded"},
    method="POST",
)

try:
    with urllib.request.urlopen(token_request, timeout=8) as response:
        token = json.loads(response.read().decode("utf-8"))["access_token"]
except (urllib.error.URLError, urllib.error.HTTPError, KeyError, json.JSONDecodeError) as error:
    raise SystemExit(f"Keycloak token acquisition failed: {error}") from error

orders_url = f"{frontend_url}/api/order"
orders_request = urllib.request.Request(
    orders_url,
    headers={"Authorization": f"Bearer {token}"},
)
try:
    with urllib.request.urlopen(orders_request, timeout=8) as response:
        payload = json.loads(response.read().decode("utf-8"))
        count = len(payload) if isinstance(payload, list) else "response received"
        print(f"Authenticated order-list request succeeded: HTTP {response.status}; {count} orders; via {orders_url}")
except urllib.error.HTTPError as error:
    print(f"Orders API returned HTTP {error.code}: {error.read().decode('utf-8', errors='replace')}")
    raise SystemExit(1) from error
except urllib.error.URLError as error:
    raise SystemExit(f"Orders API connection failed at {orders_url}: {error}") from error
