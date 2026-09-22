# Stage 4 — Concepts

Every idea [`README.md`](README.md) relies on, defined once. Each section answers **what it is**, **how it runs
here**, and **what breaks without it**. Scripts, rates and bucket values are in
[design §4.5](../eks-sre-llmops-design.md#45-autoscaling-and-load-testing) and
[§4.1](../eks-sre-llmops-design.md#41-the-application).

---

## 1. A histogram, and what a bucket boundary means

**What it is.** A Prometheus histogram does not store each request's latency. It keeps a counter per *bucket* —
how many requests took at most this long — labelled by the bucket's upper bound, `le`, plus a total count. The
counters are cumulative: each bucket includes everything in the smaller ones.

**How it runs here.** The api records every request into one latency histogram. The latency SLO is the ratio of the
counter at `le=T` to the total. Percentile *estimates*, used elsewhere, come from `histogram_quantile`, which
interpolates between boundaries.

**Why T must be a boundary.** The SLO asks for the counter *at* T. There is only a counter at a boundary; ask for
one between two and the selector matches no series at all, so the SLO is an empty result — not an estimate, not a
zero. See §8 for why that is the worst possible answer.

**What breaks without understanding it.** A target set by feel between two boundaries produces an SLO that is never
evaluated and never alerts, while looking, in the rules file, perfectly reasonable.

---

## 2. Percentiles, and how many samples they rest on

**What it is.** The 95th percentile is the value below which 95% of observations fall. It describes the slowest
twentieth — and is therefore decided by roughly a twentieth of the samples.

**How it runs here.** The baseline runs until a minimum number of requests has completed, so its p95 rests on a
ten tail samples rather than three.

**What breaks without enough samples.** Over sixty requests, the p95 sits around the third- or fourth-slowest one.
Each extra slow call shifts it by one rank, and when the neighbouring values straddle a bucket boundary, that one
call decides which bucket T lands in. Everything later that is judged against T inherits the luck.

---

## 3. Client-side and server-side latency

**What it is.** *Client-side* latency is measured by the sender. k6's request duration covers sending, waiting and
receiving on an already-open connection; it times DNS, connecting and the TLS handshake separately, and with
keep-alive those happen once per connection, not per request. *Server-side* latency is measured by the application,
here from the moment the timing middleware sees the request until the response starts.

**How it runs here.** The SLO counts the server-side histogram, so T is read from it. k6's figure — which also
includes a network round trip and the load balancer's own time — is recorded beside it, as what a direct client of
the api waits.

**What breaks when they are mixed.** A target taken from one and enforced on the other is off by their difference on
every request. In this deployment that difference is small next to the bucket width, and rounding usually absorbs
it; the principle is kept because at a finer scale the same mix-up is how a threshold ends up enforcing something
nobody measured.

---

## 4. How Prometheus finds a target

**What it is.** Prometheus only collects from *targets* it is configured to scrape. With the Prometheus Operator, a
`ServiceMonitor` says "scrape the pods behind the Services matching these labels", a `PodMonitor` says "scrape the
pods matching these labels" directly, and the Prometheus instance has its own selectors deciding which monitors it
pays attention to — by label, and by namespace.

**How it runs here.** The app chart ships a PodMonitor for the api — so each pod is scraped exactly once even
when, from stage 5, three Services select it. It also copies the pod label the canary needs onto every series — a
ServiceMonitor could do that too; the double scrape is what decides between them.
The monitoring stack's label selectors are emptied so it accepts monitors whatever their labels; its namespace
selectors are empty by default. The same is done for alert rules, which have their own, identical selector.

**What breaks without it.** By default the stack selects only objects carrying its own release label. Anything else
is accepted by the cluster, shows no error anywhere, and is never used. For a monitor the symptom is queries that
return nothing; for a rule it is an alert that cannot fire.

---

## 5. Open and closed load models

**What it is.** A *closed* model simulates a fixed number of users, each waiting for its answer before asking again.
An *open* model sends requests at a set arrival rate, whether or not earlier ones have been answered. Under a closed
model, a slow service slows the generator with it — the requests it would have sent during the slow period are never
sent and never timed. That is called *coordinated omission*.

**How it runs here.** The capacity ramp raises an arrival rate. When the service falls behind, requests queue and
latency climbs; iterations the generator cannot start, for lack of free workers, are counted as dropped.

**What breaks with a closed model.** It still shows a throughput ceiling. What it hides is the queue: latency rises
only as fast as users are added, and the percentiles leave out every request that a real arrival process would have
made and made wait. The knee looks gentler than it is.

---

## 6. Saturation, and where it can come from

**What it is.** *Saturation* is where adding load adds latency or errors instead of throughput. A test finds *a*
limit; it does not say whose.

**How it runs here.** At a fixed replica count there are two candidates: the pods, and the machine generating the
load. Dropped iterations appear in both cases, so the workstation's CPU is recorded beside them. The node group's
ceiling is not a candidate here — nothing asks for more pods — and becomes one only in the autoscaling run.

**What breaks without separating them.** A capacity figure that is really the workstation's becomes the number the
autoscaler's threshold is derived from. It understates what a pod can carry, so scaling starts earlier and more often
than the service needs — a cost paid on every busy hour, for a number that described the test.

---

## 7. The fake provider as a load source

**What it is.** A mode of the api that answers without calling a model, with a configurable latency and error rate.
It is set per deployment and is never the default.

**How it runs here.** The capacity ramp, the canary drills and the alert drill use it, so they can push hard, repeat
exactly and cost nothing. The baseline that sets T never does.

**What its numbers mean.** A fake-mode latency is a configured sleep plus the platform's overhead. It measures how
much routing, scheduling and the app's own code can carry — not how fast the model is.

**What breaks when modes are mixed.** A fake-mode p95 is a fraction of any real-mode T, so a comparison between them
passes well into saturation. Every number is recorded with its mode on the same line, and no fake-mode figure is ever
set against a real-mode target.

---

## 8. An empty result is not a zero

**What it is.** A Prometheus query over data that does not exist returns an *empty result* — no series at all. That
is different from a series whose value is zero.

**How it runs here.** Every stage that reads a metric first checks that the data is there: the api's target is up,
and the **total** request counter has samples over the window about to be used. Not the error counter — it has no
samples until the first error, so a healthy service would fail that check.

**What breaks without the check.** An alert rule over nothing never fires. A dashboard panel says "No data", which is
easy to overlook — and the common fix, treating absent as zero so the graph looks complete, turns "measuring nothing"
into a flat, reassuring line. The system has not been measured and reports that it is fine: the purest form of a
check that cannot fail.

---

[README](README.md) · [Design §4.5](../eks-sre-llmops-design.md#45-autoscaling-and-load-testing) ·
[Design §4.3](../eks-sre-llmops-design.md#43-slos-and-alerting-deployslo)
