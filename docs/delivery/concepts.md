# Stage 5 — Concepts

Every idea [`README.md`](README.md) relies on, defined once. Each section answers **what it is**, **how it runs
here**, and **what breaks without it**. Steps, thresholds, the window and the drill rate are in
[design §4.4](../eks-sre-llmops-design.md#44-progressive-delivery-argo-rollouts).

---

## 1. A Rollout instead of a Deployment

**What it is.** A `Rollout` is Argo Rollouts' replacement for a Deployment. It manages the same ReplicaSets, but
instead of replacing pods as fast as possible it follows a written strategy — steps, pauses and analyses — and can
stop or reverse itself.

**How it runs here.** From this stage the api is a Rollout. Before it, the api was a Deployment; the kind arrives with
the controller that understands it.

**What breaks without it.** A Deployment's rolling update only knows whether pods are Ready. A version that starts
cleanly and then fails a share of its requests is, to a Deployment, a successful release.

---

## 2. Canary steps and traffic weights

**What it is.** A *canary* runs the new version beside the old and sends it a share of traffic. *Steps* say how the
share grows and when to stop and check. With a traffic router, the share is set at the load balancer as weights
between two target groups, independent of how many pods each version has.

**How it runs here.** Argo Rollouts decides the weight at each step and writes it into the public Ingress; the load
balancer controller applies it to the listener.

**What breaks without a router.** The split follows pod counts: one new pod beside two old ones takes a third of the
traffic whatever the step says. The share becomes a side effect of scaling instead of a decision.

---

## 3. An AnalysisRun, and its three outcomes

**What it is.** An *AnalysisTemplate* defines measurements — a query, how often, how many times — and conditions for
success and failure. An *AnalysisRun* executes it during a rollout. A measurement is **successful**, **failed**, or,
when it meets neither condition, **inconclusive**. It can also **error**, when its query or condition cannot be
evaluated at all.

**How it runs here.** The traffic guard is written so that too few requests meets neither condition, making it
inconclusive, and an inconclusive run pauses the rollout. An empty result is declared inconclusive explicitly, so a
vanished canary pauses instead of erroring.

**What breaks without the third outcome.** Thin evidence must become a pass or a fail. As a pass, a canary that saw
four requests is promoted on nothing. As a fail, every quiet hour aborts a healthy release. And without the explicit
rule for empty results, repeated errors fail the run and abort the release on what was really a capacity event.

---

## 4. The pod-template-hash, and getting it onto a series

**What it is.** Each ReplicaSet a Rollout creates stamps its pods with a `rollouts-pod-template-hash` label, unique to
that version's pod template. It is how the stable and canary Services select their pods — and the only thing that
separates the two versions' metrics.

**How it runs here.** The PodMonitor copies that pod label onto every series it collects. The success-rate query
filters on the canary's hash; the latency ratio reads both.

**What breaks without it.** A pod label is not a metric label unless the scrape copies it. Without the copy, every
filtered query is empty from the first probe; each measurement errors and every release aborts — loudly, and blamed on
the release. The tempting fix, making empty count as zero, turns that into a gate that can never fail.

---

## 5. A query window and the scrape interval

**What it is.** `rate()` over a window estimates how fast a counter grew, from the samples inside that window. It needs
at least two. Prometheus takes one sample per target at every scrape interval.

**How it runs here.** The window spans several scrape intervals, so every probe has enough samples, and the probes are
spaced more closely than the window, so consecutive probes overlap.

**What breaks with a window equal to the scrape interval.** It often holds a single sample, and the rate over it is
empty. The measurement then errors on a busy, healthy canary, and the fault is in the arithmetic, not the release.

---

## 6. A relative gate

**What it is.** A gate that compares the new version with the old — *is the canary's p95 more than some ratio of the
stable version's?* — rather than with a fixed number.

**How it runs here.** The latency gate is the ratio of the two versions' estimated p95s, over the same window, in the
same mode.

**Why relative.** An absolute threshold means something only in the mode it was measured in. A ratio means the same in
either, and cancels what affects both versions at once, such as a slow afternoon at the provider. It does not cancel
what affects only one: at a small share the canary is a single pod on a single node, and that node's troubles are the
canary's alone.

**What breaks without understanding its resolution.** Each p95 is *estimated* from histogram buckets. When the stable
estimate sits just below a bucket edge and the ratio's limit falls just above it, the canary's estimate cannot reach
the limit until far more than the stated regression has happened. The written ratio and the effective ratio can be
very different numbers.

---

## 7. The resolution of a threshold

**What it is.** A threshold can only be as fine as the measurement under it. A percentage over *n* requests moves in
steps of 1/*n*; a latency estimated from buckets moves in steps set by where the bucket edges are.

**How it runs here.** The drill's rate gives each window a few hundred canary requests, so a 99% floor tolerates a
couple of stray errors and still fails on a real fault. Because probes overlap, one error is seen by several probes in
a row — which is why the window has to be large enough to absorb it.

**What breaks without enough resolution.** Over sixty requests a single error is below 99%, several overlapping probes
see it, and a healthy release aborts at random. A gate that does that gets switched off, after which it catches
nothing.

---

## 8. Abort, and what Git says afterwards

**What it is.** When an analysis fails, the Rollout *aborts*: the canary is scaled down and all traffic returns to the
stable version. The Rollout's spec — and therefore Git — still names the new version.

**How it runs here.** Argo CD shows the Application as synced but **Degraded**. Nothing retries automatically. The
state ends when Git changes — reverted or fixed.

**What breaks if it is misread.** Syncing again does nothing, because nothing is out of sync. Pushing the rollout
through by hand clears Degraded and ships the version the analysis rejected, without anyone deciding it was fine. The
disagreement is the signal, and it is meant to be resolved in Git.

---

## 9. Fault injection that actually injects

**What it is.** Deliberately making a version fail, to prove the system reacts — with the injection itself verified, or
the drill proves nothing.

**How it runs here.** The api runs in fake mode for every drill. The rollback drill's version adds a fault rate, which
only the fake provider honours, and the canary's error rate is checked to be above zero before the abort is trusted.

**What breaks without the check.** A fault rate on a real-model version does nothing. The canary stays healthy, the
analysis passes, the version is promoted — and the drill is recorded as proof that rollback works.

---

[README](README.md) · [Design §4.4](../eks-sre-llmops-design.md#44-progressive-delivery-argo-rollouts)
