{{/*
=============================================================================
App-of-Apps Template
Generates ArgoCD Application resources for app-of-apps pattern
Usage: {{ include "chart-library.appofapps" . }}
=============================================================================
*/}}

{{- define "chart-library.appofapps" -}}
{{- $defaults := .Values.defaults | default dict -}}
{{- $paths := .Values.paths | default dict -}}
{{- $repo := .Values.repo | default dict -}}
{{- $chart := .Values.chart | default dict -}}
{{- $cluster := include "chart-library.clusterName" . -}}
{{- $cloud := include "chart-library.cloud" . -}}
{{- $valuesDir := $paths.values | default "values" -}}
{{- $clustersDir := $paths.clusters | default "clusters" -}}
{{- range $namespace, $apps := .Values.appofapps -}}
{{- range $appKey, $app := $apps -}}
{{- if $app.enabled -}}
{{- $appName := include "chart-library.normalizeName" $appKey -}}
{{- $fullAppName := printf "%s--%s" $appName $namespace -}}
{{- $multiSource := $app.multiSource | default $defaults.multiSource | default false -}}
{{- $repoURL := $app.repoURL | default $repo.url | required "repo.url is required" -}}
{{- $revision := $app.revision | default $repo.revision | default "HEAD" -}}
{{- $sourcePath := $app.sourcePath | default (printf "%s/%s" $clustersDir $cluster) -}}
{{- $appContext := merge $app (dict "chartName" $appName "releaseName" $appName "sourcePath" $sourcePath) -}}
{{- $valueFilesArgs := dict "app" $appContext "paths" $paths "cluster" $cluster "cloud" $cloud "ctx" $ }}
---
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: {{ $fullAppName | quote }}
  namespace: {{ $defaults.argocdNamespace | default "argocd" }}
{{- if not $app.disableFinalizers }}
  finalizers: {{ toYaml ($app.finalizers | default (list "resources-finalizer.argocd.argoproj.io")) | nindent 4 }}
{{- end }}
{{- with $app.labels }}
  labels: {{ toYaml . | nindent 4 }}
{{- end }}
{{- with $app.annotations }}
  annotations: {{ toYaml . | nindent 4 }}
{{- end }}
spec:
  project: {{ $app.project | default $defaults.project | default "default" | quote }}
  destination:
    server: {{ $app.server | default $defaults.server | default "https://kubernetes.default.svc" | quote }}
    namespace: {{ $namespace | quote }}
{{- if $multiSource }}
  sources:
    - repoURL: {{ $app.chartRepoURL | default $chart.repoURL | required "chart.repoURL is required for multi-source" | quote }}
      chart: {{ $appName | quote }}
      targetRevision: {{ $app.chartVersion | default $chart.version | default "1.0.0" | quote }}
      helm:
        releaseName: {{ $appName | quote }}
        ignoreMissingValueFiles: {{ $app.ignoreMissingValueFiles | default $defaults.ignoreMissingValueFiles | default true }}
        valueFiles: {{ include "chart-library.appofappsValueFiles" (merge $valueFilesArgs (dict "prefix" "$values")) | nindent 10 }}
{{- with $app.helmValues }}
        values: |- {{ toYaml . | nindent 10 }}
{{- end }}
    - repoURL: {{ $repoURL | quote }}
      targetRevision: {{ $revision | quote }}
{{- if ($app.recurseSubmodules | default $defaults.recurseSubmodules | default false) }}
      directory:
        recurse: true
{{- end }}
      ref: values
{{- else }}
  source:
    repoURL: {{ $repoURL | quote }}
    path: {{ $sourcePath | quote }}
    targetRevision: {{ $revision | quote }}
{{- if ($app.recurseSubmodules | default $defaults.recurseSubmodules | default false) }}
    directory:
      recurse: true
{{- end }}
    helm:
      releaseName: {{ $appName | quote }}
      ignoreMissingValueFiles: {{ $app.ignoreMissingValueFiles | default $defaults.ignoreMissingValueFiles | default true }}
      valueFiles: {{ include "chart-library.appofappsValueFiles" $valueFilesArgs | nindent 8 }}
{{- with $app.helmValues }}
      values: |- {{ toYaml . | nindent 8 }}
{{- end }}
{{- end }}
{{- $syncPolicy := $app.syncPolicy | default dict -}}
{{- $automated := $syncPolicy.automated | default dict -}}
{{- $prune := true -}}
{{- if hasKey $automated "prune" -}}
{{- $prune = $automated.prune -}}
{{- end -}}
{{- $selfHeal := true -}}
{{- if hasKey $automated "selfHeal" -}}
{{- $selfHeal = $automated.selfHeal -}}
{{- end }}
  syncPolicy:
    automated:
      prune: {{ $prune }}
      selfHeal: {{ $selfHeal }}
    syncOptions:
    {{- $defaultSyncOptions := list "FailOnSharedResource=true" "ApplyOutOfSyncOnly=true" "CreateNamespace=true" }}
    {{- range ($syncPolicy.syncOptions | default $defaultSyncOptions) }}
    - {{ . }}
    {{- end }}
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
