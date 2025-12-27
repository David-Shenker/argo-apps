{{/*
=============================================================================
ApplicationSet Template
Generates ArgoCD ApplicationSet resources with configurable paths
=============================================================================
*/}}

{{- define "chart-library.applicationset" -}}
{{- range $appSetKey, $appSetSpec := .Values.appSets }}
{{- if $appSetSpec.enabled }}

{{- /* Normalize appSet name */ -}}
{{- $appSetName := include "chart-library.normalizeName" $appSetKey -}}
{{- $appSetSpec := coalesce $appSetSpec dict -}}

{{- /* Get configuration from values with safe access */ -}}
{{- $paths := $.Values.paths | default dict -}}
{{- $valuesDir := $paths.values | default "values" -}}
{{- $chartsDir := $paths.charts | default "helm-charts" -}}
{{- $clusterConfig := $.Values.cluster | default dict -}}
{{- $cluster := "" -}}
{{- if kindIs "string" $.Values.cluster -}}
{{- $cluster = $.Values.cluster -}}
{{- else -}}
{{- $cluster = $clusterConfig.name | default "" -}}
{{- end -}}
{{- $cloud := $clusterConfig.cloud | default "" -}}

{{- /* Repository settings with safe access */ -}}
{{- $repoConfig := $.Values.repo | default dict -}}
{{- $repoURL := $appSetSpec.repoURL | default $repoConfig.url | required "repo.url is required" -}}
{{- $revision := $appSetSpec.revision | default $repoConfig.revision | default "HEAD" -}}

{{- /* Generator path configuration with safe access */ -}}
{{- $generatorConfig := $.Values.generator | default dict -}}
{{- $segmentsConfig := $generatorConfig.segments | default dict -}}
{{- $segmentNamespace := $segmentsConfig.namespace | default 3 -}}
{{- $segmentChartName := $segmentsConfig.chartName | default 4 -}}

{{- /* Build the generator path pattern */ -}}
{{- $pathPattern := $appSetSpec.pathPattern | default (printf "%s/%s/%s/*/*/*.yaml" $valuesDir $cluster $appSetName) -}}

{{- /* Defaults with safe access */ -}}
{{- $defaultsConfig := $.Values.defaults | default dict -}}

{{- /* Determine if multi-source (handle explicit false) */ -}}
{{- $multiSource := $defaultsConfig.multiSource | default false -}}
{{- if hasKey $appSetSpec "multiSource" -}}
{{- $multiSource = $appSetSpec.multiSource -}}
{{- end -}}

{{- /* Chart settings (only needed for multi-source) */ -}}
{{- $chartConfig := $.Values.chart | default dict -}}
{{- $chartRepoURL := "" -}}
{{- $chartVersion := "1.0.0" -}}
{{- if $multiSource -}}
{{- $chartRepoURL = $appSetSpec.chartRepoURL | default $chartConfig.repoURL | required "chart.repoURL is required for multi-source" -}}
{{- $chartVersion = $appSetSpec.chartVersion | default $chartConfig.version | default "1.0.0" -}}
{{- end -}}

{{- /* Preservation settings */ -}}
{{- $preserveResourcesOnDeletion := $appSetSpec.preserveResourcesOnDeletion | default false -}}

{{- /* Build dynamic Go template expressions for ApplicationSet */ -}}
{{- $goTplNamespace := printf "{{ index .path.segments %d }}" (int $segmentNamespace) -}}
{{- $goTplChartName := printf "{{ index .path.segments %d }}" (int $segmentChartName) -}}
{{- $goTplFilename := "{{ trimSuffix \".yaml\" .path.filename }}" -}}

{{- /* Build chart release name expression */ -}}
{{- $goTplReleaseName := printf "{{ .chartReleaseName | default (ternary (trimSuffix \".yaml\" .path.filename) (printf \"%%s-%%s\" (index .path.segments %d) (trimSuffix \".yaml\" .path.filename)) (contains (index .path.segments %d) (trimSuffix \".yaml\" .path.filename))) }}" (int $segmentChartName) (int $segmentChartName) -}}

{{- /* Build app name (includes namespace for uniqueness) */ -}}
{{- $goTplAppName := printf "%s--%s" $goTplReleaseName $goTplNamespace -}}

{{- /* Source path for single-source mode */ -}}
{{- $sourcePath := printf "%s/%s" $chartsDir $goTplChartName -}}

{{- /* Build template values for the application */ -}}
{{- $appTemplateValues := dict
    "appName" $goTplAppName
    "appSetName" $appSetName
    "appReleaseName" $goTplFilename
    "labels" (dict "appset" $appSetName)
    "destinationNamespace" $goTplNamespace
    "disableFinalizers" (ternary true false $preserveResourcesOnDeletion)
    "sourcePath" $sourcePath
    "sourceTargetRevision" (printf "{{ .sourceTargetRevision | default \"%s\" }}" ($appSetSpec.sourceTargetRevision | default $revision))
    "sourceRepoURL" $repoURL
    "recurseSubmodules" ($appSetSpec.recurseSubmodules | default $defaultsConfig.recurseSubmodules | default false)
    "chartName" $goTplChartName
    "chartReleaseName" $goTplReleaseName
    "valuesDir" $valuesDir
    "chartRepoURL" $chartRepoURL
    "chartVersion" (printf "{{ .chartVersion | default \"%s\" }}" $chartVersion)
    "cluster" $cluster
    "cloud" $cloud
    "Template" $.Template
    "multiSource" ($multiSource | toString)
    "ignoreMissingValueFiles" ($appSetSpec.ignoreMissingValueFiles | default $defaultsConfig.ignoreMissingValueFiles | default true)
-}}
---
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: {{ $appSetName | quote }}
  namespace: {{ $defaultsConfig.argocdNamespace | default "argocd" | quote }}
  {{- with $appSetSpec.labels }}
  labels:
    {{- toYaml . | nindent 4 }}
  {{- end }}
  {{- with $appSetSpec.annotations }}
  annotations:
    {{- toYaml . | nindent 4 }}
  {{- end }}
spec:
  syncPolicy:
    preserveResourcesOnDeletion: {{ $preserveResourcesOnDeletion }}
  goTemplate: true
  generators:
    - git:
        repoURL: {{ $repoURL | quote }}
        revision: {{ $revision | quote }}
        files:
          - path: {{ $pathPattern | quote }}
        {{- if $multiSource }}
        values:
          chartVersion: {{ $chartVersion | quote }}
        {{- end }}

  template:
    {{- toYaml (mustMergeOverwrite dict (include "chart-library.application" $appTemplateValues | fromYaml) ($appSetSpec.template | default dict)) | nindent 4 }}

  # Allow application values file to override template settings
  templatePatch: |
    {{ "{{- if .application }}" }}
    {{ "{{ toYaml .application | nindent 4 }}" }}
    {{ "{{- end }}" }}
{{ end }}
{{ end }}
{{- end }}


{{/*
=============================================================================
Backwards compatibility alias for cluster.applicationset
=============================================================================
*/}}
{{- define "cluster.applicationset" -}}
{{- include "chart-library.applicationset" . -}}
{{- end }}
