import subprocess
import base64
from datetime import datetime, timezone

new_hash = "$2a$10$79rylVW9piAE6j7aBRJSfeqqIwLT43LfsNbC19aoaDGVOoCnGiVY."
b64_hash = base64.b64encode(new_hash.encode()).decode()
now = datetime.now(timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ')
b64_now = base64.b64encode(now.encode()).decode()

patch = f'{{"data":{{"admin.password":"{b64_hash}","admin.passwordMtime":"{b64_now}"}}}}'

subprocess.run(['kubectl', 'patch', 'secret', '-n', 'argocd', 'argocd-secret', '--type', 'merge', '-p', patch], check=True)
subprocess.run(['kubectl', 'rollout', 'restart', 'deploy/argocd-server', '-n', 'argocd'], check=True)
print("ArgoCD admin password set to 'admin' and server restarted!")
