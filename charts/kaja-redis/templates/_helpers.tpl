{{/*
Release-scoped names. The console names the Helm release after the PluginInstance
(HelmProvisioner.Provision uses instance.Name), so the release name IS the service name the
user sees — keep the object names equal to it rather than appending a chart suffix. The
connection secret's HOST is built from this in domain/plugins/catalog.go, and the two must
agree; a mismatch is exactly the dangling-HOST bug the Bitnami recipe shipped with.
*/}}
{{- define "kaja-redis.fullname" -}}
{{- .Release.Name | trunc 52 | trimSuffix "-" -}}
{{- end -}}

{{- define "kaja-redis.headlessName" -}}
{{- printf "%s-headless" (include "kaja-redis.fullname" .) | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "kaja-redis.labels" -}}
app.kubernetes.io/name: kaja-redis
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" }}
kaja.dev/managed: "true"
{{- range $k, $v := .Values.extraLabels }}
{{ $k }}: {{ $v | quote }}
{{- end }}
{{- end -}}

{{- define "kaja-redis.selectorLabels" -}}
app.kubernetes.io/name: kaja-redis
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}

{{/*
Fail fast when the platform did not point the chart at a credentials secret. Running an
unauthenticated cache reachable by every pod in the namespace is worse than not installing.
*/}}
{{- define "kaja-redis.authSecret" -}}
{{- if not .Values.auth.existingSecret -}}
{{- fail "auth.existingSecret is required: kaja-redis does not generate credentials (the platform writes redis-auth-<instance> before provisioning)" -}}
{{- end -}}
{{- .Values.auth.existingSecret -}}
{{- end -}}
