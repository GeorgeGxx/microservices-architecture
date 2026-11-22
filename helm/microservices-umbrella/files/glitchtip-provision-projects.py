import json
import os
from urllib.parse import urlsplit

os.environ.setdefault("DJANGO_SETTINGS_MODULE", "glitchtip.settings")

import django

django.setup()

from django.contrib.auth import get_user_model
from django.contrib.auth.password_validation import validate_password
from apps.organizations_ext.models import Organization
from apps.projects.models import Project
from apps.teams.models import Team

EMAIL = os.environ["GLITCHTIP_ADMIN_EMAIL"]
PASSWORD = os.environ["GLITCHTIP_ADMIN_PASSWORD"]
BASE_URL = os.environ.get("GLITCHTIP_DOMAIN", "http://localhost:8090").rstrip("/")
SERVICES = {
    "GLITCHTIP_DEMAND_FORECAST_DSN": ("demand-forecast-service", "demand-forecast-service (FastAPI)", "python"),
    "GLITCHTIP_INVENTORY_DSN": ("inventory-service", "inventory-service (Spring Boot)", "java"),
    "GLITCHTIP_NOTIFICATION_DSN": ("notification-service", "notification-service (Spring Boot)", "java"),
    "GLITCHTIP_ORDERS_DSN": ("orders-service", "orders-service (Spring Boot)", "java"),
    "GLITCHTIP_PAYMENTS_DSN": ("payments-service", "payments-service (Gin)", "go"),
    "GLITCHTIP_FULFILLMENT_DSN": ("fulfillment-service", "fulfillment-service (NestJS)", "node"),
    "GLITCHTIP_ANALYTICS_DSN": ("analytics-service", "analytics-service (FastAPI)", "python"),
    "GLITCHTIP_PRODUCTS_DSN": ("products-service", "products-service (Spring Boot)", "java"),
    "GLITCHTIP_AI_DSN": ("ai-service", "ai-service (FastAPI)", "python"),
    "GLITCHTIP_FRONTEND_DSN": ("frontend", "frontend (React)", "javascript-react"),
}

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
    project, _ = Project.objects.update_or_create(
        organization=organization,
        slug=project_slug,
        defaults={"name": project_name, "platform": platform},
    )
    team.projects.add(project)
    key = project.projectkey_set.filter(is_active=True).first()
    if key is None:
        raise RuntimeError(f"No active GlitchTip project key for {project_name}")
    if env_name == "GLITCHTIP_FRONTEND_DSN":
        dsns[env_name] = f"{public_base}/{key.public_key_hex}/{project.id}"
    else:
        dsns[env_name] = f"http://{key.public_key_hex}@glitchtip:8000/{project.id}"

if os.environ.get("GLITCHTIP_PRINT_DSNS", "true").lower() not in {"0", "false", "no"}:
    print("GLITCHTIP_DSNS_JSON=" + json.dumps(dsns, sort_keys=True))
