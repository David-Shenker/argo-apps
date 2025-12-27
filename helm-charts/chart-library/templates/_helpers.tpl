{{/*
=============================================================================
Chart Library - Helper Templates
=============================================================================
*/}}

{{/*
Convert underscores to hyphens and normalize name
*/}}
{{- define "chart-library.normalizeName" -}}
{{- snakecase . | replace "_" "-" }}
{{- end -}}

{{/*
Generate application name with namespace suffix
Format: {appName}--{namespace}
*/}}
{{- define "chart-library.appName" -}}
{{- $appName := .appName | default .chartName -}}
{{- $namespace := .namespace | default "default" -}}
{{- if .fullnameOverride -}}
{{- .fullnameOverride -}}
{{- else -}}
{{- printf "%s--%s" $appName $namespace -}}
{{- end -}}
{{- end -}}

{{/*
Get value with fallback chain
Usage: {{ include "chart-library.getValue" (dict "value" .specific "default" .general "fallback" "hardcoded") }}
*/}}
{{- define "chart-library.getValue" -}}
{{- coalesce .value .default .fallback -}}
{{- end -}}

{{/*
Build repository URL from context
*/}}
{{- define "chart-library.repoURL" -}}
{{- coalesce .repoURL .Values.repo.url | required "repo.url is required" -}}
{{- end -}}

{{/*
Build revision from context
*/}}
{{- define "chart-library.revision" -}}
{{- coalesce .revision .Values.repo.revision "HEAD" -}}
{{- end -}}

{{/*
Build chart repo URL from context
*/}}
{{- define "chart-library.chartRepoURL" -}}
{{- coalesce .chartRepoURL .Values.chart.repoURL | required "chart.repoURL is required for multi-source" -}}
{{- end -}}

{{/*
Build chart version from context
*/}}
{{- define "chart-library.chartVersion" -}}
{{- coalesce .chartVersion .Values.chart.version "1.0.0" -}}
{{- end -}}

{{/*
Get cluster name
*/}}
{{- define "chart-library.clusterName" -}}
{{- .Values.cluster.name | default .Values.cluster | required "cluster.name is required" -}}
{{- end -}}

{{/*
Get cloud provider (optional)
*/}}
{{- define "chart-library.cloud" -}}
{{- .Values.cluster.cloud | default "" -}}
{{- end -}}

{{/*
Build value files list from template
Usage: {{ include "chart-library.buildValueFiles" (dict "ctx" . "valuesDir" "values" "cluster" "prod" ...) }}
*/}}
{{- define "chart-library.buildValueFiles" -}}
{{- $valueFilesConfig := .valueFiles | default .ctx.Values.paths.valueFiles -}}
{{- range $valueFilesConfig -}}
{{- $rendered := tpl . $.ctx -}}
{{- if $rendered }}
- {{ $rendered | quote }}
{{- end }}
{{- end -}}
{{- end -}}

{{/*
Merge sync policy with defaults
*/}}
{{- define "chart-library.syncPolicy" -}}
{{- $defaults := .Values.syncPolicy | default dict -}}
{{- $override := .syncPolicy | default dict -}}
{{- toYaml (mustMergeOverwrite (deepCopy $defaults) $override) -}}
{{- end -}}

{{/*
=============================================================================
Standard Helm Chart Helpers (kept for backwards compatibility)
=============================================================================
*/}}

{{/* Expand the name of the chart */}}
{{- define "chart-library.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/* Create a default fully qualified app name */}}
{{- define "chart-library.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- $name := default .Chart.Name .Values.nameOverride }}
{{- if contains $name .Release.Name }}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}
{{- end }}

{{/* Create chart name and version as used by the chart label */}}
{{- define "chart-library.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/* Common labels */}}
{{- define "chart-library.labels" -}}
helm.sh/chart: {{ include "chart-library.chart" . }}
{{- with .Values.team }}
team: {{ . | quote }}
{{- end }}
{{ include "chart-library.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/* Selector labels */}}
{{- define "chart-library.selectorLabels" -}}
app.kubernetes.io/name: {{ include "chart-library.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/* Create the name of the service account to use */}}
{{- define "chart-library.serviceAccountName" -}}
{{- if and .Values.serviceAccount .Values.serviceAccount.create }}
{{- default (include "chart-library.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" ((.Values.serviceAccount).name) }}
{{- end }}
{{- end }}

{{/* Create namespace */}}
{{- define "chart-library.namespace" -}}
{{- .Values.namespaceOverride | default .Release.Namespace }}
{{- end }}

{{/*
Merge two YAML templates and output the result
Usage: {{ include "chart-library.merge" (list . "overrides-template" "base-template") }}
*/}}
{{- define "chart-library.merge" -}}
{{- $top := first . -}}
{{- $overrides := fromYaml (include (index . 1) $top) | default dict -}}
{{- $base := fromYaml (include (index . 2) $top) | default dict -}}
{{- toYaml (mustMergeOverwrite (deepCopy $base) $overrides) -}}
{{- end -}}

{{/*
Backwards compatibility alias
*/}}
{{- define "chart-library.underscoreToHyphen" -}}
{{- include "chart-library.normalizeName" . -}}
{{- end -}}
