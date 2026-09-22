# Stage 7 — Concepts

Every idea [`README.md`](README.md) relies on, defined once. Each section answers **what it is**, **how it runs
here**, and **what breaks without it**. Bounds, the trigger, the fallback and the windows are in
[design §4.5](../eks-sre-llmops-design.md#45-autoscaling-and-load-testing).

---

## 1. Scaling on the signal that tracks demand

**What it is.** An autoscaler adds replicas when a metric crosses a target. The metric has to rise when the service
struggles — otherwise the autoscaler is watching something else.

**How it runs here.** The api's requests spend almost all their time waiting on remote APIs, so CPU hardly moves under
load. The metric is requests currently in flight, averaged per pod, which grows exactly when work queues.

**What breaks with the wrong signal.** A CPU-based autoscaler on an I/O-bound service sits at low utilisation while
requests pile up. It never scales, and the dashboard says the service is under-used.

---

## 2. KEDA and the HPA underneath

**What it is.** The *Horizontal Pod Autoscaler* is Kubernetes' replica controller: on each sync it reads a metric,
compares it with a target and sets the replica count. *KEDA* creates and owns that HPA from a `ScaledObject`, and serves
it metrics from external sources — here, a Prometheus query — on demand.

**How it runs here.** One ScaledObject targets the api's Rollout. Between non-zero replica counts, the HPA's own sync
drives scaling, pulling the metric from KEDA when it needs it. KEDA's own polling and cooldown govern activation and
scaling to and from zero, which this service never does.

**What breaks without knowing there are two layers.** Settings are tuned in the wrong place. KEDA's cooldown and polling
interval look like the knobs for how fast replicas change; with a non-zero minimum, they are not.

---

## 3. Little's law

**What it is.** In a stable system, the average number of requests in progress equals the arrival rate times the
*average* time each spends inside: *L = λ × W*.

**How it runs here.** Stage 4's capacity run reads in-flight per pod directly from the gauge at the knee. Little's law,
with the mean latency — not the p95 — is the cross-check that the reading is consistent with the rate and latency
measured at the same moment.

**What breaks without it.** A threshold picked by feel, or one computed from the wrong latency: the p95 in place of the
mean overstates how many requests a pod holds. And at the edge of a rising ramp the system is not quite steady, so the
cross-check is approximate — which is why the gauge, not the formula, is the primary reading.

---

## 4. A control loop and its delays

**What it is.** A *control loop* measures, decides and acts, then measures again. Each step takes time; the total is how
late the action arrives after the change that called for it.

**How it runs here.** The gauge is scraped periodically; the HPA syncs on its own interval and asks KEDA for the value;
a new pod starts, loads its index, passes its readiness probe and is registered by the load balancer.

**What breaks without allowing for the delay.** Load keeps climbing during every step. A threshold at the point of
failure means capacity always arrives after it was needed; the margin below the knee is what buys the time. And if the
measurement itself competes with the load for the same resources, it arrives later still — or not at all.

---

## 5. Scale-down and the stabilisation window

**What it is.** The HPA does not remove replicas the moment the metric falls. It waits out a *stabilisation window*,
acting on the highest recommendation seen during it, so a dip does not shrink the service just before the next spike.

**How it runs here.** The window is set explicitly on the ScaledObject and passed to the HPA. Nodes have their own,
separate clock: the node autoscaler removes a node only after it has been unneeded for a while, not soon after a
scale-up, and not while it holds a pod that has not been marked safe to evict.

**What breaks without it.** Replicas flap — removed on every lull, re-added on every rise, each time paying the full
start-up delay. Or the wrong setting is tuned and the scale-down that follows is misread.

---

## 6. What happens when the metric disappears

**What it is.** A Prometheus query that finds no series returns an empty result, and an autoscaler has to decide what
that means. If errors persist, KEDA can substitute a *fallback* — a replica count, applied in a way its configuration
chooses.

**How it runs here.** An empty result is an error, during which the HPA holds its replicas. After repeated errors the
fallback keeps whichever is higher, the current count or the fallback count. The metric is a per-pod average, the only
kind for which KEDA's fallback works.

**What breaks with the defaults.** Empty read as zero scales the service to its minimum during a monitoring failure —
possibly at peak. And a fallback that sets a fixed count scales *down* to it as readily as up, which turns a hold into a
cut.

---

## 7. Pods and nodes: two autoscalers

**What it is.** Pod autoscaling adds pods; it cannot add machines. A pod whose *resource requests* fit on no node stays
`Pending`. The *Cluster Autoscaler* watches for such pods and grows the node group, and shrinks it when nodes' requested
capacity sits largely unused. A managed node group's bounds are limits for it to move within; on their own they change
nothing.

**How it runs here.** The Cluster Autoscaler manages the one node group. The api's requests come from what a pod used at
the capacity knee, so whether nodes ever need adding is itself a result.

**What breaks without it.** The group stays at its desired size and every pod beyond it waits for ever — while the replica
count still rises, so the pod autoscaler looks as if it worked. And with requests set too small, the node autoscaler is
installed and never acts.

---

## 8. Scaling during a canary

**What it is.** When the scaled object is a Rollout mid-canary, the canary's ReplicaSet is sized to its weight times the
replica count, and the stable ReplicaSet stays at full size so that an abort can return all traffic at once.

**How it runs here.** Traffic is split by load-balancer weight, so the canary's share of requests does not change when the
replica count does. The number of pods — and of requested resources — is temporarily larger than the replica count.

**What breaks without knowing it.** Capacity planning that counts replicas undercounts pods during every release, and a
scale-out mid-canary asks for more nodes than expected. New pods of both versions also start inside the analysis window,
with cold starts that the latency ratio can see.

---

[README](README.md) · [Design §4.5](../eks-sre-llmops-design.md#45-autoscaling-and-load-testing)
