{{- define "famjam.name" -}}famjam{{- end }}
{{- define "famjam.labels" -}}
app.kubernetes.io/name: {{ include "famjam.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version }}
{{- end }}
{{- define "famjam.selectorLabels" -}}
app.kubernetes.io/name: {{ include "famjam.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}
