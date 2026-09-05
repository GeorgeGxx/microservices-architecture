import os
import subprocess
import time

SERVICES = [
    ("georgegxx/api-gateway:1.0.0", "localhost:30002/microservices/msa-api-gateway:1.0.0"),
    ("georgegxx/orders-service:1.0.0", "localhost:30002/microservices/msa-orders-service:1.0.0"),
    ("georgegxx/notification-service:1.0.0", "localhost:30002/microservices/msa-notification-service:1.0.0"),
    ("georgegxx/inventory-service:1.0.0", "localhost:30002/microservices/msa-inventory-service:1.0.0"),
    ("georgegxx/frontend:1.0.0", "localhost:30002/microservices/msa-frontend:1.0.0"),
]

docker_dir = r"C:\Users\jorge\.gemini\antigravity-ide\brain\f47dbc44-2e94-40b1-a1f2-09baf5e382a8\scratch\docker"
env = os.environ.copy()
env["DOCKER_CONFIG"] = docker_dir

for src, dst in SERVICES:
    print(f"Tagging {src} -> {dst}")
    subprocess.run(["docker", "tag", src, dst], check=True)
    print(f"Pushing {dst}...")
    res = subprocess.run(["docker", "push", dst], env=env)
    if res.returncode != 0:
        print(f"Failed to push {dst}")
    else:
        print(f"Successfully pushed {dst}")

print("All images processed!")
