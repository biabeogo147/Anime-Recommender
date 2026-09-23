# Stage 7 — Guide: pods, then nodes, and both come back

Commands and checks only. The reasoning is in the comments of these files:
- `deploy/charts/anime-api/templates/scaledobject.yaml`, and `_pod.tpl` (preStop, grace period, safe-to-evict);
- `deploy/charts/anime-api/values.yaml` (`scaling:`, `resources:`);
- `deploy/argocd/root/templates/scaling.yaml` (KEDA, Cluster Autoscaler) and `app.yaml` (the replica count left to
  the HPA);
- `infra/terraform/cluster/pod-identity.tf` (the Cluster Autoscaler's role) and `eks.tf` (the node group, 2 to 4);
- [README](README.md) · [concepts](concepts.md).

The "Scaling A…" references are answers in [answers.md](answers.md).

Machines: **laptop** (git, browser), **ops** (inside tmux; start each block with
`cd ~/Anime-Recommender && export KUBECONFIG=$HOME/.kube/anime`). The run takes about **50 minutes**: 18 minutes of
load, then 30 for pods and nodes to come back.

Criterion ([design §6](../eks-sre-llmops-design.md#6-verification-and-evidence-definition-of-done)):
- **#14:** under `ramp.js`, replicas move from 2 toward 8 and nodes from 2 toward 4, and both come back. The evidence
  is replicas and nodes over time, the trigger's value, the pod and node scale-out delays, and the scale-down timed
  against the HPA's window. It is closed only if nodes move too. If eight pods fit on two nodes, it is recorded as
  **"pods: pass; nodes: not exercised"**, never as a full pass (Scaling A4.3).

---

## 0. The numbers from stage 4, into Git — ops, laptop

**0.1 — fake mode first.** The values change in 0.2 is a new pod template, so it is a canary, and a canary is judged
on traffic. In real mode that traffic would spend the provider's quota and money. Switch with **only the first block** of
[stage 5, section 2](../5-delivery/guide.md#2-fake-mode-for-the-drills--ops), then start steady traffic in window 3 (k6; window 2 holds the tunnel) and
leave it running until the end of 0.3:

```bash
cd ~/Anime-Recommender && DURATION=90m make loadtest-steady
```

**0.2 — report three readings from stage 4, 3.4:** in-flight per pod at the knee, and CPU and memory per pod at the
knee. I write them into `deploy/charts/anime-api/values.yaml` and commit on a branch; you push it and open a pull
request, and merge it once `ci-ok` is green (`main` takes changes only through a pull request, stage 3). Until then
the chart refuses to render the ScaledObject.
- `scaling.inFlightTarget`: below the knee's in-flight per pod, so scaling starts before the knee (Scaling A3.2).
  The rule used is about **70%** of it, rounded down. It is written in the evidence with the knee value.
- `resources.requests`: CPU and memory at the knee, rounded up a little. They are not inflated to make nodes appear.
  If the memory request comes out above 1 Gi, `limits.memory` is raised with it; a request above its limit is
  refused.

**0.3 — ops: wait for both releases.** The merge is a new commit, so CI also releases new image digests a few minutes
later: two canaries in a row, both judged under the running traffic. Wait until both are done, so no release rolls
pods during the run.

```bash
cd ~/Anime-Recommender && export KUBECONFIG=$HOME/.kube/anime
# Done when main's newest commit is CI's release commit AND the Rollout has finished walking it.
for i in $(seq 80); do
  git fetch -q origin
  git log -1 --format=%s origin/main | grep -q '^release:' && make -s rollout-status | grep -q 'phase=Healthy' && break
  sleep 30
done
git pull -q --ff-only; git log --oneline -3
kubectl -n anime get rollout anime-api -o jsonpath='requests: {.spec.template.spec.containers[0].resources.requests}{"\n"}'
make -s rollout-status
```

Expected: the last commit is CI's `release:` commit, the requests are the new values, and `phase=Healthy` with
`stable` equal to `latest`. Then stop k6 in window 3 (`Ctrl-c`).

---

## 1. Switch the stage on — ops

```bash
cd ~/Anime-Recommender && export KUBECONFIG=$HOME/.kube/anime
grep -nE '^    keda:|^    clusterAutoscaler:|clusterAutoscalerImageTag:' deploy/argocd/root/values.yaml
grep -A5 '^scaling:' deploy/charts/anime-api/values.yaml
F=infra/terraform/bootstrap/terraform.tfvars
sed -i 's/^enabled_stages .*/enabled_stages            = ["gitops", "load", "delivery", "slo", "scaling"]/' $F
grep '^enabled_stages' $F
make bootstrap-plan && make bootstrap
kubectl -n argocd annotate application root argocd.argoproj.io/refresh=hard --overwrite
for i in $(seq 40); do
  s=$(kubectl -n anime get scaledobject anime-api -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null)
  [ "$s" = True ] && break; sleep 15
done; echo "ScaledObject Ready: $s"
make -s apps
```

Expected:
- two chart versions and an image tag `v1.36.x`, none `PIN_ME`;
- `inFlightTarget` is a number, not `MEASURE_IN_STAGE_4`;
- `Plan: 0 to add, 1 to change`;
- `ScaledObject Ready: True`;
- the list gains `keda` and `cluster-autoscaler`, and every Application is `Synced`/`Healthy`.

---

## 2. Wired as intended, before any load — ops

Every output in this section is saved; section 4 reports it.

**2.1 — the HPA KEDA made, and what it reads.**

```bash
cd ~/Anime-Recommender && export KUBECONFIG=$HOME/.kube/anime
{
kubectl -n anime get hpa keda-hpa-anime-api -o jsonpath='target={.spec.scaleTargetRef.kind}/{.spec.scaleTargetRef.name} min={.spec.minReplicas} max={.spec.maxReplicas} down-window={.spec.behavior.scaleDown.stabilizationWindowSeconds}s{"\n"}'
kubectl -n anime get hpa keda-hpa-anime-api -o jsonpath='{range .status.currentMetrics[*]}metric now: {.external.current.averageValue}{"\n"}{end}'
kubectl -n anime get scaledobject anime-api -o jsonpath='ignoreNullValues={.spec.triggers[0].metadata.ignoreNullValues} fallback={.spec.fallback.behavior} threshold={.spec.triggers[0].metadata.threshold}{"\n"}'
kubectl -n anime get rollout anime-api -o jsonpath='rollout replicas={.spec.replicas}{"\n"}'
} | tee ~/anime-evidence/scaling-wiring.txt
```

Expected:
- `target=Rollout/anime-api min=2 max=8 down-window=300s`;
- a current metric value, a small number with no load. Quantities print like `0` or `500m` (0.5); that is a value,
  not an error;
- `ignoreNullValues=false fallback=currentReplicasIfHigher threshold=<your number>`;
- `rollout replicas=2`.

**2.2 — the replica count is the HPA's, and Argo CD leaves it alone.** The next section's scale-out would otherwise be
undone by self-heal within seconds (Scaling A7.2).

```bash
cd ~/Anime-Recommender && export KUBECONFIG=$HOME/.kube/anime
kubectl -n argocd get application anime-api -o jsonpath='{range .spec.ignoreDifferences[*]}{.kind} {.jsonPointers}{"\n"}{end}' \
  | tee -a ~/anime-evidence/scaling-wiring.txt
```

Expected: an `Ingress` line with the weights annotation, and `Rollout ["/spec/replicas"]`.

**2.3 — the Cluster Autoscaler found the node group, with its bounds.** It logs the Auto Scaling group once at
startup, and its bounds on every cache refresh; the whole log is read, not its tail.

```bash
cd ~/Anime-Recommender && export KUBECONFIG=$HOME/.kube/anime
CA=$(kubectl -n kube-system get pods -l app.kubernetes.io/name=aws-cluster-autoscaler -o name | head -1)
{
kubectl -n kube-system logs $CA | grep -E 'Registering ASG|min/max/current|AccessDenied' | tail -3
kubectl -n kube-system get ${CA} -o jsonpath='image={.spec.containers[0].image}{"\n"}'
kubectl version -o json | jq -r '"server=\(.serverVersion.gitVersion)"'
kubectl get nodes -L node.kubernetes.io/instance-type,topology.kubernetes.io/zone
} | tee -a ~/anime-evidence/scaling-wiring.txt
```

Expected:
- a `Registering ASG` line and a `min/max/current is 2/4/2` line, and no `AccessDenied`;
- the image's minor version equals the server's (`v1.36.x` and `v1.36.x`);
- two nodes, preferably in two zones.

**2.4 — predict the node half before the run.** The scheduler and the autoscaler decide by requests, not use. If eight
api pods and one canary's worth fit in what two nodes have left, no pod will go Pending, and nodes will not move.

```bash
cd ~/Anime-Recommender && export KUBECONFIG=$HOME/.kube/anime
{
kubectl describe nodes | grep -A6 'Allocated resources' | grep -E 'Name:|cpu|memory'
kubectl get nodes -o jsonpath='{range .items[*]}{.metadata.name} allocatable cpu={.status.allocatable.cpu} memory={.status.allocatable.memory}{"\n"}{end}'
kubectl -n anime get rollout anime-api -o jsonpath='api pod requests: {.spec.template.spec.containers[0].resources.requests}{"\n"}'
} | tee ~/anime-evidence/scaling-prediction.txt
```

Write the prediction down beside the numbers: the free CPU and memory on the two nodes, against six more api pods at
their requests. **Fits** means the node half will not be exercised. That is recorded as it is, not forced.

---

## 3. Criterion #14 — the run — ops

**3.1 — a recorder.** The api is in fake mode since 0.1. In window 4 (`Ctrl-b c`), start a recorder that prints one
line every 15 s for the whole run. It is what you watch live; the numbers reported come from Prometheus afterwards
(3.4).

```bash
cd ~/Anime-Recommender && export KUBECONFIG=$HOME/.kube/anime
while true; do
  r=$(kubectl -n anime get rollout anime-api -o jsonpath='{.spec.replicas}/{.status.availableReplicas}')
  p=$(kubectl -n anime get pods -l app=anime-api --field-selector=status.phase=Pending -o name | wc -l)
  n=$(kubectl get nodes --no-headers | awk '$2=="Ready"' | wc -l)
  m=$(kubectl -n anime get hpa keda-hpa-anime-api -o jsonpath='{.status.currentMetrics[0].external.current.averageValue}')
  echo "$(date -u +%T) replicas(desired/available)=$r pending=$p nodes-ready=$n in-flight-per-pod=$m"
  sleep 15
done | tee ~/anime-evidence/scaling-live.txt
```

**3.2 — the load.** First, in window 1, the gate: no release in progress, and no other traffic.

```bash
cd ~/Anime-Recommender && export KUBECONFIG=$HOME/.kube/anime
make -s rollout-status
make -s prom Q='sum(rate(anime_http_requests_total{route="/recommend"}[2m]))'
```

Expected: `phase=Healthy` with `stable` equal to `latest`, and a request rate near `0`.

Then, in window 3: the same ramp as stage 4, with the top held for ten minutes, because a new node takes minutes. The
top rate must be **above** what two pods sustain, or nothing needs to scale: about three times stage 4's capacity.
`MAX_VUS` follows Little's law with room to spare: the rate times a queued latency of about 10 s. The ramp target
overwrites stage 4's `ramp*` files, so they are copied aside first. **Replace `CAP=` with stage 4's capacity before
running.**

```bash
cd ~/Anime-Recommender && mkdir -p ~/anime-evidence/stage4-ramp && cp -n ~/anime-evidence/ramp* ~/anime-evidence/stage4-ramp/ || true
CAP=40   # ← stage 4's capacity, in requests per second
MAX_RPS=$((3*CAP)) MAX_VUS=$((30*CAP)) HOLD=10m make loadtest-ramp
```

Expected in window 4, over the next 18 minutes:
- in-flight per pod rises past the threshold;
- desired replicas climb above 2 within about a minute, up to at most 8;
- if the new pods do not fit, `pending` becomes non-zero, and a few minutes later `nodes-ready` rises, up to at most 4.

**As soon as k6 finishes**, in window 1, save the events: the cluster keeps them for about an hour only.

```bash
cd ~/Anime-Recommender && export KUBECONFIG=$HOME/.kube/anime
{
echo "== HPA"; kubectl -n anime get events --field-selector involvedObject.name=keda-hpa-anime-api --sort-by=.lastTimestamp
echo "== pending pods"; kubectl -n anime get events --sort-by=.lastTimestamp | grep -E 'TriggeredScaleUp|NotTriggerScaleUp|FailedScheduling'
echo "== ScaledObject"; kubectl -n anime get scaledobject anime-api -o jsonpath='{.status.health}{"\n"}{range .status.conditions[*]}{.type}={.status} {.reason}{"\n"}{end}'
echo "== Cluster Autoscaler"; kubectl -n kube-system logs $(kubectl -n kube-system get pods -l app.kubernetes.io/name=aws-cluster-autoscaler -o name | head -1) \
  --since=30m | grep -iE 'scale-up|scale-down|backoff|failed to' | tail -30
} | tee ~/anime-evidence/scaling-events.txt
```

**3.3 — the return.** As soon as k6 finishes, keep a light load running in window 3 for the whole return, so that
scale-in happens under traffic and can be seen to drop requests or not (M5 in
[guide-measurements](../evidence/guide-measurements.md#m5--scaling-out-and-back)):

```bash
cd ~/Anime-Recommender && RPS=5 DURATION=30m make loadtest-steady
```

Leave window 4 running for the same **30 minutes**:
- replicas start falling after the 5-minute window, then one per minute: 8 to 2 in about 11 minutes;
- nodes fall after 10 minutes unneeded, and not within 10 minutes of the last scale-up.

Then stop the recorder (`Ctrl-c`). If a node stayed, list what is on it before anything else changes:

```bash
cd ~/Anime-Recommender && export KUBECONFIG=$HOME/.kube/anime
for n in $(kubectl get nodes -o name); do echo "== $n"; kubectl get pods -A -o wide --field-selector spec.nodeName=${n#node/} --no-headers | awk '{print $1"/"$2}'; done \
  | tee ~/anime-evidence/scaling-nodes-at-end.txt
kubectl -n kube-system get cm cluster-autoscaler-status -o jsonpath='{.data.status}' | tee -a ~/anime-evidence/scaling-nodes-at-end.txt
```

**3.4 — the evidence, from Prometheus.** The range covers the ramp and the 30 minutes after it.

```bash
cd ~/Anime-Recommender && export KUBECONFIG=$HOME/.kube/anime
S=$(cat ~/anime-evidence/ramp.start); E=$(date -u +%FT%TZ)
q() { make -s prom-range START=$S END=$E STEP=30s Q="$1" | grep '@\[' ; }
H='horizontalpodautoscaler="keda-hpa-anime-api",namespace="anime"'
echo "== trigger: in-flight, summed";     q 'sum(anime_http_requests_in_flight{job="anime/anime-api"})'                  | tee ~/anime-evidence/scaling-trigger.txt
echo "== HPA desired replicas";           q "max(kube_horizontalpodautoscaler_status_desired_replicas{$H})"                | tee ~/anime-evidence/scaling-desired.txt
echo "== ready api pods";                 q 'sum(kube_pod_status_ready{namespace="anime",pod=~"anime-api-.*",condition="true"})' | tee ~/anime-evidence/scaling-ready.txt
echo "== pending api pods";               q 'sum(kube_pod_status_phase{namespace="anime",pod=~"anime-api-.*",phase="Pending"}) or vector(0)' | tee ~/anime-evidence/scaling-pending.txt
echo "== ready nodes";                    q 'sum(kube_node_status_condition{condition="Ready",status="true"})'            | tee ~/anime-evidence/scaling-nodes.txt
echo "== p95 (s)";                        q 'histogram_quantile(0.95, sum by (le) (rate(anime_http_request_duration_seconds_bucket{route="/recommend"}[2m])))' | tee ~/anime-evidence/scaling-p95.txt
echo "== error ratio";                    q '(sum(rate(anime_http_requests_total{route="/recommend",status=~"5.."}[2m])) or vector(0)) / sum(rate(anime_http_requests_total{route="/recommend"}[2m]))' | tee ~/anime-evidence/scaling-errors.txt
jq -r '.metrics | "k6: dropped iterations \(.dropped_iterations.count // 0), vus max \(.vus_max.max // .vus_max.value)"' ~/anime-evidence/ramp-summary.json \
  | tee ~/anime-evidence/scaling-k6.txt
```

Read, in this order:
1. **The trigger moved first.** Desired replicas are `ceil(summed in-flight ÷ threshold)`, with a 10% tolerance, so
   the first rise comes once the sum passes about `2.2 × threshold`. The HPA events in `scaling-events.txt` name the
   metric behind each step. Ready pods rising while desired stays flat is a rollout adding canary pods, not the
   autoscaler; desired rising with no trigger rise is a manual scale or a bug (Scaling A8.1).
2. **Pod scale-out delay:** from the trigger crossing to the first extra ready pod.
3. **Node scale-out delay:** from the first pending pod to the first extra ready node. If `pending` stayed `0` all
   run, the node half was **not exercised**, as 2.4 predicted or not. Record it that way; do not raise the requests to
   force it (Scaling A4.3).
4. **The ceiling:** did replicas stop at 8, or below it with pods pending at 4 nodes? The run's plateau is then the
   cluster's, not the service's (Scaling A4.4).
5. **Scale-down:** replicas start falling about 5 minutes after the trigger fell (the HPA's window, 300 s), then one
   per minute. Nodes are removed at least 10 minutes after they became unneeded (Scaling A5.1, A5.2). Replicas that
   fell while the trigger series was empty would be the empty-query false pass: the ScaledObject's health and its
   `Fallback` condition in `scaling-events.txt` show whether KEDA saw query errors.
6. **Errors during scale-in:** the error ratio while replicas were falling. It should be at or near zero; the preStop
   wait and the deregistration delay exist for this.

**3.5 — back to real mode**, as in [stage 5, section 5](../5-delivery/guide.md#5-back-to-real-mode--ops).

---

## 4. Evidence

Report the files in `~/anime-evidence/` whose names start with `scaling`, the prediction from 2.4, and the six
readings from 3.4, with the threshold and requests from section 0. They become `docs/evidence/scaling.md`.

---

## Troubleshooting

| Symptom | Likely cause | What to do |
|---|---|---|
| `keda` or `cluster-autoscaler` ComparisonError | A chart version or the image tag is still `PIN_ME` | Section 1's first line; the pins round of stage 2 |
| `anime-api` ComparisonError: `scaling.inFlightTarget is still a placeholder` | 0.2 not merged | Report the numbers; merge; pull |
| `anime-api` ComparisonError: `switch delivery on first` | `scaling` without `delivery` in `enabled_stages` | The stages are cumulative |
| A canary starts during the run | A release landed: CI's release commit, or a values change | 0.3 and 3.2's gate; rerun the ramp after it finishes |
| `keda` stuck `OutOfSync` on CRDs | Client-side apply of large CRDs | `ServerSideApply=true` must be in its syncOptions (`scaling.yaml`) |
| ScaledObject `Ready` False, `ScaledObjectCheckFailed` | The query errors, or Prometheus is unreachable | `kubectl -n anime describe scaledobject anime-api`; the keda-operator log |
| HPA metric `<unknown>` | KEDA's metrics server is not answering | `kubectl get apiservice v1beta1.external.metrics.k8s.io`; `kubectl -n keda get pods` |
| Replicas jump back to 2 within seconds | Self-heal writing the chart's `replicas` | 2.2: the `Rollout /spec/replicas` ignore must be live |
| Replicas never exceed 2 under load | The threshold is above what a pod reaches, or the ramp too gentle | Compare the trigger with `2.2 × threshold`; raise `CAP` |
| Pods `Pending` and no new node | The autoscaler cannot act, or the pod would not fit any new node | `kubectl -n anime describe pod <pending>`: `TriggeredScaleUp` or `NotTriggerScaleUp`; the CA log for `AccessDenied`, `backoff`, `InsufficientInstanceCapacity` (Spot); the group at max 4 |
| 2.3 prints nothing | The Cluster Autoscaler logged its startup before a restart, or at another level | `kubectl -n kube-system logs <ca> --previous`; `kubectl -n kube-system get cm cluster-autoscaler-status -o yaml` |
| The Cluster Autoscaler errors on list or watch calls | Its minor version differs from the cluster's | 2.3's image and server lines; `pins.clusterAutoscalerImageTag` |
| Nodes never come back | A pod blocks the drain: an emptyDir pod without the safe-to-evict annotation (Prometheus, Tempo, Grafana, Argo CD's repo-server), a kube-system pod without a PDB, or the node is above half its requests | `scaling-nodes-at-end.txt`; the CA log `\| grep -i 'cannot be removed'`. Record it as the node half's result — do not evict Prometheus mid-run |
| Errors during scale-in | Requests still routed to a terminating pod | The target group's deregistration delay (`ingress.yaml`); a longer preStop wait |
| Dropped iterations early in the ramp | The generator, not the service | A larger `MAX_VUS`; the workstation's CPU (stage 4, 3.3) |

---

[README](README.md) · [Concepts](concepts.md) · [Design §4.5](../eks-sre-llmops-design.md#45-autoscaling-and-load-testing) ·
Previous: [SLO guide](../6-slo/guide.md)
