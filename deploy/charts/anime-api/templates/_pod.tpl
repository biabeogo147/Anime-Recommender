{{/*
The api's pod template, shared by the Deployment (stages 2-4) and the Rollout (stage 5 on), so switching the delivery
stage on changes the controller, not the pod. What the pod looks like is identical either way; only how a new version
reaches it differs.
*/}}
{{- define "anime-api.podTemplate" -}}
metadata:
  labels: { app: anime-api }
  annotations:
    # /tmp is an emptyDir, and the Cluster Autoscaler never removes a node holding a pod with local storage unless the
    # pod says it may be evicted. Nothing in /tmp outlives a pod anyway (Scaling A5.2).
    cluster-autoscaler.kubernetes.io/safe-to-evict-local-volumes: tmp
    {{- with .Values.drill }}
    # A drill's only change to the template. Any change to the template is a new version to the Rollout (a new
    # rollouts-pod-template-hash), so a promotion drill needs no new image: it bumps this value (docs/5-delivery/guide.md).
    anime.recruitai.io.vn/drill: {{ . | quote }}
    {{- end }}
spec:
  # Longer than the preStop wait plus the app's own shutdown, so the kubelet never kills a pod that is still draining.
  terminationGracePeriodSeconds: 45
  # One replica per node where possible, so a reclaimed Spot node usually takes one replica, not both. ScheduleAnyway:
  # when a node is missing or full the pod still starts, co-located, rather than staying Pending.
  topologySpreadConstraints:
    - maxSkew: 1
      topologyKey: kubernetes.io/hostname
      whenUnsatisfiable: ScheduleAnyway
      labelSelector:
        matchLabels: { app: anime-api }
  securityContext:
    runAsNonRoot: true
    runAsUser: 10001 # the image's own user (services/api/Dockerfile)
    seccompProfile: { type: RuntimeDefault }
  containers:
    - name: api
      image: "{{ .Values.image.repository }}@{{ .Values.image.digest }}"
      ports:
        - { name: http, containerPort: 8000 }
      # GOOGLE_API_KEY, OPENAI_API_KEY and HF_TOKEN: every key of anime/llm, from the Secret External Secrets writes
      # (deploy/platform/base). The provider in use reads its own key and ignores the other.
      envFrom:
        - secretRef: { name: anime-llm }
      env:
        - { name: LLM_PROVIDER, value: {{ .Values.llm.provider | quote }} }
        # The provider's own model. fake has none (the app names it "fake"), so it gets an empty value and the app's
        # default, which it does not use.
        - { name: MODEL_NAME, value: {{ index .Values.llm.models .Values.llm.provider | default "" | quote }} }
        - { name: FAULT_RATE, value: {{ .Values.llm.faultRate | quote }} }
        {{- if has "tracing" .Values.stages }}
        # Tracing (stage 8) is on only when the endpoint is set (src/anime/telemetry.py). The provider goes onto every
        # span as a RESOURCE attribute, from the same value as LLM_PROVIDER, so the collector can keep drill traffic
        # out of Langfuse by pod rather than by span (design §4.2).
        - { name: OTEL_EXPORTER_OTLP_ENDPOINT, value: "http://otel-collector.tracing.svc.cluster.local:4318" }
        - { name: OTEL_RESOURCE_ATTRIBUTES, value: {{ printf "anime.llm.provider=%s" .Values.llm.provider | quote }} }
        # Prompt and completion on the generation span. On for this single-operator demonstration; what users type
        # is copied to Langfuse, which the UI states (design §4.2).
        - { name: OTEL_CAPTURE_CONTENT, value: {{ .Values.tracing.captureContent | quote }} }
        {{- end }}
      # /healthz says "the process is alive" and stays 200 while the index loads; /readyz says "the index is loaded
      # and I can answer". So readiness is what keeps traffic off a loading pod, and liveness never kills a pod whose
      # load is merely retrying (docs/evidence/local.md, startup resilience). The startup probe only covers the
      # process coming up. The probes' handlers are async: they do not wait behind a saturated thread pool (design §4.1).
      startupProbe:
        httpGet: { path: /healthz, port: http }
        periodSeconds: 5
        failureThreshold: 24 # two minutes to start
      readinessProbe:
        httpGet: { path: /readyz, port: http }
        periodSeconds: 10
        timeoutSeconds: 3
      livenessProbe:
        httpGet: { path: /healthz, port: http }
        periodSeconds: 20
        timeoutSeconds: 3
        failureThreshold: 3
      # Scale-in must not drop requests. A terminating pod is removed from the ALB's target group, but the load balancer
      # controller and the ALB take seconds to stop sending to it. The wait keeps the pod serving through that; only
      # then does it receive SIGTERM (design §4.5). The target group's deregistration delay (30 s, ingress.yaml) is
      # set below the 45 s grace period.
      lifecycle:
        preStop:
          sleep: { seconds: 15 }
      resources: {{ toYaml .Values.resources | nindent 8 }}
      securityContext:
        allowPrivilegeEscalation: false
        readOnlyRootFilesystem: true
        capabilities: { drop: [ALL] }
      volumeMounts:
        - { name: tmp, mountPath: /tmp } # HOME and HF_HOME point here; the root filesystem is read-only
  volumes:
    - name: tmp
      emptyDir: {}
{{- end -}}
