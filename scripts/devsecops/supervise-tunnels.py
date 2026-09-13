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
    {"name": "Tempo", "ns": "observability", "svc": "tempo", "local": 3200, "remote": 3200},
    {"name": "Loki", "ns": "observability", "svc": "loki", "local": 3100, "remote": 3100},
    {"name": "Kiali", "ns": "istio-system", "svc": "kiali", "local": 20001, "remote": 20001},
]

def check_service_exists(ns, svc):
    try:
        res = subprocess.run(["kubectl", "get", "svc", "-n", ns, svc], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        return res.returncode == 0
    except Exception:
        return False

def start_tunnel(t):
    if not check_service_exists(t["ns"], t["svc"]):
        return None
    cmd = [
        "kubectl", "port-forward",
        "-n", t["ns"],
        "--address", "0.0.0.0,127.0.0.1",
        f"svc/{t['svc']}",
        f"{t['local']}:{t['remote']}"
    ]
    return subprocess.Popen(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

# Start all tunnels
processes = {}
for t in tunnels:
    proc = start_tunnel(t)
    processes[t["name"]] = (t, proc)
    if proc:
        print(f"[+] Tunnel started: {t['name']} ({t['ns']}) on localhost:{t['local']}")
    else:
        print(f"[~] Service {t['svc']} not yet ready in '{t['ns']}'. Will auto-connect once active.")

while True:
    time.sleep(5)
    for name, (t, proc) in list(processes.items()):
        if proc is None or proc.poll() is not None:
            new_proc = start_tunnel(t)
            if new_proc:
                print(f"[+] Tunnel connected: {t['name']} ({t['ns']}) on localhost:{t['local']}")
            processes[name] = (t, new_proc)
