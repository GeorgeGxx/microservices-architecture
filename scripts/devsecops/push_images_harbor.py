import os
import subprocess
import shutil

SERVICES = [
    ("georgegxx/products-service:1.0.0", "localhost:30002/microservices/msa-products-service:1.0.0"),
    ("georgegxx/api-gateway:1.0.0", "localhost:30002/microservices/msa-api-gateway:1.0.0"),
    ("georgegxx/orders-service:1.0.0", "localhost:30002/microservices/msa-orders-service:1.0.0"),
    ("georgegxx/notification-service:1.0.0", "localhost:30002/microservices/msa-notification-service:1.0.0"),
    ("georgegxx/inventory-service:1.0.0", "localhost:30002/microservices/msa-inventory-service:1.0.0"),
    ("georgegxx/frontend:1.0.0", "localhost:30002/microservices/msa-frontend:1.0.0"),
]

scratch_dir = r"C:\Users\jorge\.gemini\antigravity-ide\brain\f47dbc44-2e94-40b1-a1f2-09baf5e382a8\scratch"
docker_dir = os.path.join(scratch_dir, "docker")
crane_bin = os.path.expanduser(r"~\go\bin\crane.exe")

env = os.environ.copy()
env["DOCKER_CONFIG"] = docker_dir

for src, dst in SERVICES:
    print(f"\n==========================================")
    print(f"Processing {src} -> {dst}")
    tar_file = os.path.join(scratch_dir, "tmp_image.tar")
    if os.path.exists(tar_file):
        os.remove(tar_file)
        
    print(f"Saving {src} to tar...")
    res = subprocess.run(["docker", "save", src, "-o", tar_file], capture_output=True, text=True)
    if res.returncode != 0:
        print(f"Error saving {src}: {res.stderr}")
        continue
        
    print(f"Pushing {tar_file} with crane to {dst}...")
    res = subprocess.run([crane_bin, "push", tar_file, dst, "--insecure"], env=env, capture_output=True, text=True)
    print(f"Stdout: {res.stdout}")
    print(f"Stderr: {res.stderr}")
    print(f"Return code: {res.returncode}")
    
    if os.path.exists(tar_file):
        os.remove(tar_file)

print("\nFinished pushing all images to Harbor!")
