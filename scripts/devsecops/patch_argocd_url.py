import subprocess

patch = '{"data":{"url":"https://localhost:8088"}}'
subprocess.run(['kubectl', 'patch', 'cm', '-n', 'argocd', 'argocd-cm', '--type', 'merge', '-p', patch], check=True)
print("Updated argocd-cm url to https://localhost:8088 successfully!")
