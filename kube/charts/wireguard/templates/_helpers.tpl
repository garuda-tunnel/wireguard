{{- define "wireguard.labels" -}}
app.kubernetes.io/name: wireguard
app.kubernetes.io/instance: {{ .Values.name | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
garuda.managed-by: helm
{{- end -}}

{{- define "wireguard.selector" -}}
app.kubernetes.io/name: wireguard
app.kubernetes.io/instance: {{ .Values.name | quote }}
{{- end -}}

{{/* Comma-separated Multus annotation: name@iface, name@iface. */}}
{{- define "wireguard.networks" -}}
{{- $items := list -}}
{{- range .Values.nic_attach -}}
{{- $items = append $items (printf "%s@%s" . .) -}}
{{- end -}}
{{- join "," $items -}}
{{- end -}}


