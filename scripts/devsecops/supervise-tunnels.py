import subprocess
import time
import sys

# Port-forward tunnels for local Minikube DevSecOps platform:
# - Microservices and Presentation Frontend run in 'dev' namespace
# - Authentication / IAM runs in 'auth' namespace
# - Platform tools run in 'argocd', 'observability', 'vault', and 'istio-system'
tunnels = [
    {"name": "Frontend", "ns": "dev", "svc": "frontend", "local": 4200, "remote": 80},
    {"name": "API-Gateway", "ns": "dev", "svc": "api-gateway", "local": 8080, "remote": 8080},
    {"name": "Keycloak", "ns": "auth", "svc": "keycloak", "local": 8181, "remote": 8181},
    {"name": "ArgoCD", "ns": "argocd", "svc": "argocd-server", "local": 8088, "remote": 80},
    {"name": "Grafana", "ns": "observability", "svc": "kube-prometheus-grafana", "local": 3000, "remote": 80},
    {"name": "Prometheus", "ns": "observability", "svc": "kube-prometheus-kube-prome-prometheus", "local": 9090, "remote": 9090},
    {"name": "Vault", "ns": "vault", "svc": "vault", "local": 8200, "remote": 8200},
    {"name": "Kiali", "ns": "istio-system", "svc": "kiali", "local": 20001, "remote": 20001},
]

processes = {}

def start_tunnel(t):
    cmd = [
        "kubectl", "port-forward",
        "-n", t["ns"],
        "--address", "0.0.0.0,127.0.0.1",
        f"svc/{t['svc']}",
        f"{t['local']}:{t['remote']}"
    ]
    return subprocess.Popen(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

# Start all tunnels
for t in tunnels:
    processes[t["name"]] = (t, start_tunnel(t))
    print(f"[+] Tunnel started: {t['name']} ({t['ns']}) on localhost:{t['local']}")

while True:
    time.sleep(5)
    for name, (t, proc) in list(processes.items()):
        if proc.poll() is not None:
            # Process terminated, respawn with pause
            time.sleep(2)
            processes[name] = (t, start_tunnel(t))
