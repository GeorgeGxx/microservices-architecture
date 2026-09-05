import subprocess

patch = '{"data":{"url":"http://localhost:30088"}}'
subprocess.run(['kubectl', 'patch', 'cm', '-n', 'argocd', 'argocd-cm', '--type', 'merge', '-p', patch], check=True)
print("Updated argocd-cm url to http://localhost:30088 successfully!")
