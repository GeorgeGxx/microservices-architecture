import subprocess

patch = '{"data":{"server.insecure":"true"}}'
subprocess.run(['kubectl', 'patch', 'cm', '-n', 'argocd', 'argocd-cmd-params-cm', '--type', 'merge', '-p', patch], check=True)
subprocess.run(['kubectl', 'rollout', 'restart', 'deploy/argocd-server', '-n', 'argocd'], check=True)
print("ArgoCD patched with server.insecure: true and restarted successfully!")
