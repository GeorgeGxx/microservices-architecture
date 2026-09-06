import subprocess
import datetime
import time

print("Generating bcrypt hash from argocd-server...")
hash_out = subprocess.check_output(
    ["kubectl", "exec", "-n", "argocd", "deploy/argocd-server", "--", "argocd", "account", "bcrypt", "--password", "admin"]
).decode().strip()
print(f"Generated hash: {hash_out}")

mtime = datetime.datetime.utcnow().strftime("%Y-%m-%dT%H:%M:%SZ")
patch = f'{{"stringData":{{"admin.password":"{hash_out}","admin.passwordMtime":"{mtime}"}}}}'

print("Patching argocd-secret...")
subprocess.check_call(["kubectl", "patch", "secret", "-n", "argocd", "argocd-secret", "--type", "merge", "-p", patch])

# Also ensure argocd-initial-admin-secret is deleted so it doesn't conflict
subprocess.call(["kubectl", "delete", "secret", "argocd-initial-admin-secret", "-n", "argocd", "--ignore-not-found"])

print("Restarting argocd-server deployment...")
subprocess.check_call(["kubectl", "rollout", "restart", "deployment", "argocd-server", "-n", "argocd"])
subprocess.check_call(["kubectl", "rollout", "status", "deployment", "argocd-server", "-n", "argocd", "--timeout=90s"])
print("ArgoCD admin password successfully updated to 'admin'!")
