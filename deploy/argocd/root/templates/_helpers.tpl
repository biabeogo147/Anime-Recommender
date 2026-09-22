{{/*
The parts every child Application shares.

- resources-finalizer: deleting the Application deletes what it deployed; `make down` relies on it.
- automated + selfHeal: Git is the only way in; a hand edit is put back.
- retry: automated sync does NOT retry a failed sync of the same revision on its own. Without this, one transient failure
  on the first bootstrap — a webhook not serving yet, a CRD not established — leaves a child stuck, the health check never
  reports it Healthy+Synced, and every later wave waits for ever.
*/}}
{{- define "root.metadata" -}}
namespace: argocd
finalizers:
  - resources-finalizer.argocd.argoproj.io
{{- end -}}

{{- define "root.syncPolicy" -}}
syncPolicy:
  automated:
    prune: true
    selfHeal: true
  retry:
    limit: 10
    backoff:
      duration: 10s
      factor: 2
      maxDuration: 3m
  {{- with . }}
  syncOptions:
    {{- toYaml . | nindent 4 }}
  {{- end }}
{{- end -}}

{{/* The internal door: the annotations all four admin Ingresses must share EXACTLY — scheme, group, ports, certificate
and allowed ranges are group-wide, and members that disagree break reconciliation of the whole group. One definition,
used by every member, is what keeps them equal. */}}
{{- define "root.internalIngressAnnotations" -}}
alb.ingress.kubernetes.io/scheme: internal
alb.ingress.kubernetes.io/group.name: anime-internal
alb.ingress.kubernetes.io/target-type: ip
alb.ingress.kubernetes.io/listen-ports: '[{"HTTPS":443}]'
alb.ingress.kubernetes.io/certificate-arn: {{ .Values.pins.certificateArn | quote }}
alb.ingress.kubernetes.io/inbound-cidrs: {{ printf "%s,%s" .Values.network.vpcCidr .Values.network.vpnCidr | quote }}
{{- end -}}
