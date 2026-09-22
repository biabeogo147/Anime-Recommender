# Runbook — anime-api

Each alert's `runbook_url` points at a section here. It was written before the drill that first fires the alert (design
§4.3). An alert that arrives with no instructions is an interruption, not a signal.

All commands run on **ops**, from `~/Anime-Recommender`, with `export KUBECONFIG=$HOME/.kube/anime`. The UIs (Grafana,
Prometheus, Alertmanager, Argo CD) are reachable only through the VPN.

**Page** (`severity=page`, the fast-burn pairs 1h/5m and 6h/30m): at this rate the 28-day budget is gone in about two
days (1h/5m, 13.44×) or five (6h/30m, 5.6×). Look now.
**Ticket** (`severity=ticket`, the slow-burn pairs 1d/2h and 3d/6h): look this week.

On this platform the Prometheus store is only a few hours old. Every pair except 1h/5m is computed from less data than
its name says, so read the burn rate of each window before trusting which pair fired (SLO README, Decision 4).

---

## Availability budget burn

*Alert:* `AnimeApiAvailabilityBudgetBurn`. More than the budgeted 0.5% of `/recommend` requests are failing with a 5xx.

**1. Is it real, and how bad?**

```bash
make -s prom Q='sum by (status) (rate(anime_http_requests_total{route="/recommend"}[5m]))'
make -s prom Q='slo:sli_error:ratio_rate5m{sloth_slo="requests-availability"} / on(sloth_id) group_left slo:error_budget:ratio{sloth_slo="requests-availability"}'
```

The first query shows which statuses are growing. The second is the current burn rate: 1 means the budget is spent
exactly over 28 days, and a page means above 13.44 over the last hour and 5 minutes.

**2. Which stage fails?**

```bash
make -s prom Q='sum by (stage) (rate(anime_upstream_errors_total[5m]))'
kubectl -n anime logs -l app=anime-api --since=10m --tail=200 | grep -i 'upstream failure' | tail -20
```

- `stage="llm"`: the model provider is failing, rate-limiting or out of quota. `503 Upstream model unavailable`.
- `stage="retrieval"`: the embedding call, or the index. `503 Retrieval unavailable`.
- Neither, with 5xx still rising: the failures are in the api itself. Read the pod logs for tracebacks.

**3. Did something just change?**

```bash
make -s rollout
kubectl -n argocd get application anime-api -o jsonpath='{.status.sync.revision}{"\n"}'
kubectl -n anime get rollout anime-api -o jsonpath='{.spec.template.spec.containers[0].env}{"\n"}'
```

- A canary running: the analysis should stop it. If it has not, abort it:
  `kubectl -n anime patch rollout anime-api --subresource=status --type merge -p '{"status":{"abort":true}}'`
- A version recently promoted: revert its change in Git (the digest in `deploy/charts/anime-api/values.yaml`, or the
  `api_*` value in `terraform.tfvars`) and apply. Git is the way back; a hand edit is undone by self-heal.
- `FAULT_RATE` above `0` on a fake-mode version: a drill is still in place. Set `api_fault_rate = "0"` and apply.

**4. Capacity?** Pods not ready, or restarting, fail requests too:

```bash
kubectl -n anime get pods -l app=anime-api -o wide
kubectl get nodes
```

**Resolved when** the 5-minute burn rate is back below 1, and the page clears on its own. Record the cause, the start
and end times, and the budget spent in the evidence or an incident note.

---

## Latency budget burn

*Alert:* `AnimeApiLatencyBudgetBurn`. More than 5% of `/recommend` requests are slower than T.

**1. How slow, and since when?**

```bash
make -s prom Q='histogram_quantile(0.95, sum by (le) (rate(anime_http_request_duration_seconds_bucket{route="/recommend"}[5m])))'
make -s prom Q='slo:sli_error:ratio_rate5m{sloth_slo="requests-latency"} / on(sloth_id) group_left slo:error_budget:ratio{sloth_slo="requests-latency"}'
```

**2. Model, retrieval, or queueing?**

```bash
make -s prom Q='histogram_quantile(0.95, sum by (le) (rate(anime_llm_request_duration_seconds_bucket{outcome="ok"}[5m])))'
make -s prom Q='histogram_quantile(0.95, sum by (le) (rate(anime_retrieval_duration_seconds_bucket[5m])))'
make -s prom Q='avg(anime_http_requests_in_flight{job="anime/anime-api"})'
```

- The model's p95 near the request's p95: the provider is slow. There is nothing to scale; wait or switch provider.
- Retrieval slow: the embedding service.
- Both fast while the request is slow, and in-flight high: requests are queueing for the thread pool. The service is
  over capacity. Is the autoscaler scaling (stage 7)? Are pods Pending for want of nodes?

**3. Did something just change?** As for availability, step 3.

**Resolved when** the 5-minute burn rate is back below 1.

---

## Silence during an incident

A known cause being worked on can be silenced in Alertmanager (through the VPN): **Silences → New**, matcher
`alertname=<the alert>`, a duration, and a comment naming the cause. Remove it when the fix is in. A silence left
behind hides the next incident; the page is the only thing watching.
