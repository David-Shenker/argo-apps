{{/*
=============================================================================
App-of-Apps Template
Generates ArgoCD Application resources for app-of-apps pattern
=============================================================================
*/}}

{{- define "chart-library.appofapps" -}}
{{- $paths := .Values.paths | default dict -}}
{{- $valuesDir := $paths.values | default "values" -}}
{{- $clustersDir := $paths.clusters | default "clusters" -}}
{{- $clusterConfig := .Values.cluster | default dict -}}
{{- $cluster := ternary .Values.cluster $clusterConfig.name (kindIs "string" .Values.cluster) | default "" -}}
{{- $cloud := $clusterConfig.cloud | default "" -}}
{{- $repoConfig := .Values.repo | default dict -}}
{{- $defaultsConfig := .Values.defaults | default dict -}}
{{- $chartConfig := .Values.chart | default dict -}}

{{- range $namespace, $apps := .Values.appofapps }}
{{- range $appKey, $appSpec := $apps }}
{{- if $appSpec.enabled }}
{{- $appName := include "chart-library.normalizeName" $appKey -}}

{{- /* Repository settings */ -}}
{{- $repoURL := $appSpec.repoURL | default $repoConfig.url | required "repo.url is required" -}}
{{- $revision := $appSpec.revision | default $repoConfig.revision | default "HEAD" -}}

{{- /* Multi-source settings */ -}}
{{- $multiSource := $defaultsConfig.multiSource | default false -}}
{{- if hasKey $appSpec "multiSource" -}}
{{- $multiSource = $appSpec.multiSource -}}
{{- end -}}
{{- $chartRepoURL := "" -}}
{{- $chartVersion := "1.0.0" -}}
{{- if $multiSource -}}
{{- $chartRepoURL = $appSpec.chartRepoURL | default $chartConfig.repoURL | required "chart.repoURL is required for multi-source" -}}
{{- $chartVersion = $appSpec.chartVersion | default $chartConfig.version | default "1.0.0" -}}
{{- end -}}

{{- /* Build source path and full app name */ -}}
{{- $sourcePath := $appSpec.sourcePath | default (printf "%s/%s" $clustersDir $cluster) -}}
{{- $fullAppName := include "chart-library.appName" (dict "appName" $appName "namespace" $namespace) -}}

{{- /* Build template context */ -}}
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
{{- end }}
{{- end }}
{{- end }}
{{- end }}


{{/*
=============================================================================
Backwards compatibility alias
=============================================================================
*/}}
{{- define "cluster.appofapps" -}}
{{- include "chart-library.appofapps" . -}}
{{- end }}
