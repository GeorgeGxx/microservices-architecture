{{- define "notification-service.fullname" -}}
notification-service
{{- end -}}

{{- define "notification-service.labels" -}}
app: notification-service
app.kubernetes.io/name: notification-service
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end -}}
