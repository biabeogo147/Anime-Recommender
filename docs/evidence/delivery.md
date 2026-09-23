# Stage 5 — Delivery: evidence

Criteria **#8** (a good version is promoted by measurement) and **#9** (a bad version aborts itself), from the
[delivery guide](../5-delivery/guide.md). Both drills run in **fake mode** with k6 holding a constant 20 requests
per second: the two versions must be compared in the same mode, and 20 req/s is chosen for the success-rate
gate's resolution, not for the minimum-traffic guard.

## #8 — the promotion drill

Run 2026-09-23. Old stable `589794b4fd`, new version `586cd55b4f`; the only difference between them is the drill
marker, so the new version should be as good as the old one, and the question is whether the gate can tell.

| Reading | Value |
|---|---|
| Start → Healthy | `08:08:19Z → 08:16:42Z` — **8 m 23 s** |
| Steps walked | 10% → 50% → 100%, with an analysis at each pause |
| AnalysisRuns | **2, both `Successful`** |
| `canary-hash` / `stable-hash` in both | `586cd55b4f` / `589794b4fd` — **different** |
| Requests served in the window | stable `589794b4fd`: **7070.6**; canary `586cd55b4f`: **2825.4** |

**The timeline, as the Rollout reported it.**

| Time | Phase |
|---|---|
| 08:08:49Z | `Paused step=1/6 canary-weight=10%` |
| 08:11:15Z | `Progressing step=2/6` — the first analysis passed |
| 08:12:27Z | `Progressing step=3/6 canary-weight=50%` |
| 08:13:04Z | `Paused step=4/6` |
| 08:14:52Z | `Progressing step=5/6` — the second analysis passed |
| 08:16:42Z | `Healthy step=6/6`, `stable = latest = 586cd55b4f` |

**The measurements, four per metric per step.**

| Metric | At 10% (`…-5-2`) | At 50% (`…-5-5`) | Gate |
|---|---|---|---|
| `canary-requests` | 250.2, 261.3, 276, 256 | 1189.3, 1157.3, 1168, 1198.7 | ≥ 20 |
| `success-rate` | 1, 1, 1, 1 | 1, 1, 1, 1 | ≥ 0.99 |
| `latency-ratio` | 0.986, 0.968, 1.038, 1.028 | 1.005, 0.995, 1.004, 1.004 | ≤ 1.2 |

**Why each of those readings matters, and not just that they were green.**

- **The two hashes differ.** A `canary-hash` equal to the `stable-hash` is the false pass of design §6, row 8: the
  gate would be comparing the old version with itself and could never fail.
- **`canary-requests` matches what the traffic predicts** — about 240 per two-minute window at 10% and about 1200
  at 50%, from 20 req/s. Roughly double would mean each pod is scraped twice, and the minimum-traffic guard would
  be satisfied by half the traffic it asks for.
- **Every measurement is a number.** An empty `[]` is a query that matched nothing, which reads as green without
  measuring anything.
- **`latency-ratio` sits near 1.00 against a 1.2 threshold**, so the gate still has room to refuse. A ratio, not
  an absolute "p95 ≤ T": T is a real-mode number and these drills run in fake mode, so an absolute gate could not
  fail here. Comparing two versions measured side by side takes the mode out of the question.
- **Both hashes served real traffic in the window** (7070.6 and 2825.4), so neither side of the comparison was
  empty.

**#8: pass.**

## What the first attempt cost, and what it proved

The drill was run twice. The first attempt, `promote-1`, **aborted a healthy version**:

```
Metric "latency-ratio" assessed Error due to consecutiveErrors (5) > consecutiveErrorLimit (4):
could not evaluate successCondition "...!isInf(result[0], 0)...": too many arguments to call isInf
```

The canary itself was fine — that run's `success-rate` measured `1` and `1`, and `canary-requests` 212.6 and
209.3. What failed was the gate's own condition: Argo Rollouts evaluates these with expr-lang, whose `isInf` is a
unary predicate, while the template had been written with Go's `math.IsInf(f, sign)` shape.

The failure mode is worth keeping, because it is not the one the design anticipated. A condition that does not
**compile** never fails the metric — every evaluation returns an error, five errors pass
`consecutiveErrorLimit`, and the Rollout aborts. From the outside that is indistinguishable from a bad release:
same `abort=true`, same `Degraded`, same return to stable. Only the message separates them. The guide's
troubleshooting table now carries the symptom, and the template carries a comment saying why the argument count
is what it is.

**It was fixed through Git, not on the cluster** — the template is part of the chart, so the repair went through
a pull request and Argo CD, which is the property stage 2 exists to establish.

**The fix was then proved for free.** Merging that pull request produced a new image digest, so Argo CD started a
canary of its own (`589794b4fd`) before any drill was run. It walked the full 10 → 50 → 100 with
`latency-ratio` measuring 0.995, 0.998, 0.997 and 1.014 — the first evidence that the repaired condition
evaluates at all, at no cost in drill attempts. That canary is also why the promotion drill's "old stable" is
`589794b4fd` rather than the version that was stable before the repair.

A note that belongs to stage 3 rather than here: that release changed the digest although **no source file
changed** — the pull request it came from touched only documentation and three Terraform lock files. A digest
identifies one build, not the content of a commit. It is why the signature is over the digest.

## #9 — the rollback drill

Run 2026-09-23, immediately after #8, on the same traffic. The bad version is the same fake mode with
`api_fault_rate = "0.2"`, so one request in five fails inside the api itself — the only difference from the
version it is compared against.

| Reading | Value |
|---|---|
| Canary ReplicaSet created | `08:18:13Z` |
| Failing measurement finished — the abort | `08:21:00Z` |
| **Rollout start → abort** | **167 s** |
| Bad version | `594bfd86bf`; stable stayed `586cd55b4f` throughout |
| AnalysisRun | `anime-api-594bfd86bf-6-2`, **`Failed`** — `success-rate assessed Failed due to failed (2) > failureLimit (1)` |
| Requests the canary served | **250.9** |
| Requests the canary **failed** | **45.0** — 17.9% of its own traffic, against the 20% configured |
| Share of **all** requests that failed while the canary was live | **1.36%** |

**The measurements.**

| Metric | Values | Gate | Verdict |
|---|---|---|---|
| `canary-requests` | 230.2, 221.3 | ≥ 20 | Successful |
| `latency-ratio` | 1.042, 1.030 | ≤ 1.2 | **Successful** |
| `success-rate` | **0.813, 0.819** | ≥ 0.99 | **Failed** ×2 |

**#9: pass**, and on all four counts that make it mean something:

- the Rollout aborted **by itself**, with no human action;
- the canary's error count is **above zero** (45.0). An abort with a zero error count would prove nothing about
  the gate, whatever the Rollout did (design §6, row 9);
- the AnalysisRun that failed is the one for the bad hash (`canary-hash=594bfd86bf`), not some other run;
- `stable` never moved off `586cd55b4f`, so traffic returned to the good version.

**The detail worth keeping: the bad version was not slow.** `latency-ratio` measured 1.042 and 1.030 and passed
its gate at both probes. Only `success-rate` caught it. A release judged on latency alone would have promoted
this version to 100%. Two gates that fail for different reasons is not redundancy here — each one is blind to
what the other sees.

**The cost of the drill, in requests.** 45 failed requests out of about 3,300 served during the canary's 167
seconds — **1.36%**. That is the point of a canary stated as a number: the bad version reached a tenth of the
traffic, failed a fifth of that, and was gone in under three minutes.

**What Git and the cluster did afterwards — and why the disagreement is correct.** Immediately after the abort,
the `anime-api` Application read **`Synced/Degraded`**. That pair is the right answer, not a fault: Git still
said "run the version with `api_fault_rate = 0.2`", and the cluster had refused it. Argo CD did **not** heal the
Degraded state, because healing would mean trying the rejected version again. The disagreement ended only when
Git changed its mind — `api_fault_rate = "0"` applied through bootstrap — after which the pod template matched
the stable version again, **no canary started at all**, the Rollout reported `back on the old stable`, and the
Application returned to `Synced/Healthy`.

This is the property worth stating plainly: a self-healing GitOps controller and an automatic rollback pull in
opposite directions, and the design resolves it by letting the Rollout own the abort while Git owns the
intent. The cluster is allowed to disagree with Git, visibly, until a human changes Git.

**Back to real mode.** The stage ends with `api_llm_provider = "openai"` applied and `provider=openai` on the
Rollout, since stage 6 measures the SLO against the real provider and the T it produced.

**Time to abort, in its parts.** 167 s total: about 20 s for the canary ReplicaSet to have a pod serving, a
2-minute pause at the 10% step while the analysis probes every 30 s, then the second failing measurement, since
`failureLimit` is 1 and one failure is not enough. Measured from the cluster — the ReplicaSet's creation
timestamp and the measurement's `finishedAt` — not from the loop that watched, which only notices an abort after
it has happened.
