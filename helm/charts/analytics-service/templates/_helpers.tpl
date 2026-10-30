{{- define "analytics-service.fullname" -}}
analytics-service
{{- end -}}

{{- define "analytics-service.labels" -}}
app: analytics-service
app.kubernetes.io/name: analytics-service
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end -}}
