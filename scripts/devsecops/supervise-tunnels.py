import subprocess
import time
import sys

tunnels = [
    {"name": "Keycloak", "ns": "staging", "svc": "keycloak", "local": 8181, "remote": 8181},
    {"name": "API-Gateway", "ns": "staging", "svc": "api-gateway", "local": 8080, "remote": 8080},
    {"name": "Frontend", "ns": "staging", "svc": "frontend", "local": 4200, "remote": 80},
    {"name": "ArgoCD", "ns": "argocd", "svc": "argocd-server", "local": 30088, "remote": 80},
    {"name": "Grafana", "ns": "observability", "svc": "kube-prometheus-grafana", "local": 30030, "remote": 80},
    {"name": "Prometheus", "ns": "observability", "svc": "kube-prometheus-kube-prome-prometheus", "local": 9090, "remote": 9090},
    {"name": "Vault", "ns": "vault", "svc": "vault", "local": 8200, "remote": 8200},
    {"name": "Kiali", "ns": "istio-system", "svc": "kiali", "local": 20001, "remote": 20001},
    {"name": "Istio-Gateway", "ns": "istio-system", "svc": "istio-ingressgateway", "local": 30080, "remote": 80},
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
    print(f"[+] Tunnel started: {t['name']} on localhost:{t['local']}")

while True:
    time.sleep(2)
    for name, (t, proc) in list(processes.items()):
        if proc.poll() is not None:
            # Process terminated, respawn
            print(f"[!] Tunnel {name} disconnected, respawning...", file=sys.stderr)
            processes[name] = (t, start_tunnel(t))
