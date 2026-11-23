{{- define "products-service.fullname" -}}
products-service
{{- end -}}

{{- define "products-service.labels" -}}
app: products-service
app.kubernetes.io/name: products-service
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end -}}
