{{/* Restricted-v2 SCC compatible container security context. */}}
{{- define "lab-prereqs.securityContext" -}}
securityContext:
  allowPrivilegeEscalation: false
  runAsNonRoot: true
  capabilities:
    drop: ["ALL"]
  seccompProfile:
    type: RuntimeDefault
{{- end }}
