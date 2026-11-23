import os

os.environ.setdefault("DJANGO_SETTINGS_MODULE", "glitchtip.settings")

import django

django.setup()

from django.contrib.auth import get_user_model
from django.contrib.auth.password_validation import validate_password

email = os.environ["GLITCHTIP_ADMIN_EMAIL"]
password = os.environ["GLITCHTIP_ADMIN_PASSWORD"]
user_model = get_user_model()
user, created = user_model.objects.get_or_create(email=email)
validate_password(password, user=user)
user.is_active = True
user.is_staff = True
user.is_superuser = True
user.set_password(password)
user.save()
print(f"Development admin {'created' if created else 'updated'}: {email}")
