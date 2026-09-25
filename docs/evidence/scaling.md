# Stage 7 — Scaling: evidence

Criterion **#14** — replicas and nodes follow the load — from the [scaling guide](../7-scaling/guide.md). Run
2026-09-23 in **fake mode**, so the figures describe the cluster rather than a model provider's quota.

Two independent autoscalers are under test, and they act in sequence:

| | What it adds | On what signal | How fast |
|---|---|---|---|
| **KEDA** → HPA | **pods** | in-flight requests per pod above **30** | seconds |
| **Cluster Autoscaler** | **nodes** | a pod that is `Pending` for want of room | minutes |

## The prediction, written before the run

From `kubectl describe nodes`, before any load:

- allocatable **1930m CPU** per node, two nodes;
- already requested: node 1 **1510m** (420m free), node 2 **840m** (1090m free); memory nowhere near binding
  (~9.9 GiB free);
- an api pod requests **250m / 256Mi**.

**Scheduling is per node, not pooled**, and that is the whole prediction: node 1's 420m takes **one** more pod and
its remaining 170m takes none; node 2's 1090m takes **four**. Five more pods fit, so **7 replicas fit on two nodes
and the 8th does not**.

The HPA had to reach 8 for that to be tested at all. At the ramp's top rate of 267 req/s and a fake-mode service
time of about 0.85 s, in-flight is about 227: **32.4 per pod at 7 replicas** (above the threshold of 30) and
**28.4 at 8** (below it), so the HPA should settle exactly at `maxReplicas`.

**Both halves held.** Measured at 7 replicas: **31 to 31.9** per pod. At 8: **27.7 to 28.9**. And the pod that
could not be placed was the 8th.

## Scale-out

The load is the stage 4 ramp with its top raised to **3 × capacity = 267 req/s** and held for ten minutes,
because a new node takes minutes to become schedulable. Timestamps are from the 15-second recorder, which polls
the API directly; the Prometheus series in `scaling-*.txt` agree within one scrape interval.

| Step | Time | Elapsed |
|---|---|---|
| Ramp starts | 13:21:57Z | — |
| In-flight per pod passes 30 (reaches 32) | 13:24:33Z | — |
| **HPA scales 2 → 3** | 13:24:52Z | **+19 s** |
| 3 → 4 → 5 → 6 → 7, one step per ~1 minute | 13:25:50 … 13:29:26Z | |
| **HPA reaches 8**, and one pod is `Pending` | 13:30:27Z | +5 m 35 s from the first step |
| **Cluster Autoscaler: node 3 `Ready`** | 13:31:07Z | **+40 s** from the pending pod |
| All 8 pods running, `pending` back to 0 | 13:31:27Z | **+60 s** from the pending pod |

The scheduler said exactly what the prediction did:

```
FailedScheduling  0/2 nodes are available: 2 Insufficient cpu
TriggeredScaleUp  pod triggered scale-up: [{eks-spot-…44d065e1 2->3 (max: 4)}]
```

**`Insufficient cpu`, not memory** — the constraint the arithmetic named.

Then, forty seconds later, a detail worth keeping:

```
FailedScheduling  0/3 nodes are available: 1 node(s) had untolerated taint(s), 2 Insufficient cpu
```

The third node **existed and still could not take the pod**: it carried an initialisation taint. That is why a
node takes minutes rather than seconds, and why the guide holds the top rate for ten minutes. A shorter ramp
would end while the node is still tainted, and the run would read as "the autoscaler did not react".

## What the users saw: nothing

Across **224,396 requests** at up to 267 req/s — nearly three times the 93.9 req/s two pods can serve:

| Reading | Value |
|---|---|
| Failed requests | **0** (k6), and the server-side error ratio is **0 at every point** |
| p95 over the whole ramp | **1.44 – 1.47 s** |
| p95 at low load in stage 4, for comparison | 1.43 – 1.45 s |
| k6 dropped iterations | **0** (`PRE_VUS=800`, peak use 340) |

Latency never moved. Stage 4's ramp, two fixed pods with no autoscaler, ended at a p95 of **15.6 s** — and it did
that at **120 req/s**, less than half the rate here ([load](load.md#the-two-runs)). Two pods at 267 req/s would
have been worse still. The queue never formed here because pods were added before it could. That is the criterion stated as a user would feel it: not "the cluster scaled",
but "the load tripled and nobody noticed".

## Scale-in

| Step | Time | Elapsed |
|---|---|---|
| Ramp ends, trigger falls to 0 | 13:40:02Z | — |
| Light load resumes at 5 req/s | 13:43:27Z | |
| **First decrease, 8 → 7** | 13:45:14Z | **+5 m 12 s** — the HPA's 300 s stabilisation window |
| 7 → 6 → 5 → 4 → 3, one step per ~58 s | 13:46:11 … 13:49:05Z | |
| **Back to `minReplicas` = 2** | 13:50:04Z | **10 m 02 s** from the load stopping |
| **Node 3 deleted** (`lastScaleDownDeleteTime`) | 13:56:37Z | **26 m 16 s** after it was added |
| Observed at two nodes | 13:56:45Z | |

The five minutes before the first decrease are the HPA doing nothing on purpose: a brief lull must not shrink a
cluster that is about to need the capacity again. The Cluster Autoscaler's own guard is longer and separate — it
will not remove a node within ten minutes of adding one — and the log shows it declining while the condition held:

```
Node ip-10-30-5-228  unremovable: cpu requested (91.19% of allocatable) is above the scale-down utilization threshold
Node ip-10-30-52-164 unremovable: cpu requested (95.34% of allocatable) is above the scale-down utilization threshold
scaleDownForbidden=false scaleDownInCooldown=false
```

**Out in 6 m 35 s, back in 10 m 02 s.** The asymmetry is the right way round: growing slowly costs users, shrinking
slowly costs only money.

### Scale-in dropped nothing

The return ran under a deliberate **5 req/s**, not in silence, so that removing pods and a node could be shown to
cost requests or not:

| Reading | Value |
|---|---|
| Requests during the return | **4,935** |
| Failed | **0** |
| Server-side error ratio through the scale-in | **0 at every point** |
| `available` ever below `desired` after 13:50 | **no** |

A scale-in measured with no traffic proves nothing — there is nobody to drop. This one was measured with callers
present.

One honest gap: the trigger series is **0 from 13:40:27 to 13:43:27**, between the ramp ending and the light load
starting. The scale-in itself began at 13:45:14, after traffic had resumed, so the measurement is unaffected — and
the HPA held at 8 through the silent gap rather than collapsing, which is the stabilisation window doing its job.

## The readings that make this a measurement rather than an anecdote

- **The trigger moved first.** `scaling-trigger.txt` rises from 0 to 249 before `scaling-desired.txt` leaves 2.
  Desired replicas rising with no trigger rise would be a manual scale or a bug; ready pods rising while desired
  stays flat would be a rollout adding canary pods, not the autoscaler.
- **KEDA read Prometheus successfully throughout**: `{"s0-prometheus":{"numberOfFailures":0,"status":"Happy"}}`,
  with `Fallback=False`. Replicas that moved while the trigger query returned nothing would be the empty-query
  false pass, and `ignoreNullValues=false` is what makes an empty query an error rather than a zero.
- **The ceiling was the service's, not the cluster's.** Replicas stopped at 8 because `maxReplicas` is 8 and the
  metric had settled below the threshold — not because pods were left pending at 4 nodes.
- **Argo CD did not fight the HPA.** `Rollout ["/spec/replicas"]` is in the Application's `ignoreDifferences`, so
  self-heal left the replica count where the autoscaler put it. Without it, Git says 2 and the scale-out is undone
  within seconds.

## #14: pass

| Placeholder | Value |
|---|---|
| `[PODS-MAX]` | **8** |
| `[NODES-MAX]` | **3** |
| `[ERR-SCALEIN]` | **0** |

## Notes for later

- **KEDA 2.20.2 logs that it has not been tested on Kubernetes 1.36.** Nothing misbehaved, and the HPA it created
  tracked the metric correctly throughout. Recorded as a known risk rather than a finding, and the first suspect
  if the HPA behaves oddly on a future run.
- **KEDA restarts itself once on install, by design.** The operator generates the webhook certificate, writes it to
  `kedaorg-certs`, and exits so the pod restarts with it — `Secrets have been updated; exiting so pod can be
  restarted`. During that window the admission webhook is `0/1` and the Application reads `Degraded`. It is the
  same problem as the load balancer controller's webhook CA in stage 2, solved the other way: KEDA writes the
  secret and then reloads, while that chart generates a fresh CA on every render and leaves the two out of step.
