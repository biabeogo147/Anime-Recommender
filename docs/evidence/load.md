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
