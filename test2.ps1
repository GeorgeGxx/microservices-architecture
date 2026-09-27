$app = kubectl get application microservices-dev -n argocd -o json | ConvertFrom-Json

'--- Condiciones ---'
$app.status.conditions | Format-List *

'--- Estado de sync ---'
$app.status.sync | Format-List *

'--- Recursos gestionados ---'
$app.status.resources |
  Select-Object kind, namespace, name, status,
    @{Name='Health';Expression={$_.health.status}},
    @{Name='Message';Expression={$_.health.message}} |
  Format-Table -Wrap