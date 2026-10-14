{{- /*
  Returns a value, or fails the render if it is empty or still contains a <PLACEHOLDER>.
  Stops a half-filled values file from syncing and failing later on the cluster.
  Usage: include "vault-platform.filled" (list "platform.route.host" .Values.platform.route.host)
*/ -}}
{{- define "vault-platform.filled" -}}
{{- $key := index . 0 -}}
{{- $value := toString (index . 1) -}}
{{- if or (empty (index . 1)) (contains "<" $value) -}}
{{- fail (printf "%s is not set (value: %q). See the open items in docs/installation.md." $key $value) -}}
{{- end -}}
{{- $value -}}
{{- end -}}
