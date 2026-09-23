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

### Run 1, 2026-09-23 03:00:02Z - 03:10:16Z: discarded by the rule above

Not a failed run: 39455 requests, every one a 200, pods and nodes at 2 and 2 throughout. It is discarded because of
the first validity condition, and it is kept here because that is what the condition is for.

- Low-load p95 = mean(1.431, 1.427, 1.415, 1.455) = **1.432 s**; the threshold is 1.5 x that = **2.148 s**.
- p95 held 1.43 s for ten points, then 1.93 (under the threshold), then **3.34 s at 03:07:32Z — the knee**.
- The last point before it, 03:07:02Z, served **88.2 req/s**, at 84.5 in-flight per pod.
- **But the first dropped iteration came at 03:03:21Z**, four minutes earlier, when the offered rate was about
  50 req/s and p95 was still 1.43 s. The service was healthy there, so the drops were the generator's: `ramp.js` had
  `preAllocatedVUs: 50`, and k6 initializes any VU beyond that number during the run, slowly enough to drop
  iterations. The workstation was not the cause either — its busiest sample was 46% CPU.

So 88.2 req/s is not reported as the capacity. `PRE_VUS` now defaults to 300 (`loadtest/k6/ramp.js`), and the run is
repeated.

What the run does establish, because neither reading depends on the generator keeping up:

- **The flat region is the fake provider's own latency, not the service's.** `FakeLLM` sleeps a lognormal around a
  800 ms median with sigma 0.35, whose p95 is 0.8 x exp(1.645 x 0.35) = **1.42 s**. Measured: **1.43 s**. At low load
  the api adds nothing measurable.
- **The ceiling is the thread pool, not the CPU.** `/recommend` runs the model call in FastAPI's thread pool, 40
  threads per pod; at a mean sleep of 0.8 x exp(0.35^2/2) = 0.85 s that allows 47 req/s per pod, **94.1 req/s for
  two** — computed in `loadtest/k6/ramp.js` before the run. The served rate plateaued at **93.9 req/s** while the
  offered rate kept climbing to 120. CPU stayed at 0.23 cores per pod and memory at 142 MiB, so neither was the limit:
  the threads were, each one asleep waiting for the provider.

Past the knee the queue grew as that arithmetic predicts: in-flight per pod went 84 -> 170 -> 308 -> 499, p95 went to
15.6 s, and still nothing failed - 0 errors at every point.

### Run 2

| Reading (fake mode, 2 replicas, no autoscaler) | Value |
|---|---|
| Low-load p95 | *pending* |
| Knee | *pending* |
| Capacity, served requests per second | *pending* |
| Error ratio up to the knee | *pending* |
| In-flight per pod at the knee | *pending* — sets the KEDA threshold in stage 7 |
| CPU and memory per pod at the knee | *pending* — set the api's resource requests |
| Ready pods and nodes during the run | *pending* — both should stay at 2 |
| k6 dropped iterations, and the busiest workstation CPU sample | *pending* |
