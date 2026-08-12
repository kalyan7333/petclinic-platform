{{/*
Fully qualified app name.

Always pin this with `fullnameOverride` in helm-values/{service}.yaml. The
release name is NOT reliable: ArgoCD names the release after the Application
({service}-dev), and every in-cluster reference — service DNS, the init
container health checks, CONFIG_SERVER_URL, the Ingress backend and the
NetworkPolicy selectors — expects the bare service name.
*/}}
{{- define "petclinic-service.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}

{{/*
Common labels (CLAUDE.md Kubernetes Conventions).
*/}}
{{- define "petclinic-service.labels" -}}
app.kubernetes.io/name: {{ include "petclinic-service.fullname" . }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/component: {{ .Values.component }}
app.kubernetes.io/part-of: petclinic
app.kubernetes.io/managed-by: Helm
{{- with .Values.extraLabels }}
{{ toYaml . }}
{{- end }}
{{- end }}

{{/*
Selector labels — immutable once applied, and matched by the PodDisruptionBudget,
the Service, and the NetworkPolicies in k8s/base/security/. Kept identical to the
selector in k8s/base/{service}/deployment.yaml.
*/}}
{{- define "petclinic-service.selectorLabels" -}}
app.kubernetes.io/name: {{ include "petclinic-service.fullname" . }}
{{- end }}

{{/*
ServiceAccount name.
*/}}
{{- define "petclinic-service.serviceAccountName" -}}
{{- if .Values.serviceAccount.name }}
{{- .Values.serviceAccount.name }}
{{- else }}
{{- include "petclinic-service.fullname" . }}
{{- end }}
{{- end }}

{{/*
ConfigMap name.
*/}}
{{- define "petclinic-service.configMapName" -}}
{{- printf "%s-config" (include "petclinic-service.fullname" .) -}}
{{- end }}
