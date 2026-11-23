{{- define "ai-service.fullname" -}}
ai-service
{{- end -}}

{{- define "ai-service.labels" -}}
app: ai-service
app.kubernetes.io/name: ai-service
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end -}}
