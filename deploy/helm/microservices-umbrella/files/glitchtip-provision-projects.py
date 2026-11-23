import base64
import json
import os
import ssl
import time
import urllib.error
import urllib.request
from urllib.parse import urlsplit

os.environ.setdefault("DJANGO_SETTINGS_MODULE", "glitchtip.settings")

import django

django.setup()

from django.db import OperationalError, connections
from django.contrib.auth import get_user_model
from django.contrib.auth.password_validation import validate_password
from apps.organizations_ext.models import Organization
from apps.projects.models import Project
from apps.teams.models import Team

EMAIL = os.environ["GLITCHTIP_ADMIN_EMAIL"]
PASSWORD = os.environ["GLITCHTIP_ADMIN_PASSWORD"]
BASE_URL = os.environ.get("GLITCHTIP_DOMAIN", "http://localhost:8090").rstrip("/")
SERVICES = {
    "GLITCHTIP_DEMAND_FORECAST_DSN": ("demand-forecast-service-fastapi", "demand-forecast-service (FastAPI)", "python"),
    "GLITCHTIP_INVENTORY_DSN": ("inventory-service-spring-boot", "inventory-service (Spring Boot)", "java"),
    "GLITCHTIP_NOTIFICATION_DSN": ("notification-service-spring-boot", "notification-service (Spring Boot)", "java"),
    "GLITCHTIP_ORDERS_DSN": ("orders-service-spring-boot", "orders-service (Spring Boot)", "java"),
    "GLITCHTIP_PAYMENTS_DSN": ("payments-service-gin", "payments-service (Gin)", "go"),
    "GLITCHTIP_FULFILLMENT_DSN": ("fulfillment-service-nestjs", "fulfillment-service (NestJS)", "node"),
    "GLITCHTIP_ANALYTICS_DSN": ("analytics-service-fastapi", "analytics-service (FastAPI)", "python"),
    "GLITCHTIP_PRODUCTS_DSN": ("products-service-spring-boot", "products-service (Spring Boot)", "java"),
    "GLITCHTIP_AI_DSN": ("ai-service-fastapi", "ai-service (FastAPI)", "python"),
    "GLITCHTIP_FRONTEND_DSN": ("frontend-react", "frontend (React)", "javascript-react"),
}

# A mesh sidecar may need a short interval to establish its upstream mTLS
# connection after the container starts. Confirm PostgreSQL before touching
# Django models and retry transient resets with a bounded exponential backoff.
for attempt in range(8):
    try:
        connections["default"].ensure_connection()
        break
    except OperationalError as error:
        if attempt == 7:
            raise RuntimeError(
                "GlitchTip PostgreSQL did not become reachable after bounded retries"
            ) from error
        time.sleep(min(2**attempt, 8))

user_model = get_user_model()
user, created = user_model.objects.get_or_create(email=EMAIL)
validate_password(PASSWORD, user=user)
user.is_active = True
user.is_staff = True
user.is_superuser = True
if created or not user.check_password(PASSWORD):
    user.set_password(PASSWORD)  # nosemgrep: python.django.security.audit.unvalidated-password.unvalidated-password
user.save()
organization, _ = Organization.objects.get_or_create(
    slug="microservices-development", defaults={"name": "Microservices Development"}
)
if not organization.users.filter(pk=user.pk).exists():
    organization.add_user(user)
team, _ = Team.objects.get_or_create(organization=organization, slug="engineering")
team.members.add(organization.organization_users.get(user=user))

parsed = urlsplit(BASE_URL)
public_base = f"{parsed.scheme}://{parsed.netloc}{parsed.path}"
dsns = {}
for env_name, (project_slug, project_name, platform) in SERVICES.items():
    project = Project.objects.filter(organization=organization, slug=project_slug).first()
    if project is None:
        # Preserve event history from older service-only slugs while migrating to
        # the framework-qualified slugs already used by the Minikube projects.
        project = Project.objects.filter(organization=organization, name=project_name).first()
        if project is not None:
            project.slug = project_slug
            project.save(update_fields=["slug"])
        else:
            project = Project.objects.create(
                organization=organization,
                slug=project_slug,
                name=project_name,
                platform=platform,
            )

    if project.name != project_name or project.platform != platform:
        project.name = project_name
        project.platform = platform
        project.save(update_fields=["name", "platform"])
    team.projects.add(project)
    key = project.projectkey_set.filter(is_active=True).first()
    if key is None:
        raise RuntimeError(f"No active GlitchTip project key for {project_name}")
    if env_name == "GLITCHTIP_FRONTEND_DSN":
        dsns[env_name] = f"{public_base}/{key.public_key_hex}/{project.id}"
    else:
        dsns[env_name] = f"http://{key.public_key_hex}@glitchtip:8000/{project.id}"

def write_dsns_to_kubernetes_secret(values):
    """Store project DSNs in the namespace Secret without exposing them in logs."""
    secret_dir = "/var/run/secrets/kubernetes.io/serviceaccount"
    with open(os.path.join(secret_dir, "token"), encoding="utf-8") as token_file:
        token = token_file.read().strip()
    with open(os.path.join(secret_dir, "namespace"), encoding="utf-8") as namespace_file:
        namespace = namespace_file.read().strip()

    ca_path = os.path.join(secret_dir, "ca.crt")
    context = ssl.create_default_context(cafile=ca_path if os.path.exists(ca_path) else None)
    api_host = os.environ["KUBERNETES_SERVICE_HOST"]
    api_port = os.environ.get("KUBERNETES_SERVICE_PORT_HTTPS", "443")
    base_url = f"https://{api_host}:{api_port}/api/v1/namespaces/{namespace}/secrets"
    headers = {
        "Authorization": f"Bearer {token}",
        "Content-Type": "application/json",
    }
    secret = {
        "apiVersion": "v1",
        "kind": "Secret",
        "metadata": {"name": "glitchtip-project-dsns"},
        "type": "Opaque",
        "data": {
            name: base64.b64encode(value.encode("utf-8")).decode("ascii")
            for name, value in values.items()
        },
    }
    secret_url = f"{base_url}/glitchtip-project-dsns"

    def request(url, method, body=None):
        data = json.dumps(body).encode("utf-8") if body is not None else None
        for attempt in range(5):
            req = urllib.request.Request(url, data=data, headers=headers, method=method)
            try:
                return urllib.request.urlopen(req, context=context, timeout=10)
            except urllib.error.HTTPError:
                raise
            except (urllib.error.URLError, OSError, TimeoutError):
                if attempt == 4:
                    raise
                time.sleep(2**attempt)

    try:
        with request(secret_url, "GET") as response:
            secret["metadata"]["resourceVersion"] = json.load(response)["metadata"]["resourceVersion"]
    except (urllib.error.URLError, urllib.error.HTTPError, OSError, TimeoutError) as error:
        raise RuntimeError("Could not read the pre-created GlitchTip DSN Secret in Kubernetes") from error

    try:
        with request(secret_url, "PUT", secret):
            pass
    except (urllib.error.URLError, urllib.error.HTTPError, OSError, TimeoutError) as error:
        raise RuntimeError("Could not update the GlitchTip DSN Secret in Kubernetes") from error


output_file = os.environ.get("GLITCHTIP_DSN_OUTPUT_FILE")
if output_file:
    descriptor = os.open(output_file, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(descriptor, "w", encoding="utf-8") as output:
        json.dump(dsns, output, sort_keys=True)
    if os.environ.get("GLITCHTIP_WAIT_FOR_DSN_ACK", "false").lower() in {"1", "true", "yes"}:
        deadline = time.monotonic() + 300
        while not os.path.exists(os.path.join(os.path.dirname(output_file), "ack")):
            if time.monotonic() >= deadline:
                raise RuntimeError("Timed out waiting for the orchestrator to store generated GlitchTip DSNs")
            time.sleep(1)

if os.environ.get("GLITCHTIP_WRITE_K8S_SECRET", "false").lower() in {"1", "true", "yes"}:
    write_dsns_to_kubernetes_secret(dsns)
    print(f"Provisioned {len(dsns)} GlitchTip projects and stored DSNs in Kubernetes Secret glitchtip-project-dsns.")
elif os.environ.get("GLITCHTIP_PRINT_DSNS", "true").lower() not in {"0", "false", "no"}:
    print("GLITCHTIP_DSNS_JSON=" + json.dumps(dsns, sort_keys=True))
else:
    print(f"Provisioned {len(dsns)} GlitchTip projects and wrote DSNs to the restricted output volume.")
