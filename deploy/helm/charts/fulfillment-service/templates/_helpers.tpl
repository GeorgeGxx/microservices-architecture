{{- define "fulfillment-service.fullname" -}}
fulfillment-service
{{- end -}}

{{- define "fulfillment-service.labels" -}}
app: fulfillment-service
app.kubernetes.io/name: fulfillment-service
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end -}}
