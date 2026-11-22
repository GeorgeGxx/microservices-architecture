import os
from pathlib import Path
import subprocess
import time
import sys

# Port-forward tunnels for local Minikube DevSecOps platform:
# - Microservices and Presentation Frontend run in 'dev' namespace
# - Authentication / IAM runs in 'auth' namespace
# - Platform tools run in 'argocd', 'observability', 'vault', and 'istio-system'
tunnels = [
    {"name": "Frontend", "ns": "dev", "svc": "frontend", "local": 5173, "remote": 80},
    {"name": "Cosmo-Router", "ns": "dev", "svc": "cosmo-router", "local": 8080, "remote": 8080},
    {"name": "Inventory-Service", "ns": "dev", "svc": "inventory-service", "local": 8001, "remote": 8001},
    {"name": "Notification-Service", "ns": "dev", "svc": "notification-service", "local": 8002, "remote": 8002},
    {"name": "Orders-Service", "ns": "dev", "svc": "orders-service", "local": 8003, "remote": 8003},
    {"name": "Products-Service", "ns": "dev", "svc": "products-service", "local": 8004, "remote": 8004},
    {"name": "Payments-Service", "ns": "dev", "svc": "payments-service", "local": 8085, "remote": 8085},
    {"name": "Fulfillment-Service", "ns": "dev", "svc": "fulfillment-service", "local": 8086, "remote": 8086},
    {"name": "Analytics-Service", "ns": "dev", "svc": "analytics-service", "local": 8087, "remote": 8087},
    {"name": "Keycloak", "ns": "auth", "svc": "keycloak", "local": 8181, "remote": 8181},
    {"name": "MLflow", "ns": "dev", "svc": "mlflow", "local": 5000, "remote": 5000},
    {"name": "Demand-Forecast", "ns": "dev", "svc": "demand-forecast-service", "local": 8005, "remote": 8005},
    {"name": "AI-Service", "ns": "dev", "svc": "ai-service", "local": 8010, "remote": 8010},
    {"name": "GlitchTip", "ns": "dev", "svc": "glitchtip", "local": 8091, "remote": 8000},
    {"name": "ArgoCD", "ns": "argocd", "svc": "argocd-server", "local": 8088, "remote": 80},
    {"name": "Backstage-IDP", "ns": "dev", "svc": "backstage-idp", "local": 7007, "remote": 7007},
    {"name": "Grafana", "ns": "observability", "svc": "kube-prometheus-grafana", "local": 3000, "remote": 80},
    {"name": "Prometheus", "ns": "observability", "svc": "kube-prometheus-kube-prome-prometheus", "local": 9090, "remote": 9090},
    {"name": "OpenCost UI", "ns": "opencost", "svc": "opencost", "local": 7000, "remote": 9090},
    {"name": "Vault", "ns": "vault", "svc": "vault", "local": 8200, "remote": 8200},
    {"name": "Tempo", "ns": "observability", "svc": "tempo", "local": 3200, "remote": 3200},
    {"name": "Loki", "ns": "observability", "svc": "loki", "local": 3100, "remote": 3100},
    {"name": "Alloy", "ns": "observability", "svc": "alloy", "local": 3300, "remote": 3300},
    {"name": "Phoenix", "ns": "observability", "svc": "phoenix", "local": 6006, "remote": 6006},
    {"name": "Ollama", "ns": "observability", "svc": "ollama", "local": 11434, "remote": 11434},
    {"name": "Kiali", "ns": "istio-system", "svc": "kiali", "local": 20001, "remote": 20001},
]

def check_service_exists(ns, svc):
    try:
        res = subprocess.run(["kubectl", "get", "svc", "-n", ns, svc], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        return res.returncode == 0
    except Exception:
        return False

def get_log_path(t):
    if os.getenv("LOCALAPPDATA"):
        root = Path(os.environ["LOCALAPPDATA"]) / "microservices-architecture" / "logs"
    else:
        root = Path.home() / ".local" / "state" / "microservices-architecture" / "logs"
    root.mkdir(parents=True, exist_ok=True)
    return root / f"port-forward-{t['name'].lower()}.log"

def start_tunnel(t):
    if not check_service_exists(t["ns"], t["svc"]):
        return None
    cmd = [
        "kubectl", "port-forward",
        "-n", t["ns"],
        "--address", "127.0.0.1",
        f"svc/{t['svc']}",
        f"{t['local']}:{t['remote']}"
    ]
    log_path = get_log_path(t)
    if log_path.exists() and log_path.stat().st_size > 1_048_576:
        log_path.write_text("Previous port-forward log truncated after reaching 1 MiB.\n", encoding="utf-8")
    log_handle = log_path.open("a", encoding="utf-8", errors="replace")
    log_handle.write(f"\n[{time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime())}] Starting: {' '.join(cmd)}\n")
    log_handle.flush()
    try:
        proc = subprocess.Popen(cmd, stdout=log_handle, stderr=subprocess.STDOUT)
    except Exception:
        log_handle.close()
        raise
    return proc, log_handle

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
        if proc is None or proc[0].poll() is not None:
            if proc is not None:
                proc[1].close()
            new_proc = start_tunnel(t)
            if new_proc:
                print(f"[+] Tunnel connected: {t['name']} ({t['ns']}) on localhost:{t['local']}")
            processes[name] = (t, new_proc)
