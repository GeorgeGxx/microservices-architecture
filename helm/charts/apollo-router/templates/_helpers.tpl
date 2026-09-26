{{- define "apollo-router.fullname" -}}
apollo-router
{{- end -}}

{{- define "apollo-router.labels" -}}
app: apollo-router
app.kubernetes.io/name: apollo-router
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end -}}
