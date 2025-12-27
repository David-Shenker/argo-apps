{{/*
=============================================================================
Chart Library - Helper Templates
=============================================================================
*/}}

{{/*
=============================================================================
Name Helpers
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
{{- $appName := .appName | default .name -}}
{{- $namespace := .namespace | default "default" -}}
{{- if .fullnameOverride -}}
{{- .fullnameOverride -}}
{{- else -}}
{{- printf "%s--%s" $appName $namespace -}}
{{- end -}}
{{- end -}}

{{/*
=============================================================================
Value Resolution Helpers
=============================================================================
*/}}

{{/*
Get cluster name (supports both string and map format)
*/}}
{{- define "chart-library.clusterName" -}}
{{- if kindIs "string" .Values.cluster -}}
{{- .Values.cluster -}}
{{- else -}}
{{- .Values.cluster.name | default "" -}}
{{- end -}}
{{- end -}}

{{/*
Get cloud provider
*/}}
{{- define "chart-library.cloud" -}}
{{- if kindIs "map" .Values.cluster -}}
{{- .Values.cluster.cloud | default "" -}}
{{- else -}}
{{- "" -}}
{{- end -}}
{{- end -}}

{{/*
=============================================================================
Sync Policy Helper
=============================================================================
*/}}

{{/*
Build sync policy with defaults
Usage: {{ include "chart-library.syncPolicy" (dict "syncPolicy" .syncPolicy "defaults" $defaults) }}
*/}}
{{- define "chart-library.syncPolicy" -}}
{{- $defaultPolicy := dict
    "automated" (dict "prune" true "selfHeal" true)
    "syncOptions" (list "FailOnSharedResource=true" "ApplyOutOfSyncOnly=true" "CreateNamespace=true")
-}}
{{- $basePolicy := .defaults.syncPolicy | default $defaultPolicy -}}
{{- $overrides := .syncPolicy | default dict -}}
{{- toYaml (mustMergeOverwrite (deepCopy $basePolicy) $overrides) -}}
{{- end -}}

{{/*
=============================================================================
Value Files Helpers
=============================================================================
*/}}

{{/*
Render value files from a configurable template list
Usage: {{ include "chart-library.renderValueFiles" (dict "valueFilesConfig" $valueFilesConfig "vars" $vars "prefix" "" "ctx" $) }}

Parameters:
  - valueFilesConfig: List of value file path templates from paths.appSetValueFiles or paths.appofappsValueFiles
  - vars: Dict with template variables (valuesDir, cluster, cloud, appSetName, namespace, chartName, releaseName)
  - prefix: Optional prefix for multi-source (e.g., "$values")
  - ctx: Template context for tpl function
*/}}
{{- define "chart-library.renderValueFiles" -}}
{{- $config := .valueFilesConfig | default list -}}
{{- $vars := .vars | default dict -}}
{{- $prefix := .prefix | default "" -}}
{{- $ctx := .ctx -}}

{{- /* Create a context dict for tpl rendering */ -}}
{{- $tplCtx := dict
    "valuesDir" ($vars.valuesDir | default "values")
    "cluster" ($vars.cluster | default "")
    "cloud" ($vars.cloud | default "")
    "appSetName" ($vars.appSetName | default "")
    "namespace" ($vars.namespace | default "")
    "chartName" ($vars.chartName | default "")
    "releaseName" ($vars.releaseName | default "")
-}}

{{- range $config }}
  {{- /* Render the template with variables */ -}}
  {{- $rendered := tpl . $tplCtx -}}
  {{- /* Skip if the rendered path contains empty segments (from missing variables) */ -}}
  {{- if and $rendered (not (contains "//" $rendered)) (not (contains "/_defaults//" $rendered)) }}
    {{- /* Ensure path starts with / */ -}}
    {{- $path := $rendered -}}
    {{- if not (hasPrefix "/" $path) }}
      {{- $path = printf "/%s" $path -}}
    {{- end }}
    {{- /* Add prefix for multi-source */ -}}
    {{- if $prefix }}
- {{ printf "%s%s" $prefix $path | quote }}
    {{- else }}
- {{ $path | quote }}
    {{- end }}
  {{- end }}
{{- end }}
{{- end -}}

{{/*
Render value files for App-of-Apps
Usage: {{ include "chart-library.appofappsValueFiles" (dict "app" $app "paths" $paths "cluster" $cluster "cloud" $cloud "prefix" "" "ctx" $) }}
*/}}
{{- define "chart-library.appofappsValueFiles" -}}
{{- $app := .app -}}
{{- $paths := .paths | default dict -}}
{{- $prefix := .prefix | default "" -}}

{{- /* Use app-specific valueFiles if provided, otherwise use paths.appofappsValueFiles */ -}}
{{- $valueFilesConfig := $app.valueFiles | default ($paths.appofappsValueFiles | default list) -}}

{{- $vars := dict
    "valuesDir" ($paths.values | default "values")
    "cluster" .cluster
    "cloud" .cloud
    "chartName" $app.chartName
    "releaseName" $app.releaseName
-}}

{{- include "chart-library.renderValueFiles" (dict "valueFilesConfig" $valueFilesConfig "vars" $vars "prefix" $prefix "ctx" .ctx) -}}
{{- end -}}

{{/*
Render value files for ApplicationSet (with Go template expressions)
Usage: {{ include "chart-library.appSetValueFiles" (dict "appSet" $appSet "paths" $paths "cluster" $cluster "cloud" $cloud "appSetName" $appSetName "goTpl" $goTpl "prefix" "" "ctx" $) }}
*/}}
{{- define "chart-library.appSetValueFiles" -}}
{{- $appSet := .appSet -}}
{{- $paths := .paths | default dict -}}
{{- $prefix := .prefix | default "" -}}
{{- $goTpl := .goTpl -}}

{{- /* Use appSet-specific valueFiles if provided, otherwise use paths.appSetValueFiles */ -}}
{{- $valueFilesConfig := $appSet.valueFiles | default ($paths.appSetValueFiles | default list) -}}

{{- /* Build vars with Go template expressions for dynamic values */ -}}
{{- $vars := dict
    "valuesDir" ($paths.values | default "values")
    "cluster" .cluster
    "cloud" .cloud
    "appSetName" .appSetName
    "namespace" $goTpl.namespace
    "chartName" $goTpl.chartName
    "releaseName" $goTpl.filename
-}}

{{- include "chart-library.renderValueFiles" (dict "valueFilesConfig" $valueFilesConfig "vars" $vars "prefix" $prefix "ctx" .ctx) -}}
{{- end -}}

{{/*
=============================================================================
ApplicationSet Go Template Expression Helpers
=============================================================================
*/}}

{{/*
Build Go template expressions for ApplicationSet
Usage: {{ include "chart-library.appSetGoTpl" (dict "segments" $segments) }}
Returns a dict with namespace, chartName, filename, releaseName, appName expressions
*/}}
{{- define "chart-library.appSetGoTpl" -}}
{{- $nsIdx := .segments.namespace | default 3 -}}
{{- $chartIdx := .segments.chartName | default 4 -}}
{{- $ns := printf "{{ index .path.segments %d }}" (int $nsIdx) -}}
{{- $chart := printf "{{ index .path.segments %d }}" (int $chartIdx) -}}
{{- $filename := "{{ trimSuffix \".yaml\" .path.filename }}" -}}
{{- $release := printf "{{ .chartReleaseName | default (ternary (trimSuffix \".yaml\" .path.filename) (printf \"%%s-%%s\" (index .path.segments %d) (trimSuffix \".yaml\" .path.filename)) (contains (index .path.segments %d) (trimSuffix \".yaml\" .path.filename))) }}" (int $chartIdx) (int $chartIdx) -}}
{{- $appName := printf "%s--%s" $release $ns -}}
{{- dict "namespace" $ns "chartName" $chart "filename" $filename "releaseName" $release "appName" $appName | toYaml -}}
{{- end -}}

{{/*
=============================================================================
Standard Helm Chart Helpers (backwards compatibility)
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
Backwards compatibility aliases
*/}}
{{- define "chart-library.underscoreToHyphen" -}}
{{- include "chart-library.normalizeName" . -}}
{{- end -}}

{{- define "chart-library.getValue" -}}
{{- coalesce .value .default .fallback -}}
{{- end -}}

{{- define "chart-library.repoURL" -}}
{{- coalesce .repoURL .Values.repo.url | required "repo.url is required" -}}
{{- end -}}

{{- define "chart-library.revision" -}}
{{- coalesce .revision .Values.repo.revision "HEAD" -}}
{{- end -}}

{{- define "chart-library.chartRepoURL" -}}
{{- coalesce .chartRepoURL .Values.chart.repoURL | required "chart.repoURL is required for multi-source" -}}
{{- end -}}

{{- define "chart-library.chartVersion" -}}
{{- coalesce .chartVersion .Values.chart.version "1.0.0" -}}
{{- end -}}

{{/*
Legacy valueFiles helper (backwards compatibility)
*/}}
{{- define "chart-library.valueFiles" -}}
{{- $app := .app -}}
{{- $ctx := .ctx -}}
{{- $prefix := .prefix | default "" -}}

{{- if $app.valueFiles -}}
  {{- range $app.valueFiles -}}
    {{- $path := tpl . $ctx | replace "\\" "" -}}
    {{- if hasPrefix "/" $path }}
      {{- if $prefix }}
- {{ printf "%s%s" $prefix $path | quote }}
      {{- else }}
- {{ $path | quote }}
      {{- end }}
    {{- else }}
      {{- if $prefix }}
- {{ printf "%s/%s" $prefix $path | quote }}
      {{- else }}
- {{ printf "/%s" $path | quote }}
      {{- end }}
    {{- end }}
  {{- end -}}
{{- end -}}
{{- end -}}
