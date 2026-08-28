{{- define "rallyroo.name" -}}rallyroo{{- end }}
{{- define "rallyroo.labels" -}}
app.kubernetes.io/name: {{ include "rallyroo.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- define "rallyroo.selectorLabels" -}}
app.kubernetes.io/name: {{ include "rallyroo.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}
{{- define "rallyroo.apiImageTag" -}}
{{- default .Chart.AppVersion .Values.api.image.tag -}}
{{- end }}
