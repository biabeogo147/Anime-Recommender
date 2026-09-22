# Stage 6 — Guide: alerts built from the budget, and a page that reaches a person

Commands and checks only. The reasoning is in the comments of these files:
- `deploy/slo/anime-api.sloth.yaml` (the objectives);
- the `slo-generate` and `slo-check` targets of the `Makefile`, and the `sloth generate diff` step of `ci.yml`;
- `deploy/argocd/root/templates/slo.yaml` and the `alertmanager:` block of `gitops-monitoring.yaml`;
- `deploy/platform/slo/externalsecret-alerting.yaml`;
- [the runbook](../runbooks/anime-api.md), which every alert links to;
- [README](README.md) · [concepts](concepts.md).

The "SLO A…" references are answers in [answers.md](answers.md).

Machines: **laptop** (git, browser), **ops** (inside tmux; start each block with
`cd ~/Anime-Recommender && export KUBECONFIG=$HOME/.kube/anime`). The drill needs about **two and a half hours** of
cluster time: one hour of clean traffic, then the fault and its recovery.

**This build runs the short drill.** Design §4.3 describes three clean hours, which let the calibrated 1h/5m pair fire
first. Here there is about one clean hour, so the 6h/30m pair will probably fire first, at about 4 minutes. The page then
proves that a fast burn reaches a person, and how long that took from the fault. The calibrated 1h/5m pair is still
measured: its 1-hour window holds a full clean hour, so its own crossing time (3.4) is the calibrated one, about
8 minutes. The evidence records both, and which paged; the CV claims only the time to the Discord page.

Criterion closed ([design §6](../eks-sre-llmops-design.md#6-verification-and-evidence-definition-of-done)):
- **#10:** the fast-burn page reaches Discord during the fault drill. The evidence is the time to alert in its parts,
  the `alertname` and objective, and which pair fired, read from each window's burn rate.

One webhook, one channel: pages and tickets arrive in the same Discord channel, told apart by `[PAGE]` and
`[TICKET]` in the title.

---

## 0. The rules, generated once — laptop, browser, ops

The latency objective needs T, which stage 4 measured. Sloth runs only in containers — on ops, or in CI — never on the
laptop, so the generated rules reach Git through CI. From stage 3 on, `main` accepts changes only through a pull
request with `ci-ok` green, so this goes through one pull request. The Sloth image and `actions/upload-artifact` were
pinned in stage 2's pins round; without those pins no artifact would be produced.

**0.1 — report T.** It is the `le=` value printed in stage 4, 2.2, exactly as printed (for example `3.0`, not `3`).
I write it into `deploy/slo/anime-api.sloth.yaml` in place of `PIN_ME_T` and commit it on a branch. You push the
branch and open a pull request.

**0.2 — browser: take the rules CI generated.** The pull request's `lint-test` job fails at `sloth generate diff`,
because no generated file is committed yet. That failure is expected; nothing is released from a pull request anyway.
On the run's summary page, download the artifact **`slo-regenerated`**. Unzip it, and put `anime-api.yaml` at
`deploy/slo/generated/anime-api.yaml` in the laptop's repository, on the same branch. I commit it; you push. The next
run must show `SLO rules match the spec` and `ci-ok` green. Then merge the pull request.

**0.3 — ops: the rules are what the design says.**

```bash
cd ~/Anime-Recommender && export KUBECONFIG=$HOME/.kube/anime
git pull --ff-only
G=deploy/slo/generated/anime-api.yaml; T=$(sed -n 's/.*le="\([^"]*\)".*/\1/p' deploy/slo/anime-api.sloth.yaml)
make -s slo-check
grep -E '^(kind|  name):' $G
grep -c 'record:' $G; grep -c 'alert:' $G
grep -oE '\(([0-9.]+) \* ' $G | sort | uniq -c   # each alert's burn-rate factors, written as (factor * budget)
echo "T=$T"; grep -c "le=\"$T\"" $G; grep -c 'le="PIN_ME_T"' $G
```

Expected:
- `SLO rules match the spec`;
- `kind: PrometheusRule` and `  name: anime-api`;
- `16` recording rules (per objective, eight windows and eight meta rules) and `4` alert rules (page and ticket for
  each objective). Write both down, for 2.1;
- the 28-day factors, printed as full floats, four of each: `(13.44 *`, `(5.6000000000000005 *`,
  `(2.8000000000000003 *` and `(0.9333333333333333 *`. The 30-day set (`14.4`, `6`, `3`, `1`) means the period flag
  did not take (design §4.3): stop and report it;
- `T=<your value>`, then a count above `0`, then `0`: T is pinned, and the rules use it.

**0.4 — ops: the webhook is set.** It was written in stage 1, 2.5. From this stage on, a missing value stops every
bootstrap at wave -1, so check it first. If it is missing, write it now the same way.

```bash
cd ~/Anime-Recommender && export KUBECONFIG=$HOME/.kube/anime
aws secretsmanager get-secret-value --region ap-southeast-1 --secret-id anime/alerting \
  --query SecretString --output text | jq -c 'map_values(length)'
```

Expected: `{"DISCORD_WEBHOOK_URL":<about 120>}`.

---

## 1. Switch the stage on — ops

This renders two Applications: `alerting-secret` (wave -1) and `slo` (wave 2). It also mounts the Secret into
Alertmanager, and gives Alertmanager the two Discord routes. The merge in 0.2 was a new commit, so CI released new
image digests, and the Rollout may be paused on an inconclusive canary. Check that first.

```bash
cd ~/Anime-Recommender && export KUBECONFIG=$HOME/.kube/anime
make -s rollout-status
```

Expected: `phase=Healthy`, with `stable` equal to `latest`. If it is `Paused` on an inconclusive analysis, run the
promotion drill's traffic and let it walk, or push it through as a configuration change
([stage 5, 3.4](../delivery/guide.md#3-criterion-8--the-promotion-drill--ops-window-1)). Then:

```bash
cd ~/Anime-Recommender && export KUBECONFIG=$HOME/.kube/anime
F=infra/terraform/bootstrap/terraform.tfvars
sed -i 's/^enabled_stages .*/enabled_stages            = ["gitops", "load", "delivery", "slo"]/' $F
grep '^enabled_stages' $F
make bootstrap-plan && make bootstrap
kubectl -n argocd annotate application root argocd.argoproj.io/refresh=hard --overwrite
for i in $(seq 40); do
  s=$(kubectl -n argocd get application slo -o jsonpath='{.status.sync.status}/{.status.health.status}' 2>/dev/null)
  [ "$s" = Synced/Healthy ] && break; sleep 15
done; echo "slo: $s"
make -s apps
```

Expected: `Plan: 0 to add, 1 to change`, then `slo: Synced/Healthy`. The list gains `alerting-secret` and `slo`, and
every Application is `Synced`/`Healthy`.

---

## 2. Loaded, routed, delivered — before any drill — ops

Each check here closes one of criterion #10's false passes before the drill can be blamed for it.

**2.1 — Prometheus has LOADED the rules.** The cluster accepting a PrometheusRule proves nothing: one the stack does
not select is kept and ignored (SLO A4.2). Prometheus's own metrics say what it evaluates.

```bash
cd ~/Anime-Recommender && export KUBECONFIG=$HOME/.kube/anime
kubectl -n monitoring get prometheusrule anime-api -o name
sleep 60
make -s prom Q='count(prometheus_rule_group_rules{rule_group=~".*sloth-slo-.*anime-api.*"})'
make -s prom Q='sum(prometheus_rule_group_rules{rule_group=~".*sloth-slo-.*anime-api.*"})'
make -s prom Q='sum(prometheus_rule_evaluation_failures_total{rule_group=~".*sloth-slo-.*anime-api.*"})'
```

Expected: the PrometheusRule exists; `6` rule groups (recordings, meta recordings and alerts, for each objective);
`20` rules (16 recording plus 4 alert, as counted in 0.3); `0` evaluation failures. An empty answer means the rules
were not loaded: see troubleshooting.

**2.2 — Alertmanager has the routes, and can read the webhook.**

```bash
cd ~/Anime-Recommender && export KUBECONFIG=$HOME/.kube/anime
AM="kubectl -n monitoring exec alertmanager-kube-prometheus-stack-alertmanager-0 -c alertmanager --"
$AM amtool config routes show --alertmanager.url=http://localhost:9093
$AM sh -c 'test -s /etc/alertmanager/secrets/anime-alerting/DISCORD_WEBHOOK_URL && echo "webhook file present"'
```

Expected: a tree with `receiver: null` at the root, and two children, `{severity="page"}` → `discord-page` and
`{severity="ticket"}` → `discord-ticket`. Then `webhook file present`. The old tree, without the two children, means
the new configuration was not applied: see troubleshooting.

**2.3 — a test page reaches Discord.** This proves delivery on its own, with no rule involved. The drill would
otherwise be the first attempt, and a refused webhook would look like a rule that never fired (SLO A8.1).

```bash
cd ~/Anime-Recommender && export KUBECONFIG=$HOME/.kube/anime
AM="kubectl -n monitoring exec alertmanager-kube-prometheus-stack-alertmanager-0 -c alertmanager --"
$AM amtool alert add AnimeDeliveryTest severity=page --annotation='summary="delivery test, ignore"' \
  --end="$(date -u -d '+5 minutes' +%FT%TZ)" --alertmanager.url=http://localhost:9093
sleep 60
make -s prom Q='sum by (integration) (alertmanager_notifications_total{integration="discord"})'
make -s prom Q='sum by (integration) (alertmanager_notifications_failed_total{integration="discord"})'
```

Expected: within about a minute, a `[PAGE] AnimeDeliveryTest FIRING` message in the Discord channel, and about five
minutes later `[PAGE] AnimeDeliveryTest RESOLVED`. The attempted count is at least `1`, and the failed count is `0`.
A failed count above zero means Discord refused the webhook: check the URL in 0.4.

---

## 3. Criterion #10 — the alert drill — ops

The arithmetic is in design §4.3. The fault is 50% of requests, at **all** traffic: a canary's share would dilute it
below the page threshold.

**3.1 — fake mode, then an hour of clean traffic.** Put the api in fake mode with **only the mode-switch block**
of [stage 5, section 2](../delivery/guide.md#2-fake-mode-for-the-drills--ops), if it is not already. Do not start that
section's 45-minute k6. Then, in window 2, two and a half hours of traffic, which covers the clean hour, the fault, the
recovery and the half hour until the page resolves:

```bash
cd ~/Anime-Recommender && DURATION=2h30m make loadtest-steady
```

After **one hour**, in window 1, check that the store really holds clean traffic, and how old it is:

```bash
cd ~/Anime-Recommender && export KUBECONFIG=$HOME/.kube/anime
R='route="/recommend"'
{
make -s prom Q="sum(increase(anime_http_requests_total{$R}[1h]))"
make -s prom Q="sum(increase(anime_http_requests_total{$R,status=~\"5..\"}[1h])) or vector(0)"
make -s prom Q='(time() - min(prometheus_tsdb_lowest_timestamp_seconds)) / 3600'
} | tee ~/anime-evidence/alert-clean.txt
make -s rollout-status
```

Expected:
- about 72,000 requests (20 per second for an hour), and `0` errors or very close;
- the store's age in hours;
- `phase=Healthy`, with `stable` equal to `latest`. A Rollout that is not Healthy here means the clean hour ran on a
  canary split: stop, and see troubleshooting.

Fewer requests, or errors, mean the hour is not clean: wait a little longer (the k6 run has about ten minutes of
spare), or report it.

**3.2 — the fault, promoted straight to all traffic.** The times and hashes are written to files, for 3.4 and 3.5.

```bash
cd ~/Anime-Recommender && export KUBECONFIG=$HOME/.kube/anime
E=~/anime-evidence; mkdir -p $E
kubectl -n anime get rollout anime-api -o jsonpath='{.status.stableRS}' > $E/alert.clean-hash
sed -i 's/^api_fault_rate .*/api_fault_rate            = "0.5"/' infra/terraform/bootstrap/terraform.tfvars
make bootstrap-plan && make bootstrap
kubectl -n argocd annotate application root argocd.argoproj.io/refresh=hard --overwrite
# Wait until the FAULTY version exists (a new latest hash), so promote-full promotes it and nothing else.
ok=; for i in $(seq 60); do
  l=$(make -s rollout-status); echo "$l" | grep -q "latest=$(cat $E/alert.clean-hash) " || { ok=1; break; }; sleep 5
done
[ -n "$ok" ] && make -s promote-full || echo "NO NEW VERSION STARTED: promote-full not run, see troubleshooting"
for i in $(seq 60); do make -s rollout-status | grep -q 'phase=Healthy' && break; sleep 5; done
date -u +%FT%TZ | tee $E/alert.fault
kubectl -n anime get rollout anime-api -o jsonpath='{.status.stableRS}' | tee $E/alert.fault-hash; echo
make -s rollout-status
```

Expected: `Plan: 0 to add, 1 to change`, `patched`, then `phase=Healthy` with `stable` equal to `latest`, and a hash
different from `alert.clean-hash`. The file `alert.fault` holds the moment the faulty version had all traffic.

**3.3 — wait for the page.** By the arithmetic, it comes in about 4 minutes on a one-hour store (the 6h/30m pair;
about 8 if the 1h/5m pair wins), plus scrape, evaluation and grouping.
The ticket arrives first — its pairs cross within a couple of minutes — and is not the page.

```bash
cd ~/Anime-Recommender && export KUBECONFIG=$HOME/.kube/anime
rm -f ~/anime-evidence/alert.firing-seen
for i in $(seq 120); do
  make -s prom Q='ALERTS{alertname="AnimeApiAvailabilityBudgetBurn",severity="page",alertstate="firing"}' | grep -q '=>' \
    && { date -u +%FT%TZ | tee ~/anime-evidence/alert.firing-seen; break; }
  sleep 10
done
[ -f ~/anime-evidence/alert.firing-seen ] || echo "NO PAGE WITHIN 20 MINUTES — see troubleshooting"
```

Note the time of the `[PAGE] AnimeApiAvailabilityBudgetBurn FIRING` message in Discord: hover over it to see it.
That is the last part of the sum.

**3.4 — the parts, and which pair fired.** Sloth's alerts have no `for:`, so an alert fires on the first evaluation
that sees its condition; there is no pending state. The page is the OR of two pairs, so each pair's own condition is
followed separately, and the one that became true first is the one that fired. Run this block **ten minutes after
the page**, with the fault still on (before 3.5): the range reaches ten minutes past the page, so the 1h/5m pair's
own crossing is inside it even when the 6h/30m pair paged first.

```bash
cd ~/Anime-Recommender && export KUBECONFIG=$HOME/.kube/anime
E=~/anime-evidence; F0=$(cat $E/alert.fault); FS=$(cat $E/alert.firing-seen)
S=$(date -u -d "$F0 - 2 minutes" +%FT%TZ); End=$(date -u -d "$FS + 10 minutes" +%FT%TZ)
# The first 15-second point where the expression has a value above zero, as a UTC time.
first() {
  t=$(make -s prom-range START=$S END=$End STEP=15s Q="$1" | awk '/@\[/ && $1+0 > 0 {gsub(/[^0-9.]/,"",$2); print $2; exit}')
  [ -n "$t" ] && date -u -d "@${t%.*}" +%FT%TZ || echo "(none)"
}
SLO='sloth_slo="requests-availability"'
br() { echo "(slo:sli_error:ratio_rate$1{$SLO} / on(sloth_id) group_left slo:error_budget:ratio{$SLO})"; }
{
echo "fault at all traffic:              $F0"
echo "first failed request scraped:      $(first 'sum(increase(anime_http_requests_total{route="/recommend",status=~"5.."}[1m]))')"
echo "5m error ratio recorded:           $(first "slo:sli_error:ratio_rate5m{$SLO}")"
echo "pair 1h/5m  over 13.44:            $(first "count($(br 5m) > 13.44 and $(br 1h) > 13.44)")"
echo "pair 6h/30m over 5.6:              $(first "count($(br 30m) > 5.6 and $(br 6h) > 5.6)")"
echo "page alert firing:                 $(first 'count(ALERTS{alertname="AnimeApiAvailabilityBudgetBurn",severity="page",alertstate="firing"})')"
echo "seen firing by the poll (±10 s):   $FS"
} | tee $E/alert-timeline.txt
AT=$(sed -n 's/^page alert firing: *//p' $E/alert-timeline.txt)
for w in 5m 30m 1h 6h 2h 1d 3d; do
  printf '%-4s burn rate at firing: ' $w
  make -s prom AT=$AT Q="$(br $w)" | grep -oE '=> [0-9.e+-]+' || echo "(none)"
done | tee $E/alert-burn.txt
make -s prom AT=$AT Q='ALERTS{alertname="AnimeApiAvailabilityBudgetBurn",severity="page",alertstate="firing"}' \
  | tee $E/alert-labels.txt
make -s prom AT=$AT Q='sum(rate(anime_http_requests_total{route="/recommend",status=~"5.."}[5m])) / sum(rate(anime_http_requests_total{route="/recommend"}[5m]))' \
  | tee $E/alert-error-ratio.txt
make -s prom AT=$AT Q='sum(increase(alertmanager_notifications_failed_total{integration="discord"}[30m]))' \
  | tee $E/alert-delivery-failures.txt
```

Read the output:
- **The timeline** is the time to alert in its parts, at 15-second resolution:
  - fault → first failed request scraped: the scrape;
  - → 5-minute ratio recorded: the recording rules;
  - → a pair true, and the alert firing: the window arithmetic and the evaluation;
  - → the Discord message (3.3): Alertmanager's 30-second `group_wait`, and delivery.

  Alertmanager's own send counter cannot say which message was the page: both routes use the same integration, and
  the ticket is sent first. So that step is read from the Discord time.
- **Which pair fired:** the pair whose line has the earlier time. The 1h/5m pair is the calibrated one. If the 6h/30m
  pair came first, the page came from the uncalibrated pair (SLO README, Decision 4): record it as that.
- **The burn rates at firing**, for every window, as the numbers behind that answer. The ticket pairs (`2h`/`1d`,
  `6h`/`3d`) will also be over their factors, and are recorded as uncalibrated.
- **The labels**, on the `severity="page"` series: `alertname`, `severity="page"`, and
  `sloth_slo="requests-availability"` (the objective).
- **The service's error ratio** is close to `0.5`: the fault reached all traffic, not a canary's share.
- **Delivery failures** are `0`.

**3.5 — end the fault.** Reverting is a new version again, the good one, and k6 is still sending traffic, so it walks
through the canary analysis against the faulty stable. Faulty requests take as long as good ones, since the fake
provider waits its full latency before failing, so the latency ratio is about 1 and the canary should pass.

```bash
cd ~/Anime-Recommender && export KUBECONFIG=$HOME/.kube/anime
E=~/anime-evidence; FAULT=$(cat $E/alert.fault-hash)
sed -i 's/^api_fault_rate .*/api_fault_rate            = "0"/' infra/terraform/bootstrap/terraform.tfvars
make bootstrap-plan && make bootstrap
kubectl -n argocd annotate application root argocd.argoproj.io/refresh=hard --overwrite
for i in $(seq 60); do
  l=$(make -s rollout-status); echo "$l" | tee -a $E/alert-recovery.txt
  echo "$l" | grep -q 'phase=Healthy' && ! echo "$l" | grep -q "stable=$FAULT " && { echo "recovered"; break; }
  echo "$l" | grep -qE 'abort=true|phase=Degraded|Inconclusive' && { echo "STOPPED — see troubleshooting"; break; }
  sleep 30
done
date -u +%FT%TZ | tee $E/alert.recovered
```

Expected: the canary walks 10 → 50 → 100 and the loop prints `recovered`. The `[PAGE] … RESOLVED` message comes
later: the page is `(5m and 1h) or (30m and 6h)`, and after 20 minutes or more of fault the 6h/30m pair is usually true
too, so it resolves only once the 30-minute window has also fallen — about half an hour after the fault ended. Keep
k6 running until then. Stopped earlier, the ratios would go absent and the alert would resolve for lack of traffic,
not for recovery.

**3.6 — after the RESOLVED message**, stop k6 in window 2 (`Ctrl-c`). Then put the api back in gemini mode, as in
[stage 5, section 5](../delivery/guide.md#5-back-to-gemini--ops).

---

## 4. Evidence

Report the files in `~/anime-evidence/` whose names start with `alert`, and the Discord message times. They become
`docs/evidence/slo.md`:
- the time to alert in its parts;
- the `alertname`, severity and objective;
- which pair fired, with each window's burn rate at firing;
- the clean traffic before the fault, the store's age, and the service's error ratio during it.

---

## Troubleshooting

| Symptom | Likely cause | What to do |
|---|---|---|
| The push to `main` is rejected (GH013) | `main` takes changes only through a pull request | 0.1: a branch and a pull request |
| CI fails but there is no `slo-regenerated` artifact | The Sloth image or `upload-artifact` is still `PIN_ME`, or an earlier step failed | Stage 2's pins round; the job's log |
| CI: `sloth generate diff` fails after 0.2 | The downloaded file was changed, or a different Sloth image | Download the artifact again; `SLOTH_IMAGE` must be the pinned tag |
| 0.3 shows `14.4`, `6`, `3`, `1` | The 28-day period did not take | Check `--default-slo-period=28d` in the Makefile; the Sloth version's flag name |
| `slo` `Unknown`, "app path does not exist" | The generated file is not on `main` | 0.2, including the merge |
| `alerting-secret` Degraded | `anime/alerting` has no value, or External Secrets may not read it | 0.4; `kubectl -n monitoring describe externalsecret anime-alerting` |
| After a rebuild, the root stops at wave -1 | The same: from stage 6 on, every bootstrap waits for this secret | 0.4, then refresh the root |
| Alertmanager pod stuck `ContainerCreating` | The Secret it mounts does not exist | `alerting-secret` must be Healthy; `kubectl -n monitoring get secret anime-alerting` |
| 2.2 shows the old tree | The operator rejected the new configuration, and kept the old one | `kubectl -n monitoring logs deploy/kube-prometheus-stack-operator \| grep -i alertmanager`; `discord_configs` with `webhook_url_file` needs a recent Alertmanager |
| 2.1 empty | The rule is not selected, or not in the monitoring namespace | `kubectl -n monitoring get prometheusrule`; the stack's `ruleSelectorNilUsesHelmValues: false` (stage 2 values) |
| Evaluation failures above 0 | A query in the spec is wrong | Prometheus UI → Rules (through the VPN): the failing rule shows its error |
| No Discord message in 2.3, failed count 0 | The alert matched no route | 2.2's tree; `severity=page` exactly |
| Failed count above 0 | Discord refused the webhook | The URL in `anime/alerting`; test it with `curl` on ops |
| Rollout not Healthy at the end of 3.1 | A release (the merge's new digests) paused on an inconclusive canary | Let it walk under the running k6, or promote it as in stage 5, 3.4; then restart the clean hour |
| `NO PAGE WITHIN 20 MINUTES` | The fault is not reaching all traffic, or not injected | The error ratio in 3.4; the Rollout's template must show `FAULT_RATE=0.5` and `LLM_PROVIDER=fake` |
| The page came from 6h/30m | Expected in the short drill: one clean hour is too little for the 1h/5m pair to win | Record it as it is; only the three-hour drill of design §4.3 would change it |
| 3.5 `STOPPED` | The revert canary was judged against the faulty stable and failed, or paused | Read `make -s rollout`; push it through with `promote-full`, since the fault is what is being removed |
| The latency alert fires in the drill too | Faulty requests take as long as good ones, so latency should not burn | Report it with the latency burn rates; check T in the spec |

---

[README](README.md) · [Concepts](concepts.md) · [Design §4.3](../eks-sre-llmops-design.md#43-slos-and-alerting-deployslo) ·
[Runbook](../runbooks/anime-api.md) · Previous: [Delivery guide](../delivery/guide.md)
