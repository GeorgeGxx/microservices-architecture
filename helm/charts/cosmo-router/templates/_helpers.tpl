{{- define "cosmo-router.fullname" -}}
cosmo-router
{{- end -}}

{{- define "cosmo-router.labels" -}}
app: cosmo-router
app.kubernetes.io/name: cosmo-router
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end -}}
