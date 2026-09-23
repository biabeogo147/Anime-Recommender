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

*Pending.* It needs a version that is bad on purpose — the same fake mode with `api_fault_rate = "0.2"` — and it
is only meaningful if the canary is shown to have really failed requests: a canary whose error count is zero
makes the drill worthless whatever the Rollout did (design §6, row 9).

| Reading | Value |
|---|---|
| Time from rollout start to abort | *pending* — measured from the canary ReplicaSet's creation to the failing measurement's `finishedAt`, not from the watching loop |
| The failing measurement, and its metric | *pending* |
| Requests the canary actually failed | *pending* |
| Requests served by the bad version before the abort | *pending* |
| Whether Git and the cluster disagreed afterwards, and until when | *pending* |
