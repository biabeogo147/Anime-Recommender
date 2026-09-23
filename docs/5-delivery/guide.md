# Stage 5 — Guide: a release that judges itself

Commands and checks only. The reasoning is in the comments of these files:
- `deploy/charts/anime-api/templates/rollout.yaml`, `analysistemplate.yaml`, `service.yaml` and `ingress.yaml`;
- `deploy/charts/anime-api/values.yaml` (the `analysis:` thresholds);
- `deploy/argocd/root/templates/delivery-controllers.yaml` and `app.yaml`;
- the `rollout` and `promote-full` targets of the `Makefile`;
- [README](README.md) · [concepts](concepts.md).

The "Delivery A…" references are answers in [answers.md](answers.md).

Machines: **ops** only. Work inside tmux, and start each block with
`cd ~/Anime-Recommender && export KUBECONFIG=$HOME/.kube/anime`. Three tmux windows are used: window 1 for commands, window 2 for the tunnel
(stage 1, 4.2; never press `Ctrl-c` there), and window 3 for k6, opened with `Ctrl-b c`.

Criteria closed ([design §6](../eks-sre-llmops-design.md#6-verification-and-evidence-definition-of-done)):
- **#8:** a good version walks 10 → 50 → 100. The evidence is the Rollout timeline and each AnalysisRun's measured
  values, non-empty, taken on the canary's own hash.
- **#9:** a version with `LLM_PROVIDER=fake` **and** `FAULT_RATE=0.2` aborts itself. The evidence is the time to abort,
  the failing measurement, and the requests affected. It counts only after a non-zero canary error rate is shown.

How a version is made in this stage: every change to the api's pod template is a new version. The three used here are
all `terraform.tfvars` values, applied with `make bootstrap-plan && make bootstrap`:
- `api_llm_provider`: the mode (a real provider, `openai` or `gemini`, ↔ fake);
- `api_drill`: a marker annotation, and nothing else — the promotion drill;
- `api_fault_rate`: the rollback drill.

A new digest from CI walks the same steps. With no traffic, its analysis is inconclusive, and the Rollout pauses
(Delivery A6.2).

---

## 0. Before you start — ops

Stage 4 passed, and the api is in real mode (`openai`). The Argo Rollouts chart version was pinned in stage 2 with the others.
The first command checks that it is not `PIN_ME`.

```bash
cd ~/Anime-Recommender && export KUBECONFIG=$HOME/.kube/anime
git pull --ff-only
grep -n 'argoRollouts:' deploy/argocd/root/values.yaml
grep -E '^(enabled_stages|api_)' infra/terraform/bootstrap/terraform.tfvars
```

Expected: a version number after `argoRollouts:`. Then `["gitops", "load"]`, `openai`, `"0"`.

---

## 1. Switch the stage on — ops

**1.1 — add `delivery`.** This does three things:
- renders the Argo Rollouts controller (wave 0);
- turns the api into a Rollout, with the stable and canary Services and the weighted Ingress rule;
- points the UI at the stable Service.

The first Rollout has no stable version to compare with, so it goes straight to 100%. The old Deployment is pruned
only after the Rollout is healthy (`PruneLast`). Expect `api.<domain>` to return 503 for up to a minute during the
switch: the api rule moves to the new stable target group before its pods are registered and health-checked. Do it
with no traffic running.

```bash
cd ~/Anime-Recommender && export KUBECONFIG=$HOME/.kube/anime
F=infra/terraform/bootstrap/terraform.tfvars
sed -i 's/^enabled_stages .*/enabled_stages            = ["gitops", "load", "delivery"]/' $F
grep -q '^api_drill' $F || echo 'api_drill                 = ""' >> $F
grep -E '^(enabled_stages|api_)' $F
make bootstrap-plan
```

Expected: `delivery` in the list, the three `api_` lines, and `Plan: 0 to add, 1 to change, 0 to destroy.` Then:

```bash
cd ~/Anime-Recommender && export KUBECONFIG=$HOME/.kube/anime
make bootstrap
for i in $(seq 40); do
  h=$(kubectl -n argocd get application anime-api -o jsonpath='{.status.sync.status}/{.status.health.status}' 2>/dev/null)
  [ "$h" = Synced/Healthy ] && kubectl -n anime get rollout anime-api >/dev/null 2>&1 && break; sleep 15
done; echo "anime-api: $h"
make -s apps
```

Expected: `anime-api: Synced/Healthy`. The list has the stage 2 Applications plus `argo-rollouts`, all
`Synced`/`Healthy`.

**1.2 — the objects, by name.**

```bash
cd ~/Anime-Recommender && export KUBECONFIG=$HOME/.kube/anime
kubectl -n anime get deploy anime-api 2>&1 | tail -1
kubectl -n anime get rollout,svc,analysistemplate -l app!=anime-ui -o name
kubectl -n anime get svc anime-api-stable anime-api-canary -o jsonpath='{range .items[*]}{.metadata.name} selector={.spec.selector}{"\n"}{end}'
kubectl -n anime get ingress anime-public -o jsonpath='{.metadata.annotations.alb\.ingress\.kubernetes\.io/actions\.anime-api-stable}{"\n"}'
make -s rollout
```

Expected:
- `Error from server (NotFound)`: the Deployment is gone;
- `rollout.argoproj.io/anime-api`, the Services `anime-api`, `anime-api-stable` and `anime-api-canary`, and
  `analysistemplate.argoproj.io/success-rate-and-latency`;
- both Service selectors carry `rollouts-pod-template-hash`, and with no canary running it is the **same** hash;
- the action has weight `100` on `anime-api-stable` and `0` on `anime-api-canary`;
- `phase=Healthy`, with `stable` equal to `latest`, and `no AnalysisRun yet`.

**1.3 — the doors still work, and the hash reaches the series.** A canary query can only be about the canary if its
pods' series carry the hash (Delivery A4.1). The queries have no `job` filter on purpose: a second monitor scraping
the same pods would show up here as more than two targets. That is the double-scrape false pass in design §6, row 8.

```bash
cd ~/Anime-Recommender && export KUBECONFIG=$HOME/.kube/anime
curl -s -o /dev/null -w 'api: %{http_code}\n' https://api.anime.recruitai.io.vn/readyz
curl -s -o /dev/null -w 'ui:  %{http_code}\n' https://anime.recruitai.io.vn/
sleep 60
make -s prom Q='count(up{pod=~"anime-api-.*"} == 1)'
make -s prom Q='count(up{pod=~"anime-api-.*",rollouts_pod_template_hash!=""} == 1)'
make -s prom Q='count by (rollouts_pod_template_hash, job) (up{pod=~"anime-api-.*"} == 1)'
kubectl -n anime get rollout anime-api -o jsonpath='stable hash: {.status.stableRS}{"\n"}'
```

Expected:
- `api: 200` and `ui:  200`;
- `=> 2` and `=> 2`: two targets, and both carry a hash. An empty answer or `0` on the second means no hash reached
  the series: stop, and see troubleshooting;
- one line, with `job="anime/anime-api"` and the same hash as `stable hash:`.

---

## 2. Fake mode for the drills — ops

Both drills compare two versions in the same mode (Delivery A8.1). Switching the mode is itself a new version, and
nothing is sending it traffic. So its analysis is inconclusive, and the Rollout pauses. This one change is pushed
through with `promote-full`. It is a mode switch, not a release under test.

```bash
cd ~/Anime-Recommender && export KUBECONFIG=$HOME/.kube/anime
sed -i 's/^api_llm_provider .*/api_llm_provider          = "fake"/' infra/terraform/bootstrap/terraform.tfvars
make bootstrap-plan && make bootstrap
kubectl -n argocd annotate application root argocd.argoproj.io/refresh=hard --overwrite
ok=; for i in $(seq 40); do make -s rollout-status | grep -qE 'phase=(Paused|Progressing)' && { ok=1; break; }; sleep 15; done
# promote-full only once the new version has really started: on a Healthy Rollout it would be left pending.
[ -n "$ok" ] && make -s promote-full || echo "NO NEW VERSION STARTED: promote-full not run, see troubleshooting"
for i in $(seq 40); do make -s rollout-status | grep -q 'phase=Healthy' && break; sleep 15; done
make -s rollout-status
kubectl -n anime get rollout anime-api -o jsonpath='provider={.spec.template.spec.containers[0].env[?(@.name=="LLM_PROVIDER")].value}{"\n"}'
```

Expected: `Plan: 0 to add, 1 to change`, `Apply complete!`, a `patched` line, `phase=Healthy` with `stable` equal to
`latest` (a new hash), and `provider=fake`.

**Start the traffic.** In window 3, run k6 at 20 requests per second for the whole of sections 3 and 4. The rate is
set for the success-rate gate's resolution, not for the minimum-traffic guard (Delivery A5.3).

```bash
cd ~/Anime-Recommender && DURATION=45m make loadtest-steady
```

Leave it running. Wait two minutes before section 3, so the stable version has a full window of traffic to be
compared with.

---

## 3. Criterion #8 — the promotion drill — ops (window 1)

**3.1 — start a good version.** Only the drill marker changes, so the new version should be as good as the old one.
The start time is recorded for the timeline. A later promotion drill needs a new value (`promote-2`, …): the same
value again changes nothing, and the plan says `No changes`.

```bash
cd ~/Anime-Recommender && export KUBECONFIG=$HOME/.kube/anime
mkdir -p ~/anime-evidence
sed -i 's/^api_drill .*/api_drill                 = "promote-1"/' infra/terraform/bootstrap/terraform.tfvars
make bootstrap-plan && make bootstrap
date -u +%FT%TZ | tee ~/anime-evidence/promote.start
kubectl -n argocd annotate application root argocd.argoproj.io/refresh=hard --overwrite
```

**3.2 — watch it walk, and keep the timeline.** This takes about ten minutes: two steps, each a 2-minute pause
followed by four probes 30 s apart. The loop logs one line every 30 s and every AnalysisRun it sees, and stops once
the Rollout is Healthy on the new hash.

```bash
cd ~/Anime-Recommender && export KUBECONFIG=$HOME/.kube/anime
OLD=$(kubectl -n anime get rollout anime-api -o jsonpath='{.status.stableRS}'); echo "$OLD" > ~/anime-evidence/promote.old
echo "stable before: $OLD"
for i in $(seq 60); do
  make -s rollout >> ~/anime-evidence/promote-timeline.txt
  l=$(make -s rollout-status); echo "$l"
  echo "$l" | grep -q 'phase=Healthy' && ! echo "$l" | grep -q "stable=$OLD " && break
  # A timed pause is also phase=Paused; only an abort, Degraded or an inconclusive analysis means it stopped.
  echo "$l" | grep -qE 'abort=true|phase=Degraded|Inconclusive' && { echo "STOPPED — see 3.4"; break; }
  sleep 30
  [ $i -eq 60 ] && echo "TIMED OUT after about 30 minutes — see 3.4"
done
date -u +%FT%TZ | tee ~/anime-evidence/promote.end
```

Expected: the weight reads `0%` until Argo CD has synced, then `10%` → `50%`. A `100%` line may appear for a moment
at the end, just before the canary becomes the stable and the weight returns to `0%`. The loop ends on
`phase=Healthy` with a new `stable`. `STOPPED` means the analysis said no, or could not decide: go to 3.4.

**3.3 — the evidence: both AnalysisRuns, their values, and their hashes.**

```bash
cd ~/Anime-Recommender && export KUBECONFIG=$HOME/.kube/anime
OLD=$(cat ~/anime-evidence/promote.old); NEW=$(kubectl -n anime get rollout anime-api -o jsonpath='{.status.stableRS}')
echo "old stable $OLD, new stable $NEW"
for r in $(kubectl -n anime get analysisrun --sort-by=.metadata.creationTimestamp -o name | tail -2); do
  kubectl -n anime get $r -o json | jq -r '"\(.metadata.name) \(.status.phase) \([.spec.args[] | "\(.name)=\(.value)"] | join(" "))",
    (.status.metricResults[]? | "  \(.name): " + ([.measurements[]? | "\(.phase)=\(.value // "-")"] | join(" ")))'
done | tee ~/anime-evidence/promote-analysis.txt
S=$(cat ~/anime-evidence/promote.start); E=$(cat ~/anime-evidence/promote.end)
W=$(( $(date -d "$E" +%s) - $(date -d "$S" +%s) ))s
make -s prom AT=$E Q="sum by (rollouts_pod_template_hash) (increase(anime_http_requests_total{route=\"/recommend\",rollouts_pod_template_hash=~\"$OLD|$NEW\"}[$W]))" \
  | tee ~/anime-evidence/promote-requests.txt
```

Check each of these:
- two AnalysisRuns, both `Successful`;
- in each, `canary-hash` is **`$NEW`** and `stable-hash` is **`$OLD`**. A canary hash equal to the stable one is the
  false pass in design §6, row 8;
- every measurement is a number. `success-rate` is at or above 0.99, and `latency-ratio` is at or below 1.2. An empty
  `[]` value is a query that matched nothing;
- `canary-requests` is near what the traffic predicts: about **240** per window at the 10% step, and about **1,200**
  at 50% (20 requests per second, over 2 minutes). Values about twice that mean each pod is scraped twice — the
  guard would pass on half the traffic it asks for (design §6, row 8);
- the last query returns both hashes with non-zero counts: each version really served requests in the window.

**3.4 — if it stopped.**
- `Paused` with an `Inconclusive` AnalysisRun: too little canary traffic, or an empty series. Check that k6 is still
  running in window 3, then look at `canary-requests`. Once traffic is back, rerun the analysis: abort, then retry
  (Delivery A7.2). **Never `promote-full` here** — that would promote on no evidence.

  ```bash
  kubectl -n anime patch rollout anime-api --subresource=status --type merge -p '{"status":{"abort":true}}'
  sleep 10
  kubectl -n anime patch rollout anime-api --subresource=status --type merge -p '{"status":{"abort":false}}'
  ```
- `abort=true`: a measurement failed, or the AnalysisRun went to `Error` (a query that errors, see troubleshooting).
  Read its values in 3.3. A good version failing is a finding to report, not to retry away.
- `TIMED OUT`: read `make -s rollout`; the troubleshooting rows on a Rollout that does not move.

---

## 4. Criterion #9 — the rollback drill — ops (window 1)

**4.1 — start a bad version.** The same mode, plus a 20% fault rate. The api is already in fake mode, so the fault
rate is real (Delivery A8.2).

```bash
cd ~/Anime-Recommender && export KUBECONFIG=$HOME/.kube/anime
grep '^api_llm_provider' infra/terraform/bootstrap/terraform.tfvars
sed -i 's/^api_fault_rate .*/api_fault_rate            = "0.2"/' infra/terraform/bootstrap/terraform.tfvars
make bootstrap-plan && make bootstrap
date -u +%FT%TZ | tee ~/anime-evidence/rollback.start
kubectl -n argocd annotate application root argocd.argoproj.io/refresh=hard --overwrite
```

Expected: `api_llm_provider          = "fake"`, then `Plan: 0 to add, 1 to change`.

**4.2 — wait for the abort.**

```bash
cd ~/Anime-Recommender && export KUBECONFIG=$HOME/.kube/anime
E=~/anime-evidence; rm -f $E/rollback.abort $E/rollback-time.txt
STABLE=$(kubectl -n anime get rollout anime-api -o jsonpath='{.status.stableRS}'); echo "$STABLE" > $E/rollback.stable
echo "stable: $STABLE"
for i in $(seq 90); do
  l=$(make -s rollout-status); echo "$l" | tee -a $E/rollback-timeline.txt
  echo "$l" | grep -q 'abort=true' && { touch $E/rollback.abort; break; }
  # The false pass of criterion #9: the bad version promoted, or paused for lack of evidence.
  echo "$l" | grep -q 'phase=Healthy' && ! echo "$l" | grep -q "stable=$STABLE " && { echo "NOT ABORTED: PROMOTED — drill failed"; break; }
  echo "$l" | grep -q 'Inconclusive' && { echo "NOT ABORTED: INCONCLUSIVE — drill failed, see 3.4"; break; }
  sleep 10
done
[ -f $E/rollback.abort ] || echo "NO ABORT RECORDED — stop here and report"
```

When it prints `abort=true`, read the times from the cluster, not from the loop. The loop only noticed the abort, and
it may have been started late.

```bash
cd ~/Anime-Recommender && export KUBECONFIG=$HOME/.kube/anime
E=~/anime-evidence
BAD=$(kubectl -n anime get rollout anime-api -o jsonpath='{.status.currentPodHash}'); echo "$BAD" > $E/rollback.bad
r=$(kubectl -n anime get analysisrun --sort-by=.metadata.creationTimestamp -o name | tail -1)
# Rollout start: when the canary ReplicaSet was created. Abort: when the failing measurement finished.
C=$(kubectl -n anime get rs -l rollouts-pod-template-hash=$BAD -o jsonpath='{.items[0].metadata.creationTimestamp}')
A=$(kubectl -n anime get $r -o json | jq -r '[.status.metricResults[]?.measurements[]? | select(.phase=="Failed") | .finishedAt] | sort | .[-1]')
echo "$C" > $E/rollback.canary-created; echo "$A" > $E/rollback.abort
{ echo "bad version $BAD, AnalysisRun ${r#*/}"
  echo "canary created: $C"; echo "failing measurement finished (abort): $A"
  echo "rollout start → abort: $(( $(date -d "$A" +%s) - $(date -d "$C" +%s) )) s"; } | tee $E/rollback-time.txt
```

Expected: the weight goes to `10%` once the canary pod is available: 30–90 s for startup, the index load and target
registration. After the 2-minute pause, the first probe fails, and the second, 30 s later, fails the run:
`abort=true`, with weight `0%`. So rollout start to abort is about **3 to 4 minutes**.

**4.3 — prove the canary really failed requests, then read the analysis.** A canary whose error count is zero makes
this drill worthless, whatever the Rollout did (design §6, row 9).

```bash
cd ~/Anime-Recommender && export KUBECONFIG=$HOME/.kube/anime
BAD=$(cat ~/anime-evidence/rollback.bad); C=$(cat ~/anime-evidence/rollback.canary-created)
A=$(cat ~/anime-evidence/rollback.abort)
# The window is the canary's life, from its creation to the abort — the share asked for is "while the canary was live".
W=$(( $(date -d "$A" +%s) - $(date -d "$C" +%s) ))s
R='route="/recommend"'
make -s prom AT=$A Q="sum(increase(anime_http_requests_total{$R,rollouts_pod_template_hash=\"$BAD\"}[$W]))"                      | tee ~/anime-evidence/rollback-canary-total.txt
make -s prom AT=$A Q="sum(increase(anime_http_requests_total{$R,rollouts_pod_template_hash=\"$BAD\",status=~\"5..\"}[$W]))"      | tee ~/anime-evidence/rollback-canary-errors.txt
make -s prom AT=$A Q="sum(increase(anime_http_requests_total{$R,status=~\"5..\"}[$W])) / sum(increase(anime_http_requests_total{$R}[$W]))" | tee ~/anime-evidence/rollback-affected.txt
r=$(kubectl -n anime get analysisrun --sort-by=.metadata.creationTimestamp -o name | tail -1)
kubectl -n anime get $r -o json | jq -r '"\(.metadata.name) \(.status.phase) \(.status.message // "")",
  ([.spec.args[] | "\(.name)=\(.value)"] | join(" ")),
  (.status.metricResults[]? | "  \(.name) \(.phase): " + ([.measurements[]? | "\(.phase)=\(.value // "-")"] | join(" ")))' \
  | tee ~/anime-evidence/rollback-analysis.txt
```

Expected:
- a canary total of more than 20, and a canary error count **above zero** — about a fifth of the total;
- the share of ALL requests that failed while the canary was live: about 2% or less (10% of the traffic, a fifth of
  it failing);
- an AnalysisRun `Failed`, with `canary-hash=$BAD`. In it, `success-rate` is `Failed` and has at least two `Failed`
  measurements, near 0.8.

If the Rollout aborted but the canary error count is zero, or the AnalysisRun is not the one that failed, the abort
came from something else (Delivery A8.3). Report it.

**4.4 — Git and the cluster disagree, on purpose, until Git changes.**

```bash
cd ~/Anime-Recommender && export KUBECONFIG=$HOME/.kube/anime
kubectl -n argocd get application anime-api -o jsonpath='{.status.sync.status}/{.status.health.status}{"\n"}'
sed -i 's/^api_fault_rate .*/api_fault_rate            = "0"/' infra/terraform/bootstrap/terraform.tfvars
make bootstrap-plan && make bootstrap
kubectl -n argocd annotate application root argocd.argoproj.io/refresh=hard --overwrite
for i in $(seq 40); do make -s rollout-status | grep -q 'phase=Healthy' && break; sleep 15; done
make -s rollout-status | grep -q "stable=$(cat ~/anime-evidence/rollback.stable) " && echo "back on the old stable" \
  || echo "NOT ON THE OLD STABLE"
kubectl -n argocd get application anime-api -o jsonpath='{.status.sync.status}/{.status.health.status}{"\n"}'
```

Expected: first `Synced/Degraded` (Delivery A7.1). After the revert, the template matches the stable version again,
so no canary starts: `back on the old stable`, then `Synced/Healthy`.

**4.5 — stop k6** in window 3 (`Ctrl-c`, if it has not finished). The window is still written.

---

## 5. Back to real mode — ops

This is a mode switch with no traffic again, so it is pushed through the same way as in section 2.

```bash
cd ~/Anime-Recommender && export KUBECONFIG=$HOME/.kube/anime
sed -i 's/^api_llm_provider .*/api_llm_provider          = "openai"/' infra/terraform/bootstrap/terraform.tfvars
make bootstrap-plan && make bootstrap
kubectl -n argocd annotate application root argocd.argoproj.io/refresh=hard --overwrite
ok=; for i in $(seq 40); do make -s rollout-status | grep -qE 'phase=(Paused|Progressing)' && { ok=1; break; }; sleep 15; done
# promote-full only once the new version has really started: on a Healthy Rollout it would be left pending.
[ -n "$ok" ] && make -s promote-full || echo "NO NEW VERSION STARTED: promote-full not run, see troubleshooting"
for i in $(seq 40); do make -s rollout-status | grep -q 'phase=Healthy' && break; sleep 15; done
kubectl -n anime get rollout anime-api -o jsonpath='provider={.spec.template.spec.containers[0].env[?(@.name=="LLM_PROVIDER")].value}{"\n"}'
```

Expected: `provider=openai`, `phase=Healthy`. To run the real mode on Gemini instead, use `gemini` wherever these blocks write `openai` (design §4.1).

---

## 6. Evidence

Report the files in `~/anime-evidence/` whose names start with `promote` and `rollback`. They become
`docs/evidence/delivery.md`:
- **#8:** the timeline, both AnalysisRuns with their values and hashes, and the per-hash request counts.
- **#9:** the time to abort, the canary's total and error counts, the failing AnalysisRun, and the share of requests
  affected.

---

## Troubleshooting

| Symptom | Likely cause | What to do |
|---|---|---|
| `argo-rollouts` `ComparisonError` on the chart | `argoRollouts` still `PIN_ME`, or a wrong version | Section 0; the pins round of stage 2 |
| `anime-api` stuck `OutOfSync`, Rollout kind unknown | The CRDs are not there yet | `make apps`: `argo-rollouts` must be Healthy first (wave 0) |
| The Deployment is still there after 1.1 | The sync did not finish, so `PruneLast` has not run | `kubectl -n argocd get application anime-api -o jsonpath='{.status.operationState.message}'` |
| `api` returns 503 after 1.1 | The Ingress action is missing, or target groups are empty | Annotation in 1.2; `kubectl -n kube-system logs deploy/aws-load-balancer-controller \| grep -i error \| tail` |
| The `ui` host also fails | The load balancer controller refuses the whole Ingress over one bad rule | The same log; the action JSON must name both Services |
| Hash count empty in 1.3 | The pods carry no hash yet, or `podTargetLabels` is missing | `kubectl -n anime get pods --show-labels`; the PodMonitor (stage 4) |
| The Rollout does not move after a bootstrap | Argo CD has not synced the child | Refresh root; `make apps`; the pod template must actually differ |
| The weight stays `0%` at a `10%` step | The load balancer controller did not apply the action | Its log; `kubectl -n anime describe ingress anime-public` (events) |
| Weights snap back to 100/0 during a canary | Self-heal is writing Git's starting value | `ignoreDifferences` on the anime-api Application (`app.yaml`) must be live: `kubectl -n argocd get application anime-api -o yaml \| grep -A4 ignoreDifferences` |
| Every AnalysisRun `Error`, message about the query | Prometheus address or query syntax | `kubectl -n anime get analysisrun <name> -o yaml` → `.status.metricResults[].message` |
| `consecutiveErrors (5) > consecutiveErrorLimit (4)` and the message names an expression function, e.g. `too many arguments to call isInf` | The success/failure **condition** does not compile, so every evaluation errors. The gate aborts a healthy version on its own fault, which looks exactly like a failed release | Read the message: it names the function. `isInf` here is expr-lang's unary predicate, not Go's `math.IsInf(f, sign)`. Fix the condition in `analysistemplate.yaml`, merge, let Argo CD sync, then rerun the drill with a **new** `api_drill` value (measured 2026-09-23) |
| `Inconclusive` at every step | Too little canary traffic, or empty series | Is k6 running? Is the canary in the ALB (weight > 0)? Does 1.3 show the hash? |
| The promotion drill aborts on `latency-ratio` | The canary is slower in its first minutes, or the stable window has too few samples | Report it with the values; do not change the threshold after the fact |
| The rollback drill promotes | The fault rate is not reaching a fake-mode canary | `BAD=$(cat ~/anime-evidence/rollback.bad); kubectl -n anime get pods -l rollouts-pod-template-hash=$BAD -o yaml \| grep -A1 -E 'LLM_PROVIDER\|FAULT_RATE'` |
| `promote-full`: `unknown flag: --subresource` | kubectl older than 1.24 | `kubectl version`; upgrade kubectl on ops |
| `promote-full`: `the server could not find the requested resource` | The Rollout's name or namespace is wrong, or the CRD has no status subresource | `kubectl -n anime get rollout anime-api`; `kubectl get crd rollouts.argoproj.io -o jsonpath='{.spec.versions[0].subresources}'` |
| `NO NEW VERSION STARTED` in sections 2 or 5 | Argo CD did not sync the change, or the template did not change | `make apps`; compare `terraform.tfvars` with the Rollout's env; nothing was promoted, so rerun the block |
| A step waits long at a `setWeight` | Target-group verification is waiting for the ALB | `kubectl -n argo-rollouts logs deploy/argo-rollouts \| grep -i verif \| tail`; an `AccessDenied` there means the Pod Identity role is missing (`make plan`) |

---

[README](README.md) · [Concepts](concepts.md) · [Design §4.4](../eks-sre-llmops-design.md#44-progressive-delivery-argo-rollouts) ·
Previous: [Load guide](../4-load/guide.md)
