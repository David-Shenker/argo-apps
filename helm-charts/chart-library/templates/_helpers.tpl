{{/* Name Helpers */}}

{{- define "chart-library.normalizeName" -}}
{{- snakecase . | replace "_" "-" }}
{{- end -}}

{{- define "chart-library.appName" -}}
{{- $appName := .appName | default .name -}}
{{- $namespace := .namespace | default "default" -}}
{{- if .fullnameOverride -}}
{{- .fullnameOverride -}}
{{- else -}}
{{- printf "%s--%s" $appName $namespace -}}
{{- end -}}
{{- end -}}

{{/* Value Resolution Helpers */}}

{{- define "chart-library.clusterName" -}}
{{- if kindIs "string" .Values.cluster -}}
{{- .Values.cluster -}}
{{- else -}}
{{- .Values.cluster.name | default "" -}}
{{- end -}}
{{- end -}}

{{- define "chart-library.cloud" -}}
{{- if kindIs "map" .Values.cluster -}}
{{- .Values.cluster.cloud | default "" -}}
{{- else -}}
{{- "" -}}
{{- end -}}
{{- end -}}

{{/* Sync Policy Helper */}}

{{- define "chart-library.syncPolicy" -}}
{{- $syncPolicy := .syncPolicy | default dict -}}
{{- $automated := $syncPolicy.automated | default dict -}}
{{- $defaultSyncOptions := list "FailOnSharedResource=true" "ApplyOutOfSyncOnly=true" "CreateNamespace=true" -}}
{{- $prune := true -}}
{{- if hasKey $automated "prune" -}}
{{- $prune = $automated.prune -}}
{{- end -}}
{{- $selfHeal := true -}}
{{- if hasKey $automated "selfHeal" -}}
{{- $selfHeal = $automated.selfHeal -}}
{{- end -}}
automated:
  prune: {{ $prune }}
  selfHeal: {{ $selfHeal }}
syncOptions:
{{- range ($syncPolicy.syncOptions | default $defaultSyncOptions) }}
- {{ . }}
{{- end }}
{{- end -}}

{{/* Value Files Helpers */}}

{{- define "chart-library.renderValueFiles" -}}
{{- $config := .valueFilesConfig | default list -}}
{{- $vars := .vars | default dict -}}
{{- $prefix := .prefix | default "" -}}
{{- $ctx := .ctx -}}
{{- $tplCtx := dict -}}
{{- /* Add all variables from vars to template context dynamically */}}
{{- range $key, $value := $vars }}
  {{- $_ := set $tplCtx $key $value -}}
{{- end }}
{{- range $config }}
  {{- $rendered := tpl . $tplCtx -}}
  {{- if and $rendered (not (contains "//" $rendered)) (not (contains "/_defaults//" $rendered)) }}
    {{- $path := $rendered -}}
    {{- if not (hasPrefix "/" $path) }}
      {{- $path = printf "/%s" $path -}}
    {{- end }}
    {{- if $prefix }}
- {{ printf "%s%s" $prefix $path | quote }}
    {{- else }}
- {{ $path | quote }}
    {{- end }}
  {{- end }}
{{- end }}
{{- end -}}

{{- define "chart-library.appofappsValueFiles" -}}
{{- $app := .app -}}
{{- $paths := .paths | default dict -}}
{{- $prefix := .prefix | default "" -}}
{{- $valueFilesConfig := $app.valueFiles | default ($paths.appofappsValueFiles | default list) -}}
{{- $vars := dict
    "valuesDir" ($paths.values | default "values")
    "cluster" .cluster
    "cloud" .cloud
    "chartName" $app.chartName
    "releaseName" $app.releaseName
    "sourcePath" ($app.sourcePath | default "")
-}}
{{- include "chart-library.renderValueFiles" (dict "valueFilesConfig" $valueFilesConfig "vars" $vars "prefix" $prefix "ctx" .ctx) -}}
{{- end -}}

{{- define "chart-library.appSetValueFiles" -}}
{{- $appSet := .appSet -}}
{{- $paths := .paths | default dict -}}
{{- $prefix := .prefix | default "" -}}
{{- $goTpl := .goTpl -}}
{{- $valueFilesConfig := $appSet.valueFiles | default ($paths.appSetValueFiles | default list) -}}
{{- $vars := dict
    "valuesDir" ($paths.values | default "values")
    "cluster" .cluster
    "cloud" .cloud
    "appSetName" .appSetName
    "namespace" $goTpl.namespace
    "chartName" $goTpl.chartName
    "releaseName" $goTpl.filename
-}}
{{- /* Add all additional segments from goTpl dynamically */}}
{{- range $key, $value := $goTpl }}
  {{- if and (ne $key "namespace") (ne $key "chartName") (ne $key "filename") (ne $key "releaseName") (ne $key "appName") }}
    {{- $_ := set $vars $key $value -}}
  {{- end }}
{{- end }}
{{- include "chart-library.renderValueFiles" (dict "valueFilesConfig" $valueFilesConfig "vars" $vars "prefix" $prefix "ctx" .ctx) -}}
{{- end -}}

{{/* ApplicationSet Go Template Expression Helpers */}}

{{- define "chart-library.appSetGoTpl" -}}
{{- $segments := .segments | default dict -}}
{{- $nsIdx := $segments.namespace | default 3 -}}
{{- $chartIdx := $segments.chartName | default 4 -}}
{{- $ns := printf "{{ index .path.segments %d }}" (int $nsIdx) -}}
{{- $chart := printf "{{ index .path.segments %d }}" (int $chartIdx) -}}
{{- $filename := "{{ trimSuffix \".yaml\" .path.filename }}" -}}
{{- $release := printf "{{ .chartReleaseName | default (ternary (trimSuffix \".yaml\" .path.filename) (printf \"%%s-%%s\" (index .path.segments %d) (trimSuffix \".yaml\" .path.filename)) (contains (index .path.segments %d) (trimSuffix \".yaml\" .path.filename))) }}" (int $chartIdx) (int $chartIdx) -}}
{{- $appName := printf "%s--%s" $release $ns -}}
{{- $result := dict "namespace" $ns "chartName" $chart "filename" $filename "releaseName" $release "appName" $appName -}}
{{- /* Extract any additional segments defined in configuration */}}
{{- range $key, $idx := $segments }}
  {{- if and (ne $key "namespace") (ne $key "chartName") }}
    {{- $segmentValue := printf "{{ index .path.segments %d }}" (int $idx) -}}
    {{- $_ := set $result $key $segmentValue -}}
  {{- end }}
{{- end }}
{{- $result | toYaml -}}
{{- end -}}

{{/* Standard Helm Chart Helpers */}}

{{- define "chart-library.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

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

{{- define "chart-library.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

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

{{- define "chart-library.selectorLabels" -}}
app.kubernetes.io/name: {{ include "chart-library.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{- define "chart-library.serviceAccountName" -}}
{{- if and .Values.serviceAccount .Values.serviceAccount.create }}
{{- default (include "chart-library.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" ((.Values.serviceAccount).name) }}
{{- end }}
{{- end }}

{{- define "chart-library.namespace" -}}
{{- .Values.namespaceOverride | default .Release.Namespace }}
{{- end }}

{{- define "chart-library.merge" -}}
{{- $top := first . -}}
{{- $overrides := fromYaml (include (index . 1) $top) | default dict -}}
{{- $base := fromYaml (include (index . 2) $top) | default dict -}}
{{- toYaml (mustMergeOverwrite (deepCopy $base) $overrides) -}}
{{- end -}}

{{/* Backwards Compatibility */}}

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
