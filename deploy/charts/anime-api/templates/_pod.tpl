{{/*
The api's pod template, shared by the Deployment (stages 2-4) and the Rollout (stage 5 on), so switching the delivery
stage on changes the controller, not the pod. What the pod looks like is identical either way; only how a new version
reaches it differs.
*/}}
{{- define "anime-api.podTemplate" -}}
metadata:
  labels: { app: anime-api }
  {{- with .Values.drill }}
  annotations:
    # A drill's only change to the template. Any change to the template is a new version to the Rollout (a new
    # rollouts-pod-template-hash), so a promotion drill needs no new image: it bumps this value (docs/delivery/guide.md).
    anime.recruitai.io.vn/drill: {{ . | quote }}
  {{- end }}
spec:
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
      # GOOGLE_API_KEY and HF_TOKEN, from the Secret External Secrets writes (deploy/platform/base).
      envFrom:
        - secretRef: { name: anime-llm }
      env:
        - { name: LLM_PROVIDER, value: {{ .Values.llm.provider | quote }} }
        - { name: MODEL_NAME, value: {{ .Values.llm.model | quote }} }
        - { name: FAULT_RATE, value: {{ .Values.llm.faultRate | quote }} }
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
