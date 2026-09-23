# Stage 4 — Guide: the two numbers later stages depend on

Commands and checks only. The reasoning is in the comments of these files:
- `loadtest/k6/*.js`;
- the `loadtest-*` and `prom` targets of the `Makefile`;
- `deploy/charts/anime-api/templates/podmonitor.yaml`;
- `src/anime/metrics.py` and `services/api/main.py`;
- [README](README.md) · [concepts](concepts.md).

The "Load A…" references below are answers in [answers.md](answers.md).

Machines as before: **ops** only in this stage. Work inside tmux, and start each block with
`cd ~/Anime-Recommender && export KUBECONFIG=$HOME/.kube/anime`. k6 runs in a container on ops. Each run's summary, its
window (`<name>.start`, `<name>.end`) and the digest of the k6 image it used go to `~/anime-evidence/`. A rerun of the
same target overwrites that run's files.

Criteria closed ([design §6](../eks-sre-llmops-design.md#6-verification-and-evidence-definition-of-done)):
- **#6:** T, read server-side from at least 200 real requests, with k6's p95 and the sample count beside it.
- **#7:** the highest sustained rate of the minimum deployment before p95 breaks away, with no dropped iterations,
  and with the generator ruled out.

This stage depends on three app changes, all already in the images CI built in stage 3:
- finer latency buckets;
- `async` handlers for the probes and `/metrics`;
- embedding failures mapped to 503.

---

## 1. Switch the stage on, then prove the data exists — ops

**1.1 — add `load` (it renders the api's PodMonitor).** `cicd` is not listed: it has no in-cluster part.

```bash
cd ~/Anime-Recommender && export KUBECONFIG=$HOME/.kube/anime
F=infra/terraform/bootstrap/terraform.tfvars
sed -i 's/^enabled_stages .*/enabled_stages            = ["gitops", "load"]/' $F
grep -q '^enabled_stages.*"load"' $F && echo "load enabled" || echo "ENABLED_STAGES NOT SET"
# SET, not only added: a tfvars from before 2026-09-22 still says "gemini".
grep -q '^api_llm_provider' $F && sed -i 's/^api_llm_provider .*/api_llm_provider          = "openai"/' $F \
  || echo 'api_llm_provider          = "openai"' >> $F
grep -q '^api_fault_rate' $F   || echo 'api_fault_rate            = "0"' >> $F
grep -E '^(enabled_stages|api_)' $F
# An api switched to openai without its key never becomes ready: check the key is stored before applying.
aws secretsmanager get-secret-value --secret-id anime/llm --query SecretString --output text \
  | jq -e 'has("OPENAI_API_KEY")' >/dev/null && echo "openai key stored" || echo "NO OPENAI_API_KEY in anime/llm: terraform guide 2.6 first"
make bootstrap-plan
```

Expected: `load enabled`, the three lines, `openai key stored`, `Plan: 0 to add, 1 to change, 0 to destroy.` Then apply, and wait for the
PodMonitor. The root passes `load` down to `anime-api` only when it next syncs, which can be minutes away:

```bash
cd ~/Anime-Recommender && export KUBECONFIG=$HOME/.kube/anime
make bootstrap
kubectl -n argocd annotate application root argocd.argoproj.io/refresh=hard --overwrite
for i in $(seq 30); do kubectl -n anime get podmonitor anime-api >/dev/null 2>&1 && break; sleep 10; done
kubectl -n anime get podmonitor anime-api
```

Expected: `Apply complete!`, then the PodMonitor listed. `NotFound` after five minutes: compare the stages in
`kubectl -n argocd get application anime-api -o jsonpath='{.spec.source.helm.valuesObject.stages}'` with the tfvars.

**1.2 — the api is scraped, by name.** Before you trust any number, check two things. The target exists and is up. The
TOTAL request counter has samples — not the error counter, which has none until something fails (Load A2.3). Six
probe requests reach both pods, so each pod's `/recommend` series exists before the baseline starts. `increase()` cannot
count what a series already holds at its first scrape.

```bash
cd ~/Anime-Recommender && export KUBECONFIG=$HOME/.kube/anime
kubectl -n anime get podmonitor anime-api
for i in $(seq 20); do make -s prom Q='count(up{job="anime/anime-api"} == 1)' | grep -q '=> 2 ' && break; sleep 15; done
make -s prom Q='up{job="anime/anime-api"}'
for i in $(seq 6); do
  curl -s -o /dev/null -w 'probe request: %{http_code}\n' -X POST https://api.anime.recruitai.io.vn/recommend \
    -H 'content-type: application/json' -d '{"query":"space bounty hunters"}'
done
sleep 45
make -s prom Q='count(anime_http_requests_total{route="/recommend"})'
make -s prom Q='count(anime_http_request_duration_seconds_bucket{route="/recommend"}) by (le)' | grep -c '=>'
```

Expected:
- the PodMonitor exists;
- two `up` series, each with value `1`;
- six `probe request: 200` lines;
- a count of at least `2`: each pod has its series;
- `17` bucket lines: 16 boundaries plus `+Inf`. The old layout gives 10.

An empty answer anywhere is **not** zero: stop and see troubleshooting.

---

## 2. Criterion #6 — T — ops

**2.1 — the baseline, in real mode (openai).** 220 requests at 10 per minute take about 23 minutes. The margin over 200 covers
requests that fail. Keep the rate under the provider's limit. If you know your tier allows more, `RATE_PER_MINUTE=15`
shortens the run.

```bash
cd ~/Anime-Recommender && export KUBECONFIG=$HOME/.kube/anime
grep '^api_llm_provider' infra/terraform/bootstrap/terraform.tfvars
TARGET_REQUESTS=220 RATE_PER_MINUTE=10 make loadtest-baseline
```

Expected: `api_llm_provider = "openai"`, then k6's summary and a `window: <start> → <end>` line.

**2.2 — read T from the server's histogram, over exactly that window.** The total counter is non-empty (1.2), so the
error query below can fall back to `vector(0)` without hiding a missing series. The fallback exists because a clean run
has no 5xx series at all.

```bash
cd ~/Anime-Recommender && export KUBECONFIG=$HOME/.kube/anime
S=$(cat ~/anime-evidence/baseline.start); E=$(cat ~/anime-evidence/baseline.end)
W=$(( $(date -d "$E" +%s) - $(date -d "$S" +%s) ))s; echo "window $S → $E ($W)"
R='route="/recommend"'
make -s prom AT=$E Q="sum(increase(anime_http_requests_total{$R}[$W]))"                                 | tee ~/anime-evidence/t-count.txt
make -s prom AT=$E Q="sum(increase(anime_http_requests_total{$R,status=~\"5..\"}[$W])) or vector(0)"   | tee ~/anime-evidence/t-errors.txt
make -s prom AT=$E Q="histogram_quantile(0.95, sum by (le) (increase(anime_http_request_duration_seconds_bucket{$R}[$W])))" \
  | tee ~/anime-evidence/t-p95.txt
make -s prom AT=$E Q="sum by (le) (increase(anime_http_request_duration_seconds_bucket{$R}[$W]))" > ~/anime-evidence/t-buckets.txt
python3 - <<'PY'
import re, pathlib
rows = []
for line in pathlib.Path.home().joinpath("anime-evidence/t-buckets.txt").read_text().splitlines():
    m = re.search(r'le="([^"]+)"\}\s*=>\s*([0-9.eE+-]+)', line)
    if m: rows.append((float(m.group(1)), m.group(1), float(m.group(2))))
rows.sort()
total = rows[-1][2] if rows else 0  # the +Inf bucket holds every request
t = next((label for le, label, v in rows if total and v / total >= 0.95), None)
print(f"requests {total:.0f}; T = smallest boundary holding >= 95%: le={t}")
PY
jq -r '.metrics | "k6: p95 \(.http_req_duration."p(95)") ms, requests \(.http_reqs.count)"' ~/anime-evidence/baseline-summary.json
```

Expected, five lines to report:
- **A request count of at least 200.** Fewer means the run is too short to trust: rerun, and never read T from it.
- **An error count,** `0` on a clean run. Report it: fast 503s pull a p95 down (Load A3.7). A 5xx series that first
  appears during the window is undercounted by its first request, so read a non-zero count as "at least".
- **A server-side p95.**
- **`T = … le=<boundary>`.** `le=+Inf` means the p95 is above 32 s: the run is invalid. It is not T = infinity.
- **k6's p95.**

**T is the boundary** the script prints: the server's p95 rounded **up** to a bucket edge. It is never k6's number.

---

## 3. Criterion #7 — the capacity of the minimum deployment — ops

**3.1 — write the knee rule down BEFORE the run.** p95 "breaks away" when it exceeds **1.5 ×** its low-load value. The
low-load value is the average of the first four p95 points that are numbers. Change the factor here, not after seeing
the graph, and report it with the result.

**3.2 — fake mode.** Two replicas, no autoscaler, a provider that costs nothing. The loop waits until the Deployment's
template really says `fake`. Only then does `rollout status` mean the new pods are the ones serving.

```bash
cd ~/Anime-Recommender && export KUBECONFIG=$HOME/.kube/anime
sed -i 's/^api_llm_provider .*/api_llm_provider          = "fake"/' infra/terraform/bootstrap/terraform.tfvars
make bootstrap-plan && make bootstrap
kubectl -n argocd annotate application root argocd.argoproj.io/refresh=hard --overwrite
mode() { kubectl -n anime get deploy anime-api -o jsonpath='{.spec.template.spec.containers[0].env[?(@.name=="LLM_PROVIDER")].value}'; }
for i in $(seq 20); do [ "$(mode)" = fake ] && break; sleep 15; done; echo "template provider: $(mode)"
kubectl -n anime rollout status deploy/anime-api --timeout=5m
kubectl -n anime get deploy anime-api -o jsonpath='{.status.readyReplicas} ready of {.spec.replicas}{"\n"}'
```

Expected: `Plan: 0 to add, 1 to change`, then `template provider: fake`, `successfully rolled out`, `2 ready of 2`.

**3.3 — the ramp, with the generator watched.** In a third tmux window (`Ctrl-b c`; window 2 holds the tunnel), record the workstation's CPU every
5 s for the whole run. `-n` prints the header once, so the file holds only numbers after it.

```bash
cd ~/Anime-Recommender && vmstat -n -t 5 | tee ~/anime-evidence/ramp-vmstat.txt
```

In the first window, run the ramp: ten minutes up to 120 requests per second, the default.

```bash
cd ~/Anime-Recommender && export KUBECONFIG=$HOME/.kube/anime
make loadtest-ramp
```

Then stop `vmstat` in that third window (`Ctrl-c`). If 3.4 shows no break-away and no dropped iterations, the knee is
above the ramp: run again with `MAX_RPS=200 MAX_VUS=1500`. The knee must be inside the ramp to be measured.

**3.4 — read the run.** Queries use `[2m]`, four scrape intervals, so one late scrape does not put a gap exactly where
the knee is. Each point therefore describes the two minutes before it. The range starts two minutes after k6 did, so
no point averages in the idle time before the run.

```bash
cd ~/Anime-Recommender && export KUBECONFIG=$HOME/.kube/anime
S0=$(cat ~/anime-evidence/ramp.start); E=$(cat ~/anime-evidence/ramp.end); R='route="/recommend"'
S=$(date -u -d "$S0 + 2 minutes" +%Y-%m-%dT%H:%M:%SZ)
q() { make -s prom-range START=$S END=$E STEP=30s Q="$1" | grep '@\[' ; }   # promtool prints "value @[timestamp]"
A='namespace="anime",pod=~"anime-api.*",container="api"'
echo "== p95 (s)";                q "histogram_quantile(0.95, sum by (le) (rate(anime_http_request_duration_seconds_bucket{$R}[2m])))" | tee ~/anime-evidence/ramp-p95.txt
echo "== served rate (req/s)";    q "sum(rate(anime_http_requests_total{$R}[2m]))"                               | tee ~/anime-evidence/ramp-rate.txt
echo "== error ratio";            q "(sum(rate(anime_http_requests_total{$R,status=~\"5..\"}[2m])) or vector(0)) / sum(rate(anime_http_requests_total{$R}[2m]))" | tee ~/anime-evidence/ramp-errors.txt
echo "== in-flight per pod";      q "avg(anime_http_requests_in_flight{job=\"anime/anime-api\"})"                | tee ~/anime-evidence/ramp-inflight.txt
echo "== CPU per pod (cores)";    q "max(rate(container_cpu_usage_seconds_total{$A}[2m]))"                       | tee ~/anime-evidence/ramp-cpu.txt
echo "== memory per pod (MiB)";   q "max(container_memory_working_set_bytes{$A}) / 2^20"                         | tee ~/anime-evidence/ramp-mem.txt
echo "== ready api pods";         q "sum(kube_pod_status_ready{namespace=\"anime\",pod=~\"anime-api.*\",condition=\"true\"})" | tee ~/anime-evidence/ramp-pods.txt
echo "== nodes";                  q "count(kube_node_info)"                                                      | tee ~/anime-evidence/ramp-nodes.txt
jq -r '.metrics | "k6: dropped iterations \(.dropped_iterations.count // 0), vus max \(.vus_max.max // .vus_max.value)"' ~/anime-evidence/ramp-summary.json
D1=$(awk -F, '$1=="dropped_iterations" {print $2; exit}' ~/anime-evidence/ramp-points.csv)
[ -n "$D1" ] && echo "first dropped iteration: $(date -u -d @$D1 +%FT%TZ) (@$D1)" || echo "no dropped iterations"
awk '$15 ~ /^[0-9]+$/ {print 100-$15"%", $(NF-1)"T"$NF}' ~/anime-evidence/ramp-vmstat.txt | sort -n | tail -1 \
  | sed 's/^/busiest workstation CPU sample: /'
```

Each series prints `value @[unix timestamp]`, one line per 30 s. The first p95 points may be `NaN` if a window held no
requests; skip them. Read them in this order:

1. **Low-load p95:** the average of the first four p95 values that are numbers.
2. **Knee:** the first point where p95 exceeds 1.5 × the low-load p95 (3.1).
3. **Capacity:** the served rate at the last point *before* the knee. It is reported as the sustained rate: before
   the knee, the served rate and the offered rate agree. It is valid only if both of these hold:
   - the first dropped iteration, if any, came after that point;
   - the workstation was not saturated, which means its busiest sample was below about 90% CPU. The `vmstat` timestamp
     is local time; compare it with the knee.

   If iterations were dropped earlier, find the owner (Load A4.3):
   - the workstation was idle and `vus max` was far below `MAX_VUS`: the pods' limit;
   - `vus max` was near `MAX_VUS`: the script's limit, so rerun with a larger `MAX_VUS`;
   - the workstation was pinned: the generator's limit. The number then describes the test, and it is not used.
4. **Error ratio up to the knee:** reported beside the capacity.
5. **In-flight per pod at the knee:** the stage 7 threshold is set below this value (Load A4.5).
6. **CPU and memory per pod at the knee:** the api's resource requests come from these (Load A4.5).
7. **Ready pods and nodes over the run:** they should stay at `2` and `2`. A change means a pod restarted or a node
   was lost during the run, and that has to be reported with the number.

Report the readings, the factor from 3.1, and the raw files if anything is ambiguous.

**3.5 — back to real mode.**

```bash
cd ~/Anime-Recommender && export KUBECONFIG=$HOME/.kube/anime
sed -i 's/^api_llm_provider .*/api_llm_provider          = "openai"/' infra/terraform/bootstrap/terraform.tfvars
make bootstrap-plan && make bootstrap
kubectl -n argocd annotate application root argocd.argoproj.io/refresh=hard --overwrite
mode() { kubectl -n anime get deploy anime-api -o jsonpath='{.spec.template.spec.containers[0].env[?(@.name=="LLM_PROVIDER")].value}'; }
for i in $(seq 20); do [ "$(mode)" = openai ] && break; sleep 15; done; echo "template provider: $(mode)"
kubectl -n anime rollout status deploy/anime-api --timeout=5m
```

Expected: `template provider: openai`, `successfully rolled out`. To run the real mode on Gemini instead, use `gemini` wherever these blocks write `openai` (design §4.1).

---

## 4. Evidence

Report:
- T and the four lines behind it (2.2);
- the ramp's readings and the factor (3.4);
- `cat ~/anime-evidence/*-k6-image.txt`.

Every figure carries its mode: T is **real mode, `gpt-4o-mini` on openai**, capacity is **fake**. A fake-mode number is never compared with T
(Load A5.2). The figures become `docs/evidence/load.md`. The stage 7 threshold and the api's requests are then written
from them.

---

## Troubleshooting

| Symptom | Likely cause | What to do |
|---|---|---|
| `up{job="anime/anime-api"}` empty | PodMonitor not rendered, or not selected | `kubectl -n anime get podmonitor`; `load` in `enabled_stages`; the stack's selectors (stage 2 values) must be open |
| `up` is `0` | Scrape fails | Prometheus UI → Targets (through the VPN); `/metrics` must answer on port `http` |
| Request count empty after the probes | The route label differs, or no request reached the api | `make -s prom Q='count by (route) (anime_http_requests_total)'` |
| Request count is `1`, not `2` | All six probes landed on one pod | Send a few more probe requests and check again |
| 10 bucket lines, not 17 | The running image predates the bucket change | Check the digest in Git is CI's latest; stage 3, step 4 |
| `promtool: not found` or exec error | The Prometheus pod name differs | `kubectl -n monitoring get pods`; set `PROM_POD=` on the make command |
| Baseline count below 200 | Requests failed, or the run was cut short | Rerun; `RATE_PER_MINUTE` higher only if the tier allows it |
| Many 503s in the baseline | Provider rate limit or quota | Lower `RATE_PER_MINUTE`; report the error count with T — it flatters T |
| k6: `failed to handle the end-of-test summary`, no summary file | The container cannot write to `~/anime-evidence` | The Makefile runs k6 as your own uid; check `ls -ld ~/anime-evidence` is yours |
| `ramp-points.csv` missing | An old Makefile, or the ramp was stopped before k6 flushed | `git pull`; rerun the ramp |
| `template provider` still shows the old mode | Argo CD has not synced the root, or the child | `make apps`; `kubectl -n argocd get application anime-api -o jsonpath='{.status.sync.status}'` |
| The ramp's p95 never breaks away | The knee is above `MAX_RPS` | Rerun with a larger `MAX_RPS` and `MAX_VUS` |
| Dropped iterations from the first minutes | `MAX_VUS` too small, or the workstation too small | Rerun with a larger `MAX_VUS`; check `vmstat` |
| p95 breaks away immediately | The api is still rolling to fake mode, or pods are restarting | `kubectl -n anime get pods`; restarts → liveness under load (report) |
| CPU or memory series empty | cAdvisor metrics not scraped, or container name differs | `make -s prom Q='count by (container) (container_cpu_usage_seconds_total{namespace="anime"})'` |

---

[README](README.md) · [Concepts](concepts.md) · [Design §4.5](../eks-sre-llmops-design.md#45-autoscaling-and-load-testing) ·
Previous: [CI/CD guide](../3-cicd/guide.md)
