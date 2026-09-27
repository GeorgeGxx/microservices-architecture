$body = @{
  query = "{ products { sku name } }"
} | ConvertTo-Json

try {
  Invoke-RestMethod -Uri "http://127.0.0.1:8080/graphql" `
    -Method Post -ContentType "application/json" -Body $body
} catch {
  $_.ErrorDetails.Message
  $_.Exception.Message
}