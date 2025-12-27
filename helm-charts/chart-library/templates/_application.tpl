{{/*
=============================================================================
Application Template
Generates ArgoCD Application metadata and spec
=============================================================================
*/}}

{{- define "chart-library.application" -}}
{{- $multiSource := eq (toString .multiSource) "true" -}}
metadata:
  name: {{ required "appName is required" .appName | quote }}
  namespace: {{ .argocdNamespace | default "argocd" }}
  {{- if not .disableFinalizers }}
  finalizers: {{ toYaml (.finalizers | default (list "resources-finalizer.argocd.argoproj.io")) | nindent 4 }}
  {{- end }}
  {{- with .labels }}
  labels: {{ toYaml . | nindent 4 }}
  {{- end }}
  {{- with .annotations }}
  annotations: {{ toYaml . | nindent 4 }}
  {{- end }}
spec:
  project: {{ .project | default "default" | quote }}
  destination:
    server: {{ .server | default "https://kubernetes.default.svc" | quote }}
    namespace: {{ .destinationNamespace | quote }}
  {{- if $multiSource }}
  {{- include "chart-library.application.sources" . | nindent 2 }}
  {{- else }}
  {{- include "chart-library.application.source" . | nindent 2 }}
  {{- end }}
  syncPolicy: {{ include "chart-library.application.syncPolicy" . | nindent 4 }}
{{- end }}


{{/*
=============================================================================
Single Source Configuration
=============================================================================
*/}}
{{- define "chart-library.application.source" -}}
source:
  repoURL: {{ required "sourceRepoURL is required" .sourceRepoURL | quote }}
  path: {{ required "sourcePath is required" .sourcePath | quote }}
  targetRevision: {{ required "sourceTargetRevision is required" .sourceTargetRevision | quote }}
  {{- if .recurseSubmodules }}
  directory:
    recurse: true
  {{- end }}
  helm:
    {{- with .chartReleaseName }}
    releaseName: {{ . | quote }}
    {{- end }}
    ignoreMissingValueFiles: {{ .ignoreMissingValueFiles | default true }}
    valueFiles: {{ include "chart-library.application.valueFiles" (dict "ctx" .) | nindent 6 }}
    {{- with .helmValues }}
    values: |- {{ toYaml . | nindent 6 }}
    {{- end }}
{{- end }}


{{/*
=============================================================================
Multi-Source Configuration
=============================================================================
*/}}
{{- define "chart-library.application.sources" -}}
sources:
  - repoURL: {{ required "chartRepoURL is required for multi-source" .chartRepoURL | quote }}
    chart: {{ .chartName | quote }}
    targetRevision: {{ required "chartVersion is required" .chartVersion | quote }}
    helm:
      {{- with .chartReleaseName }}
      releaseName: {{ . | quote }}
      {{- end }}
      ignoreMissingValueFiles: {{ .ignoreMissingValueFiles | default true }}
      valueFiles: {{ include "chart-library.application.valueFiles" (dict "ctx" . "prefix" "$values") | nindent 8 }}
      {{- with .helmValues }}
      values: |- {{ toYaml . | nindent 8 }}
      {{- end }}
  - repoURL: {{ required "sourceRepoURL is required" .sourceRepoURL | quote }}
    targetRevision: {{ required "sourceTargetRevision is required" .sourceTargetRevision | quote }}
    {{- if .recurseSubmodules }}
    directory:
      recurse: true
    {{- end }}
    ref: values
{{- end }}


{{/*
=============================================================================
Value Files Generator
=============================================================================
*/}}
{{- define "chart-library.application.valueFiles" -}}
{{- $ctx := .ctx -}}
{{- $prefix := .prefix | default "" -}}
{{- $valueFiles := $ctx.valueFiles | default list -}}

{{- if $valueFiles -}}
  {{- range $valueFiles -}}
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
{{- else -}}
  {{- /* Build default value files hierarchy */ -}}
  {{- $valuesDir := $ctx.valuesDir | default "values" -}}
  {{- $cluster := $ctx.cluster | default "" -}}
  {{- $cloud := $ctx.cloud | default "" -}}
  {{- $appSetName := $ctx.appSetName | default "" -}}
  {{- $namespace := $ctx.destinationNamespace | default "" -}}
  {{- $chartName := $ctx.chartName | default "" -}}
  {{- $appReleaseName := $ctx.appReleaseName | default "" -}}

  {{- /* 1. Org-wide defaults */ -}}
  {{- if $prefix }}
- {{ printf "%s/%s/_defaults/_all.yaml" $prefix $valuesDir | quote }}
- {{ printf "%s/%s/_defaults/%s.yaml" $prefix $valuesDir $chartName | quote }}
  {{- else }}
- {{ printf "/%s/_defaults/_all.yaml" $valuesDir | quote }}
- {{ printf "/%s/_defaults/%s.yaml" $valuesDir $chartName | quote }}
  {{- end }}

  {{- /* 2. Cloud-specific values */ -}}
  {{- if $cloud }}
    {{- if $prefix }}
- {{ printf "%s/%s/_defaults/%s/%s.yaml" $prefix $valuesDir $cloud $chartName | quote }}
    {{- else }}
- {{ printf "/%s/_defaults/%s/%s.yaml" $valuesDir $cloud $chartName | quote }}
    {{- end }}
  {{- end }}

  {{- /* 3. Environment defaults */ -}}
  {{- if $prefix }}
- {{ printf "%s/%s/%s/_defaults/_all.yaml" $prefix $valuesDir $cluster | quote }}
- {{ printf "%s/%s/%s/_defaults/%s.yaml" $prefix $valuesDir $cluster $chartName | quote }}
  {{- else }}
- {{ printf "/%s/%s/_defaults/_all.yaml" $valuesDir $cluster | quote }}
- {{ printf "/%s/%s/_defaults/%s.yaml" $valuesDir $cluster $chartName | quote }}
  {{- end }}

  {{- /* 4. App-specific values */ -}}
  {{- if and $appSetName $namespace $appReleaseName }}
    {{- if $prefix }}
- {{ printf "%s/%s/%s/%s/%s/%s/%s.yaml" $prefix $valuesDir $cluster $appSetName $namespace $chartName $appReleaseName | quote }}
    {{- else }}
- {{ printf "/%s/%s/%s/%s/%s/%s.yaml" $valuesDir $cluster $appSetName $namespace $chartName $appReleaseName | quote }}
    {{- end }}
  {{- end }}
{{- end -}}
{{- end }}


{{/*
=============================================================================
Sync Policy with defaults
=============================================================================
*/}}
{{- define "chart-library.application.syncPolicy" -}}
{{- $defaults := dict
    "automated" (dict "prune" true "selfHeal" true)
    "syncOptions" (list "FailOnSharedResource=true" "ApplyOutOfSyncOnly=true" "CreateNamespace=true")
-}}
{{- toYaml (mustMergeOverwrite $defaults (.syncPolicy | default dict)) -}}
{{- end }}


{{/*
=============================================================================
Backwards compatibility alias
=============================================================================
*/}}
{{- define "chart-library.application.defaultSyncPolicy" -}}
{{- include "chart-library.application.syncPolicy" . -}}
{{- end }}
