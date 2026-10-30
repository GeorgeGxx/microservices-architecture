{{- define "payments-service.fullname" -}}
payments-service
{{- end -}}

{{- define "payments-service.labels" -}}
app: payments-service
app.kubernetes.io/name: payments-service
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end -}}
