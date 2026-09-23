# Measurements for the CV

Eight measurements that turn the bracketed placeholders in the CV's Anime entry (`cv_projects.tex`, outside this
repository) into numbers. Six of them are taken while running the stage guides, at a step named below; M5 adds one
count here, and M7 and M8 have their own commands. Every result goes in [`cv.md`](cv.md), with the file it came from.

Each measurement says what it proves, and what a false pass would look like. A number whose conditions are not met
is not written down as the placeholder's value.

| # | CV placeholder | Taken at | Proves |
|---|---|---|---|
| [M1](#m1--the-latency-target) | `[T-SLO]`, `[N-BASELINE]` | [load 2.2](../4-load/guide.md) | The latency objective comes from real calls, read server-side |
| [M2](#m2--the-knee) | `[KNEE-RPS]`, `[INFLIGHT-KNEE]` | [load 3.4](../4-load/guide.md) | Where two fixed pods saturate, and what sets the autoscaler |
| [M3](#m3--a-canary-that-aborts-itself) | `[T-ABORT]`, `[AFFECTED-PCT]` | [delivery 4.2–4.3](../5-delivery/guide.md) | A bad release stops itself at 10%, and what that cost |
| [M4](#m4--a-page-that-reaches-a-person) | `[T-PAGE]` | [slo 3.2–3.4](../6-slo/guide.md), short drill | A fast burn reaches Discord, and how fast |
| [M5](#m5--scaling-out-and-back) | `[PODS-MAX]`, `[NODES-MAX]`, `[ERR-SCALEIN]` | [scaling 3.3–3.4](../7-scaling/guide.md) | Pods and nodes follow in-flight load, and scale-in drops nothing |
| [M6](#m6--cost-per-1000-requests) | `[COST-PER-1K]` | [tracing 3.2](../8-tracing/guide.md) | What the real model costs per request |
| [M7](#m7--drill-traffic-kept-out-of-langfuse) | `[LF-LEAK]`, `[N-DRILL]` | here, during tracing 2.4 | The filter keeps drill traffic out of the third-party store |
| [M8](#m8--a-timed-rebuild) | `[T-REBUILD]`, `[N-APPS]` | here, a session of its own, last | The whole platform comes back from nothing, in a measured time |

**Order is fixed** by the stages: M1 and M2 in stage 4, M3 in 5, M4 in 6, M5 in 7, M6 and M7 in 8, then M8 in a later
session. Cluster time for M1–M7 is what the stage guides already need; M8 adds about an hour.

**If time runs out**, cut in this order. The CV wording for each cut is in the last table.
1. M7: drop the Langfuse-leak clause.
2. The node half of M5: pods only.

Never cut M3 or M4: they are the strongest lines.

**Rules.** Numbers are copied from the evidence files the stage guides write in `~/anime-evidence/`, not retyped from
memory. Every value in `cv.md` names the file it came from, and the mode it was measured in.

---

## M1 — The latency target

**At** [load guide 2.2](../4-load/guide.md), in **real** mode (`openai`, `gpt-4o-mini`).

**Record:**
- `[T-SLO]`: the `T = … le=<boundary>` line, as seconds (`le=3.0` becomes "3 s"). It is printed, not saved; copy
  it into `~/anime-evidence/t-value.txt` at once;
- `[N-BASELINE]`: the request count from `t-count.txt`, rounded down.

**Valid only if** the count is at least 200 and the mode is a real provider, named with the model in `cv.md`. A T read from k6, or from fake mode, is not T.

## M2 — The knee

**At** [load guide 3.4](../4-load/guide.md): the ramp at two fixed replicas, in fake mode, before the scaling stage
exists.

**Record:**
- `[KNEE-RPS]`: the capacity reading. This is the served rate at the last point before p95 broke away.
- `[INFLIGHT-KNEE]`: in-flight per pod at the knee, rounded to one decimal place.

**Valid only if** dropped iterations stayed at 0 up to the knee, and the workstation was not saturated (3.4,
reading 3). Otherwise the number describes the generator, and the bullet's first clause is dropped.

**Measured 2026-09-23, and the second reading did not survive.** Two runs put the ceiling at the same
93.9 req/s and the capacity at 88–89, but `[INFLIGHT-KNEE]` came out 170.5 and 117.5 — 45% apart, because the
knee is detected on a two-minute rate window while in-flight is an instantaneous gauge, sampled every 30 s
across a near-vertical rise. A third run would sample the same rise the same way. The autoscaler's threshold is
therefore taken from the pod's 40-thread concurrency limit, which the runs corroborate, and the reasoning is in
[load](load.md#the-keda-threshold-this-hands-to-stage-7). When quoting M2, quote the ceiling and the capacity,
never the in-flight figure.

## M3 — A canary that aborts itself

**At** [delivery guide 4.2–4.3](../5-delivery/guide.md), in fake mode, with k6 at 20 RPS.

**Record:**
- `[T-ABORT]`: the `rollout start → abort` line of `rollback-time.txt`, in seconds, or minutes and seconds;
- `[AFFECTED-PCT]`: `rollback-affected.txt`, as a percentage with one decimal.

**Valid only if** the canary's own error count in `rollback-canary-errors.txt` is above zero, and the failed
AnalysisRun is the one that stopped it (4.3). Otherwise the abort came from something else, and the line is not used.

## M4 — A page that reaches a person

**At** [SLO guide 3.2–3.4](../6-slo/guide.md), the short drill (about one clean hour).

**Record:** `[T-PAGE]` = the Discord `[PAGE] … FIRING` message's time minus `alert.fault`, in minutes and seconds.

**Write in `cv.md`, not in the CV:**
- which pair fired first: the earlier of the `pair 1h/5m` and `pair 6h/30m` lines in 3.4;
- the `pair 1h/5m` time on its own. The store holds a full clean hour, so this is the calibrated pair's crossing
  even when the 6h/30m pair paged first;
- the store's age, and the service's error ratio at firing.

`alert.fault` is written after the Healthy poll, so the fault may have reached traffic a few seconds earlier:
`[T-PAGE]` can be understated by that much.

**Valid only if** the error ratio at firing is close to 0.5, so the fault reached all traffic, and delivery failures
are 0. A page from the 6h/30m pair is still a valid `[T-PAGE]`, because the CV claims only the time to the page.

## M5 — Scaling out and back

**At** [scaling guide 3.4](../7-scaling/guide.md).

**Record:**
- `[PODS-MAX]`: the highest value in `scaling-desired.txt` that also appears in `scaling-ready.txt`. These are
  replicas that really ran, not only replicas that were asked for.
- `[NODES-MAX]`: the highest value in `scaling-nodes.txt`.
- `[ERR-SCALEIN]`: the requests that failed while replicas fell. A scale-in with no traffic cannot fail a request,
  so scaling 3.3 keeps a light load running through the return (`RPS=5`, 30 minutes). The count comes from **k6**,
  the client. A request the ALB sends to a pod that is already gone gets its 502 or 503 from the ALB itself, and the
  app's own counter never sees it. The server's count is kept beside it as context. After 3.4:

```bash
cd ~/Anime-Recommender && export KUBECONFIG=$HOME/.kube/anime
S=$(cat ~/anime-evidence/steady.start); E=$(cat ~/anime-evidence/steady.end)
W=$(( $(date -d "$E" +%s) - $(date -d "$S" +%s) ))s
{
# k6: http_req_failed is a rate whose "passes" are the FAILED requests (any status outside 200-399, or no response).
jq -r '.metrics | "k6: requests \(.http_reqs.count), failed \(.http_req_failed.passes // 0)"' ~/anime-evidence/steady-summary.json
make -s prom AT=$E Q="sum(increase(anime_http_requests_total{route=\"/recommend\",status=~\"5..\"}[$W])) or vector(0)"
} | tee ~/anime-evidence/scaling-errors-scalein.txt
```

Record `failed` as `[ERR-SCALEIN]`, with `requests` beside it in `cv.md` (about 9,000). If the server-side count is
lower than `failed`, the difference is failures the load balancer answered for gone pods, which is exactly what this
checks.

**Valid only if** the trigger rose before the replicas did (3.4, reading 1). **If `pending` stayed 0 all run**, nodes
did not move: `[NODES-MAX]` is not used, and the CV takes the fallback wording.

## M6 — Cost per 1,000 requests

**At** [tracing guide 3.2](../8-tracing/guide.md), in **real** mode (`openai`).

**Record:** `[COST-PER-1K]` = the value in `cost-per-1000.txt`, in USD, rounded to four significant figures, with
its `model` label and the date in `cost-pricing-date.txt`.

**Valid only if** it is above zero, and the label is a real model: not `fake`, and not a model priced at 0.

## M7 — Drill traffic kept out of Langfuse

**At** [tracing guide 2.4](../8-tracing/guide.md), right after its first block, while the api is in **fake** mode with
tracing on, and **before** switching back to real mode. Five minutes of drill traffic, then count what reached each sink.

```bash
cd ~/Anime-Recommender && export KUBECONFIG=$HOME/.kube/anime
FROM=$(date -u +%FT%TZ); echo "$FROM" > ~/anime-evidence/m7.from
RPS=20 DURATION=5m make loadtest-steady
TO=$(date -u +%FT%TZ); echo "$TO" > ~/anime-evidence/m7.to
# The span metrics are flushed by the connector about once a minute and scraped every 30 s: read both counts two
# minutes later, over a window stretched by the same two minutes, so the run's last spans are in.
sleep 120; AT=$(date -u +%FT%TZ)
W=$(( $(date -d "$AT" +%s) - $(date -d "$FROM" +%s) ))s
{
echo "== requests (N-DRILL)"
make -s prom AT=$AT Q="sum(increase(anime_http_requests_total{route=\"/recommend\"}[$W]))"
echo "== spans in Tempo's pipeline (span metrics, same window)"
make -s prom AT=$AT Q="sum(increase(traces_span_metrics_calls_total{service_name=\"anime-api\",span_name=\"POST /recommend\"}[$W]))"
} | tee ~/anime-evidence/m7-counts.txt
```

Then put the api back in real mode and run the **second block of tracing 2.4**, the later real trace. When that
trace is visible in Langfuse, ingestion has caught up past the drill window. Only then count:

```bash
cd ~/Anime-Recommender && export KUBECONFIG=$HOME/.kube/anime
make -s langfuse-count FROM=$(cat ~/anime-evidence/m7.from) TO=$(cat ~/anime-evidence/m7.to) | tee -a ~/anime-evidence/m7-counts.txt
```

**Record:**
- `[N-DRILL]`: the request count, rounded down (about 6,000);
- `[LF-LEAK]`: the `distinct traces` count, expected `0`.

**Valid only if** all three of these hold:
- `langfuse http 200`;
- the later real trace was found in Langfuse in the same session;
- the span-metric count is close to the request count, so the traces did exist and reached Tempo.

Without all three, a `0` is also what a broken export looks like, and the clause is dropped.

## M8 — A timed rebuild

**A session of its own, last**, when every stage has passed once. `enabled_stages` in
`infra/terraform/bootstrap/terraform.tfvars` holds all six in-cluster stages (gitops, load, delivery, slo,
scaling, tracing; cicd has no in-cluster part), and the pins, T and the knee values are
committed. Start from a torn-down cluster:

```bash
cd ~/Anime-Recommender && export KUBECONFIG=$HOME/.kube/anime
grep '^enabled_stages' infra/terraform/bootstrap/terraform.tfvars
```

If the cluster is up, tear it down first with `make down`, the tunnel open, as at the end of every session
(terraform guide). Then `make -s ready` must fail: nothing is left to answer.

**The clock.** It starts before `make plan` and stops when every Application is Synced+Healthy. If the load balancer
controller's webhook CA and its Secret come from two renders, wave 0 stalls until [gitops 2.3](../2-gitops/guide.md#2-switch-the-stage-on--ops)
repairs them; that repair is part of the rebuild and stays inside the measured time. The `make tunnel`
step in window 2 is inside the measured time, on purpose: it is part of a real rebuild.

```bash
cd ~/Anime-Recommender && export KUBECONFIG=$HOME/.kube/anime
T0=$(date -u +%FT%TZ); echo "$T0" | tee ~/anime-evidence/m8.start
make plan && make infra && make kubeconfig
```

Window 2: `cd ~/Anime-Recommender && make tunnel`. Then, in window 1:

```bash
cd ~/Anime-Recommender && export KUBECONFIG=$HOME/.kube/anime
until make -s ready >/dev/null 2>&1; do sleep 10; done
make bootstrap-plan && make bootstrap
for i in $(seq 180); do
  out=$(kubectl -n argocd get applications -o jsonpath='{range .items[*]}{.metadata.name} {.status.sync.status} {.status.health.status}{"\n"}{end}' 2>/dev/null)
  n=$(echo "$out" | grep -c .); bad=$(echo "$out" | awk 'NF && ($2!="Synced" || $3!="Healthy")' | grep -c . || true)
  echo "$(date -u +%T) apps=$n pending=$bad"; [ "$n" -ge 17 ] && [ "$bad" -eq 0 ] && break; sleep 15
  [ $i -eq 180 ] && { echo "NOT HEALTHY AFTER 45 MIN — the rebuild is not timed; see which app is pending"; break; }
done
TE=$(date -u +%FT%TZ); echo "$TE" | tee ~/anime-evidence/m8.end
echo "rebuild: $(( ($(date -d "$TE" +%s) - $(date -d "$T0" +%s)) / 60 )) min, $n Applications" | tee ~/anime-evidence/m8.txt
sleep 60; make -s apps
```

The loop waits for 17 Applications: `root`, 7 from `gitops`, 1 from `delivery`, 2 from `slo`, 2 from `scaling`, and 4
from `tracing`.

**Check.** The loop ends with `apps=17 pending=0`, and a minute later `make apps` still shows all 17 Synced Healthy.

**Record:** `[T-REBUILD]` = end − t0, as one wall-clock figure (do not add up the commands' own times), and
`[N-APPS]` = 17, or the count the loop saw.

**Valid only if** the rebuild started from nothing: the cluster stack destroyed, and the bootstrap state deleted by
`make down`. A rebuild onto a live cluster measures only a sync. The shared stack is not rebuilt (ECR and its images,
the ACM certificate, the secrets), so the CV says "from an empty cluster stack".

---

## What each result changes in the CV

| Result | Edit in `cv_projects.tex` |
|---|---|
| M1 | Replace `[T-SLO]` and `[N-BASELINE]` |
| M2 valid | Replace `[KNEE-RPS]` and `[INFLIGHT-KNEE]` |
| M2 generator-bound | Drop "2 pods saturate at … (… in flight each), so"; start at "KEDA scales on in-flight requests" |
| M3 valid | Replace `[T-ABORT]` and `[AFFECTED-PCT]` |
| M3 not attributable | Drop the sentence after the semicolon; keep "judged by Prometheus on the canary's own pods" only if the promotion drill (delivery 3.3) passed |
| M4 | Replace `[T-PAGE]`. The pair that fired stays in `cv.md` |
| M5 with nodes | Replace `[PODS-MAX]`, `[NODES-MAX]` and `[ERR-SCALEIN]` |
| M5 without nodes | "…2 to [PODS-MAX] pods with 0 Pending, [ERR-SCALEIN] errors on scale-in": drop "2 to [NODES-MAX] nodes" |
| M5 errors above 0 | Keep the count as it is; do not round it to 0 |
| M6 | Replace `[COST-PER-1K]` (e.g. "\$0.0123") |
| M7 valid | Replace `[LF-LEAK]` and `[N-DRILL]` |
| M7 cut or not valid | Drop "(… of … drill requests leaked)" |
| M8 | Replace `[T-REBUILD]` (e.g. "38 min") and `[N-APPS]` |
