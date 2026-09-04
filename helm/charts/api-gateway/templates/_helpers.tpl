{{- define "api-gateway.fullname" -}}
api-gateway
{{- end -}}

{{- define "api-gateway.labels" -}}
app: api-gateway
app.kubernetes.io/name: api-gateway
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end -}}
