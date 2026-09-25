# Stage 4 — Load: evidence

Criteria **#6** (T) and **#7** (capacity of the minimum deployment), from the
[load guide](../4-load/guide.md). Every figure carries its mode: T is real mode, capacity is fake mode, and a
fake-mode number is never compared with T.

## #6 — T, the latency target

Measured 2026-09-23, real mode, **OpenAI `gpt-4o-mini`**, at 10 requests per minute.

| Reading | Value |
|---|---|
| Window | `2026-09-23T01:46:47Z → 02:09:53Z` (1386 s) |
| Requests counted server-side | **230** (k6 sent 231) |
| 5xx in the window | **0** |
| Server-side p95, interpolated | 7.07 s |
| **T** | **8 s** |
| k6's client-side p95 | 6.28 s |

**Why T is 8 s and not 7.07 s.** The SLI reads the histogram's counter at `le=T`, so T has to be a bucket boundary
that exists (`src/anime/metrics.py`). The true p95 falls inside the 6–8 s bucket; `histogram_quantile` interpolates
to 7.07 s, and the boundary that holds at least 95% of the requests is 8 s.

**Why the server's number is above k6's.** Not because the server is slower: 6.28 s is k6's own order statistic,
7.07 s is an interpolation across a 2-second-wide bucket. The two are consistent, and only the boundary is used.

**#6: pass** — at least 200 requests, real mode, read server-side over exactly the run's window.

This T belongs to this provider. A T measured on Gemini would be a different number, and the SLO would have to be
re-measured with it.

## #7 — capacity, the knee rule

**Written before the ramp runs** (guide 3.1), so the threshold cannot be chosen after seeing the graph:

- **low-load p95** = the mean of the first four p95 points that are numbers, at a 30-second step;
- **knee** = the first point where p95 exceeds **1.5 ×** the low-load p95;
- **capacity** = the served rate at the last point **before** the knee.

The capacity figure is valid only if both hold:
- no dropped iterations before that point (otherwise the number describes the load generator, or the script's
  virtual-user limit, not the service);
- the ops workstation was not saturated — its busiest `vmstat` sample below about 90% CPU.

### The two runs

Both in fake mode, two replicas, no autoscaler, a ramping arrival rate to 120 req/s over ten minutes, 2026-09-23.
Neither is discarded outright and neither is a clean pass; what each establishes is set out below.

| | Run 1 (03:00:02Z → 03:10:16Z) | Run 2 (03:24:13Z → 03:34:26Z) |
|---|---|---|
| `preAllocatedVUs` | 50 | 300 |
| Requests, and 5xx | 39455, **0** server-side | 39644, **0** server-side (k6 counted 1 connection-level failure) |
| Low-load p95 → threshold | 1.432 s → 2.148 s | 1.453 s → 2.179 s |
| Knee (first p95 above it) | 3.34 s at 03:07:32Z | 4.81 s at 03:31:43Z |
| Served rate at the last point before it | **88.2 req/s** | **89.1 req/s** |
| Plateau of the served rate | **93.9 req/s** | **93.9 req/s** |
| in-flight per pod at the knee | 170.5 | 117.5 |
| CPU / memory per pod at the plateau | 0.227 cores / 142 MiB | 0.236 cores / 143 MiB |
| p95 at the top of the ramp, 120 req/s | **15.1 s** | **15.6 s** |
| Ready pods, nodes | 2, 2 throughout | 2, 2 throughout |
| First dropped iteration | 03:03:21Z — **4 minutes before** the capacity point | 03:31:08Z — **5 seconds before** it |
| Busiest workstation CPU sample | 46% | 54% |

## What the two runs establish

**The ceiling, to three significant figures.** The served rate stopped at **93.9 req/s** in both runs while the
offered rate kept climbing to 120. Two independent runs agreeing to that precision is not a coincidence, and a
third source agrees: `/recommend` runs the model call in FastAPI's thread pool, 40 threads per pod, and fake
mode sleeps a lognormal around 800 ms with sigma 0.35, whose mean is 0.8 x exp(0.35^2/2) = 0.85 s. That allows
40 / 0.85 = 47 req/s per pod, **94.1 for two** — computed in `loadtest/k6/ramp.js` before either run.

**That the limit is concurrency, not resources.** At the plateau each pod used **0.23 cores** and 143 MiB. The
threads were not working; they were asleep waiting for the provider. A CPU-based autoscaler would see an idle
service at the moment its latency triples, which is why criterion #14 scales on in-flight requests.

**That the flat region is the provider's own latency.** `FakeLLM`'s sleep has a p95 of 0.8 x exp(1.645 x 0.35) =
**1.42 s**; measured, **1.43 s** and **1.45 s**. Below the knee the api adds nothing measurable.

**What two fixed pods look like past their limit.** By the top of the ramp — 120 req/s offered against a ceiling
of 93.9 — p95 had reached **15.6 s**, ten times the 1.43 s it holds below the knee, and nothing failed on the way
there. That figure is the baseline stage 7 is measured against: the same service under an autoscaler held p95 at
1.44–1.47 s at **267 req/s**, more than twice this load ([scaling](scaling.md#what-the-users-saw-nothing)).

**Capacity, by the pre-registered rule: 88–89 req/s.** Both runs, one point apart, ~6% below the ceiling — the
rate at which the queue has not yet formed.

## What the two runs do NOT establish, and why a third was not run

**in-flight per pod at the knee is not reproducible here: 170.5 against 117.5, 45% apart.** The cluster behaved
identically both times — the ceiling proves that — so the instability is in the instrument, and it has two
causes:

- **Two different kinds of time are being paired.** p95 comes from `rate(...[2m])`, where each point summarises
  the *previous two minutes*; in-flight is a gauge read *at that instant*. By the time a two-minute average
  crosses the threshold, the instantaneous state is already well inside the break-away — how far inside depends
  on the run.
- **A 30-second grid across a near-vertical rise.** in-flight per pod goes 46 → 117 → 228 → 375 → 500 in two
  minutes. Which tick is the first past the threshold decides the number; shifting the run by fifteen seconds
  changes the answer.

A third run would sample the same rise on the same grid with the same pairing, and produce a third equally
arbitrary number. It was not run. The `preAllocatedVUs` fix (50 → 300, now 300 by default) addressed the
dropped iterations, which is a different defect; the drop in run 2 came five seconds before the capacity point
rather than four minutes, but the condition still failed and is recorded as failed.

## #7 — capacity: **partly measured**

| Reading | Value | Basis |
|---|---|---|
| Throughput ceiling, 2 pods, fake mode | **93.9 req/s** | measured twice, agrees with the computed thread-pool limit of 94.1 |
| Sustained rate before latency breaks away | **88–89 req/s** | the pre-registered rule, both runs |
| Error ratio up to the knee | **0** | every point of both runs |
| CPU / memory per pod at the ceiling | **0.23 cores / 143 MiB** | sets the api's resource requests |
| Concurrency limit per pod | **40 in-flight** | the thread pool; the last flat point sat at 46.5 per pod with p95 still 1.46 s |
| in-flight per pod at the knee | **not reproducible** — 170.5 and 117.5 | see above; not used |

**#7: partly measured.** The ceiling and the resource figures are sound. The capacity figure carries the caveat
that its validity condition — no dropped iterations before the capacity point — failed in both runs.

### The KEDA threshold this hands to stage 7

Not the knee's in-flight reading, which is not reproducible, but the architectural limit it was standing in for:

> A pod has 40 threads and each holds one request, so **in-flight above 40 per pod means a queue is forming**.
> That is a definition, not a measurement, and the measurements agree with it: at 83 req/s the pods held 46.5
> in flight with p95 still at 1.46 s, and the next point broke away.

**Stage 7 starts from a threshold of 30 in-flight per pod** — below 40, so the autoscaler reacts before the
queue forms and leaves the one to two minutes a new pod needs to become ready. Stage 7 tests that assumption:
if replicas grow before p95 reaches T = 8 s, 30 holds; if p95 breaks away first, 30 is still too high.

### Why the run looks the way it does

- **Fake mode**, because a real provider would make these 39,000 requests cost money and hit a rate limit, and
  the number would then describe the provider rather than the cluster.
- **Two replicas, no autoscaler**, because the figure has to describe one unit. With scaling on, the graph never
  breaks away and nothing is learnt about a pod.
- **An open model** (a ramping *arrival rate*, not a fixed number of users), because virtual users that wait for
  an answer send less as the service slows — coordinated omission — and the knee would look gentler than it is.
- **The rule written and committed before the run**, because "where the graph bends" is otherwise chosen after
  seeing the graph.

### What this figure is not

It is the ceiling of **two pods**, not of the cluster. The nodes were never close to saturated: 0.23 cores per
pod, two nodes idle. Reaching the cluster's own ceiling means removing this one first — that is, adding pods,
which is autoscaling, which is criterion #14 in stage 7. And configuring that correctly is what the in-flight
threshold above is for.
