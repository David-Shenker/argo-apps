{{/*
=============================================================================
App-of-Apps Template
Generates ArgoCD Application resources for app-of-apps pattern
=============================================================================
*/}}

{{- define "chart-library.appofapps" -}}
{{- range $namespace, $apps := .Values.appofapps }}
{{- range $appKey, $appSpec := $apps }}
{{- if $appSpec.enabled }}

{{- /* Normalize app name */ -}}
{{- $appName := include "chart-library.normalizeName" $appKey -}}

{{- /* Get configuration from values with safe access */ -}}
{{- $paths := $.Values.paths | default dict -}}
{{- $valuesDir := $paths.values | default "values" -}}
{{- $clustersDir := $paths.clusters | default "clusters" -}}
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
{{- $repoURL := $appSpec.repoURL | default $repoConfig.url | required "repo.url is required" -}}
{{- $revision := $appSpec.revision | default $repoConfig.revision | default "HEAD" -}}

{{- /* Defaults with safe access */ -}}
{{- $defaultsConfig := $.Values.defaults | default dict -}}

{{- /* Determine if multi-source (handle explicit false) */ -}}
{{- $multiSource := $defaultsConfig.multiSource | default false -}}
{{- if hasKey $appSpec "multiSource" -}}
{{- $multiSource = $appSpec.multiSource -}}
{{- end -}}

{{- /* Chart settings (only needed for multi-source) */ -}}
{{- $chartConfig := $.Values.chart | default dict -}}
{{- $chartRepoURL := "" -}}
{{- $chartVersion := "1.0.0" -}}
{{- if $multiSource -}}
{{- $chartRepoURL = $appSpec.chartRepoURL | default $chartConfig.repoURL | required "chart.repoURL is required for multi-source" -}}
{{- $chartVersion = $appSpec.chartVersion | default $chartConfig.version | default "1.0.0" -}}
{{- end -}}

{{- /* Build source path */ -}}
{{- $sourcePath := $appSpec.sourcePath | default (printf "%s/%s" $clustersDir $cluster) -}}

{{- /* Generate full app name with namespace suffix */ -}}
{{- $fullAppName := include "chart-library.appName" (dict "appName" $appName "namespace" $namespace) -}}

{{- /* Build template values */ -}}
{{- $appTemplateValues := dict
    "appName" $fullAppName
    "argocdNamespace" ($defaultsConfig.argocdNamespace | default "argocd")
    "project" ($appSpec.project | default $defaultsConfig.project | default "default")
    "destinationNamespace" $namespace
    "server" ($appSpec.server | default $defaultsConfig.server | default "https://kubernetes.default.svc")
    "labels" $appSpec.labels
    "annotations" $appSpec.annotations
    "disableFinalizers" ($appSpec.disableFinalizers | default false)
    "finalizers" $appSpec.finalizers
    "sourceRepoURL" $repoURL
    "sourcePath" $sourcePath
    "sourceTargetRevision" $revision
    "chartName" $appName
    "chartReleaseName" $appName
    "appReleaseName" $appName
    "valuesDir" $valuesDir
    "chartRepoURL" $chartRepoURL
    "chartVersion" $chartVersion
    "cluster" $cluster
    "cloud" $cloud
    "valueFiles" $appSpec.valueFiles
    "syncPolicy" ($appSpec.syncPolicy | default dict)
    "recurseSubmodules" ($appSpec.recurseSubmodules | default $defaultsConfig.recurseSubmodules | default false)
    "multiSource" ($multiSource | toString)
    "ignoreMissingValueFiles" ($appSpec.ignoreMissingValueFiles | default $defaultsConfig.ignoreMissingValueFiles | default true)
    "helmValues" $appSpec.helmValues
-}}
---
apiVersion: argoproj.io/v1alpha1
kind: Application
{{ include "chart-library.application" $appTemplateValues }}
{{ end }}
{{ end }}
{{ end }}
{{- end }}


{{/*
=============================================================================
Backwards compatibility alias for cluster.appofapps
=============================================================================
*/}}
{{- define "cluster.appofapps" -}}
{{- include "chart-library.appofapps" . -}}
{{- end }}
