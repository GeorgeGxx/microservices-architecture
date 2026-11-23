{{- define "inventory-service.fullname" -}}
inventory-service
{{- end -}}

{{- define "inventory-service.labels" -}}
app: inventory-service
app.kubernetes.io/name: inventory-service
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end -}}
