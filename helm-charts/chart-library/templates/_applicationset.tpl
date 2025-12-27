{{/*
=============================================================================
ApplicationSet Template
Generates ArgoCD ApplicationSet resources
Usage: {{ include "chart-library.applicationset" . }}
=============================================================================
*/}}

{{- define "chart-library.applicationset" -}}
{{- $defaults := .Values.defaults | default dict -}}
{{- $paths := .Values.paths | default dict -}}
{{- $repo := .Values.repo | default dict -}}
{{- $chart := .Values.chart | default dict -}}
{{- $generator := .Values.generator | default dict -}}
{{- $segments := $generator.segments | default dict -}}
{{- $cluster := include "chart-library.clusterName" . -}}
{{- $cloud := include "chart-library.cloud" . -}}
{{- $valuesDir := $paths.values | default "values" -}}
{{- $chartsDir := $paths.charts | default "helm-charts" -}}

{{- range $appSetKey, $appSet := .Values.appSets }}
{{- if $appSet.enabled }}
{{- $appSetName := include "chart-library.normalizeName" $appSetKey -}}
{{- $multiSource := $appSet.multiSource | default $defaults.multiSource | default false -}}
{{- $repoURL := $appSet.repoURL | default $repo.url | required "repo.url is required" -}}
{{- $revision := $appSet.revision | default $repo.revision | default "HEAD" -}}
{{- $pathPattern := $appSet.pathPattern | default (printf "%s/%s/%s/*/*/*.yaml" $valuesDir $cluster $appSetName) -}}

{{- /* Go template expressions for dynamic app generation */ -}}
{{- $goTpl := include "chart-library.appSetGoTpl" (dict "segments" $segments) | fromYaml -}}

{{- /* Build value files using helper */ -}}
{{- $valueFilesArgs := dict
    "appSet" $appSet
    "paths" $paths
    "cluster" $cluster
    "cloud" $cloud
    "appSetName" $appSetName
    "goTpl" $goTpl
    "ctx" $
-}}
---
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: {{ $appSetName | quote }}
  namespace: {{ $defaults.argocdNamespace | default "argocd" | quote }}
  {{- if or $defaults.parentInstance $appSet.labels }}
  labels:
    {{- with $defaults.parentInstance }}
    argocd.argoproj.io/instance: {{ . | quote }}
    {{- end }}
    {{- with $appSet.labels }}
    {{- toYaml . | nindent 4 }}
    {{- end }}
  {{- end }}
  {{- with $appSet.annotations }}
  annotations: {{ toYaml . | nindent 4 }}
  {{- end }}
spec:
  syncPolicy:
    preserveResourcesOnDeletion: {{ $appSet.preserveResourcesOnDeletion | default false }}
  goTemplate: true
  generators:
    - git:
        repoURL: {{ $repoURL | quote }}
        revision: {{ $revision | quote }}
        files:
          - path: {{ $pathPattern | quote }}
        {{- if $multiSource }}
        values:
          chartVersion: {{ $appSet.chartVersion | default $chart.version | default "1.0.0" | quote }}
        {{- end }}
  template:
    metadata:
      name: {{ $goTpl.appName | quote }}
      namespace: {{ $defaults.argocdNamespace | default "argocd" | quote }}
      {{- if not $appSet.preserveResourcesOnDeletion }}
      finalizers:
        - resources-finalizer.argocd.argoproj.io
      {{- end }}
      labels:
        appset: {{ $appSetName }}
    spec:
      project: {{ $appSet.project | default $defaults.project | default "default" | quote }}
      destination:
        server: {{ $appSet.server | default $defaults.server | default "https://kubernetes.default.svc" | quote }}
        namespace: {{ $goTpl.namespace | quote }}
      {{- if $multiSource }}
      sources:
        - repoURL: {{ $appSet.chartRepoURL | default $chart.repoURL | required "chart.repoURL is required for multi-source" | quote }}
          chart: {{ $goTpl.chartName | quote }}
          targetRevision: {{ printf "{{ .chartVersion | default \"%s\" }}" ($appSet.chartVersion | default $chart.version | default "1.0.0") | quote }}
          helm:
            releaseName: {{ $goTpl.releaseName | quote }}
            ignoreMissingValueFiles: {{ $appSet.ignoreMissingValueFiles | default $defaults.ignoreMissingValueFiles | default true }}
            valueFiles: {{ include "chart-library.appSetValueFiles" (merge $valueFilesArgs (dict "prefix" "$values")) | nindent 14 }}
        - repoURL: {{ $repoURL | quote }}
          targetRevision: {{ printf "{{ .sourceTargetRevision | default \"%s\" }}" $revision | quote }}
          {{- if ($appSet.recurseSubmodules | default $defaults.recurseSubmodules | default false) }}
          directory:
            recurse: true
          {{- end }}
          ref: values
      {{- else }}
      source:
        repoURL: {{ $repoURL | quote }}
        path: {{ printf "%s/%s" $chartsDir $goTpl.chartName | quote }}
        targetRevision: {{ printf "{{ .sourceTargetRevision | default \"%s\" }}" $revision | quote }}
        {{- if ($appSet.recurseSubmodules | default $defaults.recurseSubmodules | default false) }}
        directory:
          recurse: true
        {{- end }}
        helm:
          releaseName: {{ $goTpl.releaseName | quote }}
          ignoreMissingValueFiles: {{ $appSet.ignoreMissingValueFiles | default $defaults.ignoreMissingValueFiles | default true }}
          valueFiles: {{ include "chart-library.appSetValueFiles" $valueFilesArgs | nindent 12 }}
      {{- end }}
      syncPolicy:
        automated:
          prune: true
          selfHeal: true
        syncOptions:
          - FailOnSharedResource=true
          - ApplyOutOfSyncOnly=true
          - CreateNamespace=true
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
