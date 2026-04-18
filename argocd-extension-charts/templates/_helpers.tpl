{{/*
Expand the name of the chart.
*/}}
{{- define "cve-scanner.name" -}}
{{- .Chart.Name }}
{{- end }}

{{/*
Backend service FQDN — used in the ArgoCD extension.config proxy URL.
*/}}
{{- define "cve-scanner.backendURL" -}}
http://cve-backend.{{ .Values.backend.namespace }}.svc.cluster.local:8091
{{- end }}

{{/*
Common labels applied to all resources.
*/}}
{{- define "cve-scanner.labels" -}}
helm.sh/chart: {{ .Chart.Name }}-{{ .Chart.Version }}
app.kubernetes.io/name: {{ include "cve-scanner.name" . }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}
