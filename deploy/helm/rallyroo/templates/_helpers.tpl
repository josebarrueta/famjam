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
{{- define "rallyroo.postgresConnectionEnv" -}}
- name: PGHOST
  value: {{ .Release.Name }}-postgres
- name: PGPORT
  value: "5432"
- name: PGDATABASE
  value: {{ .Values.postgres.database | quote }}
- name: PGUSER
  value: {{ .Values.postgres.user | quote }}
- name: POSTGRES_PASSWORD_FILE
  value: /run/secrets/postgres/password
{{- end }}
{{- define "rallyroo.postgresPasswordVolumeMount" -}}
- name: postgres-credentials
  mountPath: /run/secrets/postgres
  readOnly: true
{{- end }}
{{- define "rallyroo.postgresPasswordVolume" -}}
- name: postgres-credentials
  secret:
    secretName: {{ required "postgres.credentialsSecret is required" .Values.postgres.credentialsSecret }}
    defaultMode: 288
    items:
      - key: POSTGRES_PASSWORD
        path: password
{{- end }}
