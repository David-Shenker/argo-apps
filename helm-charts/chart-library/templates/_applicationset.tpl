{{/*
=============================================================================
ApplicationSet Template
Generates ArgoCD ApplicationSet resources
=============================================================================
*/}}

{{- define "chart-library.applicationset" -}}
{{- $paths := .Values.paths | default dict -}}
{{- $valuesDir := $paths.values | default "values" -}}
{{- $chartsDir := $paths.charts | default "helm-charts" -}}
{{- $clusterConfig := .Values.cluster | default dict -}}
{{- $cluster := ternary .Values.cluster $clusterConfig.name (kindIs "string" .Values.cluster) | default "" -}}
{{- $cloud := $clusterConfig.cloud | default "" -}}
{{- $repoConfig := .Values.repo | default dict -}}
{{- $defaultsConfig := .Values.defaults | default dict -}}
{{- $chartConfig := .Values.chart | default dict -}}
{{- $generatorConfig := .Values.generator | default dict -}}
{{- $segmentsConfig := $generatorConfig.segments | default dict -}}

{{- range $appSetKey, $appSetSpec := .Values.appSets }}
{{- if $appSetSpec.enabled }}
{{- $appSetSpec := coalesce $appSetSpec dict -}}
{{- $appSetName := include "chart-library.normalizeName" $appSetKey -}}

{{- /* Repository settings */ -}}
{{- $repoURL := $appSetSpec.repoURL | default $repoConfig.url | required "repo.url is required" -}}
{{- $revision := $appSetSpec.revision | default $repoConfig.revision | default "HEAD" -}}

{{- /* Path segments configuration */ -}}
{{- $segmentNamespace := $segmentsConfig.namespace | default 3 -}}
{{- $segmentChartName := $segmentsConfig.chartName | default 4 -}}
{{- $pathPattern := $appSetSpec.pathPattern | default (printf "%s/%s/%s/*/*/*.yaml" $valuesDir $cluster $appSetName) -}}

{{- /* Multi-source settings */ -}}
{{- $multiSource := $defaultsConfig.multiSource | default false -}}
{{- if hasKey $appSetSpec "multiSource" -}}
{{- $multiSource = $appSetSpec.multiSource -}}
{{- end -}}
{{- $chartRepoURL := "" -}}
{{- $chartVersion := "1.0.0" -}}
{{- if $multiSource -}}
{{- $chartRepoURL = $appSetSpec.chartRepoURL | default $chartConfig.repoURL | required "chart.repoURL is required for multi-source" -}}
{{- $chartVersion = $appSetSpec.chartVersion | default $chartConfig.version | default "1.0.0" -}}
{{- end -}}

{{- /* Preservation and parent settings */ -}}
{{- $preserveResourcesOnDeletion := $appSetSpec.preserveResourcesOnDeletion | default false -}}
{{- $parentInstance := $defaultsConfig.parentInstance | default "" -}}

{{- /* Go template expressions for ApplicationSet */ -}}
{{- $goTplNamespace := printf "{{ index .path.segments %d }}" (int $segmentNamespace) -}}
{{- $goTplChartName := printf "{{ index .path.segments %d }}" (int $segmentChartName) -}}
{{- $goTplFilename := "{{ trimSuffix \".yaml\" .path.filename }}" -}}
{{- $goTplReleaseName := printf "{{ .chartReleaseName | default (ternary (trimSuffix \".yaml\" .path.filename) (printf \"%%s-%%s\" (index .path.segments %d) (trimSuffix \".yaml\" .path.filename)) (contains (index .path.segments %d) (trimSuffix \".yaml\" .path.filename))) }}" (int $segmentChartName) (int $segmentChartName) -}}
{{- $goTplAppName := printf "%s--%s" $goTplReleaseName $goTplNamespace -}}
{{- $sourcePath := printf "%s/%s" $chartsDir $goTplChartName -}}

{{- /* Build template context */ -}}
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
  {{- if or (ne $parentInstance "") $appSetSpec.labels }}
  labels:
    {{- if ne $parentInstance "" }}
    argocd.argoproj.io/instance: {{ $parentInstance | quote }}
    {{- end }}
    {{- with $appSetSpec.labels }}
    {{- toYaml . | nindent 4 }}
    {{- end }}
  {{- end }}
  {{- with $appSetSpec.annotations }}
  annotations: {{ toYaml . | nindent 4 }}
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
  template: {{ toYaml (mustMergeOverwrite dict (include "chart-library.application" $appTemplateValues | fromYaml) ($appSetSpec.template | default dict)) | nindent 4 }}
  templatePatch: |
    {{ "{{- if .application }}" }}
    {{ "{{ toYaml .application | nindent 4 }}" }}
    {{ "{{- end }}" }}
{{- end }}
{{- end }}
{{- end }}


{{/*
=============================================================================
Backwards compatibility alias
=============================================================================
*/}}
{{- define "cluster.applicationset" -}}
{{- include "chart-library.applicationset" . -}}
{{- end }}
