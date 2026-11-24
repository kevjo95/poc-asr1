{{- define "ingest-ms.name" -}}ingest-ms{{- end -}}
{{- define "ingest-ms.labels" -}}
app.kubernetes.io/name: {{ include "ingest-ms.name" . }}
app.kubernetes.io/part-of: poc-asr1
{{- end -}}
