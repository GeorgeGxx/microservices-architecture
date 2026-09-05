import subprocess
import time
import sys

cmd = ["kubectl", "port-forward", "-n", "argocd", "--address", "0.0.0.0,127.0.0.1", "svc/argocd-server", "30088:80"]

while True:
    try:
        proc = subprocess.Popen(cmd)
        proc.wait()
    except Exception as e:
        print("Port-forward error:", e, file=sys.stderr)
    time.sleep(1)
