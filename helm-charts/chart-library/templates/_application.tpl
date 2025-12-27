{{/*
=============================================================================
Application Template
Generates ArgoCD Application resources
Usage: {{ include "chart-library.application" (dict "applications" .Values.applications "Values" .Values "Template" .Template) }}
=============================================================================
*/}}

{{- define "chart-library.application" -}}
{{- $defaults := .Values.defaults | default dict -}}
{{- $paths := .Values.paths | default dict -}}
{{- $repo := .Values.repo | default dict -}}
{{- $chart := .Values.chart | default dict -}}
{{- $cluster := include "chart-library.clusterName" . -}}
{{- $cloud := include "chart-library.cloud" . -}}

{{- range .applications }}
{{- if not .disabled }}
{{- $app := . -}}
{{- $multiSource := eq (toString (.multiSource | default $defaults.multiSource | default false)) "true" -}}
---
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: {{ required "name is required" .name | quote }}
  namespace: {{ .argocdNamespace | default $defaults.argocdNamespace | default "argocd" }}
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
  project: {{ .project | default $defaults.project | default "default" | quote }}
  destination:
    server: {{ .server | default $defaults.server | default "https://kubernetes.default.svc" | quote }}
    namespace: {{ required "namespace is required" .namespace | quote }}
  {{- if $multiSource }}
  sources:
    - repoURL: {{ .chartRepoURL | default $chart.repoURL | required "chartRepoURL is required for multi-source" | quote }}
      chart: {{ .chartName | quote }}
      targetRevision: {{ .chartVersion | default $chart.version | default "1.0.0" | quote }}
      helm:
        {{- with .releaseName }}
        releaseName: {{ . | quote }}
        {{- end }}
        ignoreMissingValueFiles: {{ .ignoreMissingValueFiles | default $defaults.ignoreMissingValueFiles | default true }}
        valueFiles: {{ include "chart-library.valueFiles" (dict "app" (merge $app (dict "cluster" $cluster "cloud" $cloud "valuesDir" ($paths.values | default "values"))) "ctx" $ "prefix" "$values") | nindent 10 }}
        {{- with .helmValues }}
        values: |- {{ toYaml . | nindent 10 }}
        {{- end }}
    - repoURL: {{ .repoURL | default $repo.url | required "repoURL is required" | quote }}
      targetRevision: {{ .targetRevision | default $repo.revision | default "HEAD" | quote }}
      {{- if .recurseSubmodules }}
      directory:
        recurse: true
      {{- end }}
      ref: values
  {{- else }}
  source:
    repoURL: {{ .repoURL | default $repo.url | required "repoURL is required" | quote }}
    path: {{ required "path is required for single-source" .path | quote }}
    targetRevision: {{ .targetRevision | default $repo.revision | default "HEAD" | quote }}
    {{- if .recurseSubmodules }}
    directory:
      recurse: true
    {{- end }}
    helm:
      {{- with .releaseName }}
      releaseName: {{ . | quote }}
      {{- end }}
      ignoreMissingValueFiles: {{ .ignoreMissingValueFiles | default $defaults.ignoreMissingValueFiles | default true }}
      valueFiles: {{ include "chart-library.valueFiles" (dict "app" (merge $app (dict "cluster" $cluster "cloud" $cloud "valuesDir" ($paths.values | default "values"))) "ctx" $) | nindent 8 }}
      {{- with .helmValues }}
      values: |- {{ toYaml . | nindent 8 }}
      {{- end }}
  {{- end }}
  syncPolicy: {{ include "chart-library.syncPolicy" (dict "syncPolicy" .syncPolicy "defaults" $defaults) | nindent 4 }}
{{- end }}
{{- end }}
{{- end }}


{{/*
=============================================================================
Single Application Spec (for embedding in other templates)
Returns just the application spec without apiVersion/kind wrapper
Usage: {{ include "chart-library.application.spec" $appContext }}
=============================================================================
*/}}

{{- define "chart-library.application.spec" -}}
{{- $multiSource := eq (toString (.multiSource | default false)) "true" -}}
metadata:
  name: {{ required "name is required" .name | quote }}
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
    namespace: {{ .namespace | quote }}
  {{- if $multiSource }}
  sources:
    - repoURL: {{ required "chartRepoURL is required for multi-source" .chartRepoURL | quote }}
      chart: {{ .chartName | quote }}
      targetRevision: {{ .chartVersion | default "1.0.0" | quote }}
      helm:
        {{- with .releaseName }}
        releaseName: {{ . | quote }}
        {{- end }}
        ignoreMissingValueFiles: {{ .ignoreMissingValueFiles | default true }}
        valueFiles: {{ include "chart-library.valueFiles" (dict "app" . "ctx" .ctx "prefix" "$values") | nindent 10 }}
        {{- with .helmValues }}
        values: |- {{ toYaml . | nindent 10 }}
        {{- end }}
    - repoURL: {{ required "repoURL is required" .repoURL | quote }}
      targetRevision: {{ .targetRevision | default "HEAD" | quote }}
      {{- if .recurseSubmodules }}
      directory:
        recurse: true
      {{- end }}
      ref: values
  {{- else }}
  source:
    repoURL: {{ required "repoURL is required" .repoURL | quote }}
    path: {{ required "path is required for single-source" .path | quote }}
    targetRevision: {{ .targetRevision | default "HEAD" | quote }}
    {{- if .recurseSubmodules }}
    directory:
      recurse: true
    {{- end }}
    helm:
      {{- with .releaseName }}
      releaseName: {{ . | quote }}
      {{- end }}
      ignoreMissingValueFiles: {{ .ignoreMissingValueFiles | default true }}
      valueFiles: {{ include "chart-library.valueFiles" (dict "app" . "ctx" .ctx) | nindent 8 }}
      {{- with .helmValues }}
      values: |- {{ toYaml . | nindent 8 }}
      {{- end }}
  {{- end }}
  syncPolicy: {{ include "chart-library.syncPolicy" (dict "syncPolicy" .syncPolicy "defaults" dict) | nindent 4 }}
{{- end }}


{{/*
=============================================================================
Backwards compatibility aliases
=============================================================================
*/}}

{{- define "chart-library.application.syncPolicy" -}}
{{- include "chart-library.syncPolicy" . -}}
{{- end }}

{{- define "chart-library.application.defaultSyncPolicy" -}}
{{- include "chart-library.syncPolicy" . -}}
{{- end }}
