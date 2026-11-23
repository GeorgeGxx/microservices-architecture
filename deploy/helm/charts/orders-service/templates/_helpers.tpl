{{- define "orders-service.fullname" -}}
orders-service
{{- end -}}

{{- define "orders-service.labels" -}}
app: orders-service
app.kubernetes.io/name: orders-service
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end -}}
