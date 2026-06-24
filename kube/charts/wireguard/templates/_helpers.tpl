{{- define "wireguard.labels" -}}
app.kubernetes.io/name: wireguard
app.kubernetes.io/instance: {{ .Values.name | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/part-of: garuda
garuda.managed-by: helm
{{- end -}}

{{- define "wireguard.selector" -}}
app.kubernetes.io/name: wireguard
app.kubernetes.io/instance: {{ .Values.name | quote }}
{{- end -}}



