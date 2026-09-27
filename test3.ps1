$app = kubectl get application microservices-dev -n argocd -o json | ConvertFrom-Json
$app.status.health | ConvertTo-Json -Depth 10
$app.status.resources |
  ForEach-Object {
    [pscustomobject]@{
      Kind    = $_.kind
      Name    = $_.name
      Sync    = $_.status
      Health  = $_.health.status
      Message = $_.health.message
    }
  } | Format-Table -Wrap

kubectl get deployments,pods -n dev
kubectl get events -n dev --sort-by=.metadata.creationTimestamp |
  Select-Object -Last 20