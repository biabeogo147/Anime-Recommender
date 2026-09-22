# Stage 8 — Guide: one request, followed end to end, and what it cost

Commands and checks only. The reasoning is in the comments of these files:
- `src/anime/recommender.py` and `src/anime/telemetry.py` (the spans, the provider attribute, the content flag);
- `deploy/charts/anime-api/templates/_pod.tpl` (the `OTEL_*` environment);
- `deploy/argocd/root/templates/tracing.yaml` (Tempo, the collector and its two trace pipelines, the dashboards);
- the `grafana:` block of `gitops-monitoring.yaml` (the Tempo datasource and the exemplar link);
- `deploy/platform/tracing/externalsecret-langfuse.yaml`, and `deploy/dashboards/anime-llm.yaml`;
- [README](README.md) · [concepts](concepts.md).

The "Tracing A…" references are answers in [answers.md](answers.md).

Machines: **ops** (inside tmux; start each block with `cd ~/Anime-Recommender && export KUBECONFIG=$HOME/.kube/anime`),
and the **laptop's browser**, through the VPN, for Grafana and Langfuse.

Criteria closed ([design §6](../eks-sre-llmops-design.md#6-verification-and-evidence-definition-of-done)):
- **#11:** a gemini-mode `/recommend` trace shows retrieve and generate spans with **non-zero** tokens. The evidence
  is the span attributes as text, from Tempo **and** Langfuse. A fake-mode trace from the same session is in Tempo
  and absent from Langfuse.
- **#12:** the dashboard shows cost per 1,000 requests **in gemini mode**. The evidence is the value, the `model` label
  it is for, and the date in `config/pricing.yaml`.

---

## 0. Before you start — ops

The api is in **gemini** mode. `anime/langfuse` holds both keys (terraform guide, 2.5). The Langfuse region in
`deploy/argocd/root/values.yaml` (`langfuse.otlpEndpoint`) is the region of the project the keys belong to. From this
stage on, a missing key stops every bootstrap at wave -1, so it is checked first.

```bash
cd ~/Anime-Recommender && export KUBECONFIG=$HOME/.kube/anime
git pull --ff-only
aws secretsmanager get-secret-value --secret-id anime/langfuse --query SecretString --output text | jq -c 'map_values(length)'
grep -A1 '^langfuse:' deploy/argocd/root/values.yaml
kubectl -n anime get rollout anime-api -o jsonpath='provider={.spec.template.spec.containers[0].env[?(@.name=="LLM_PROVIDER")].value}{"\n"}'
```

Expected: both keys with a length, near 40 each; the endpoint of your region; `provider=gemini`.

---

## 1. Switch the stage on — ops

This renders four Applications: `tracing-secret` (wave -1), `tempo` and `opentelemetry-collector` (wave 0), and
`dashboards` (wave 1). It also adds the `OTEL_*` variables to the api's pods. That is a new pod template, so the
Rollout starts a canary that has no traffic to be judged on. It is pushed through as a configuration change, like a
mode switch.

```bash
cd ~/Anime-Recommender && export KUBECONFIG=$HOME/.kube/anime
F=infra/terraform/bootstrap/terraform.tfvars
sed -i 's/^enabled_stages .*/enabled_stages            = ["gitops", "load", "delivery", "slo", "scaling", "tracing"]/' $F
grep '^enabled_stages' $F
make bootstrap-plan && make bootstrap
kubectl -n argocd annotate application root argocd.argoproj.io/refresh=hard --overwrite
ok=; for i in $(seq 40); do make -s rollout-status | grep -qE 'phase=(Paused|Progressing)' && { ok=1; break; }; sleep 15; done
[ -n "$ok" ] && make -s promote-full || echo "NO NEW VERSION STARTED: promote-full not run, see troubleshooting"
for i in $(seq 40); do make -s rollout-status | grep -q 'phase=Healthy' && break; sleep 15; done
make -s apps
```

Expected: `Plan: 0 to add, 1 to change`, a `patched` line, and the list gains the four Applications, every one
`Synced`/`Healthy`.

**1.1 — wired as intended.**

```bash
cd ~/Anime-Recommender && export KUBECONFIG=$HOME/.kube/anime
kubectl -n anime get rollout anime-api -o json \
  | jq -r '.spec.template.spec.containers[0].env[] | select(.name | startswith("OTEL_")) | "\(.name)=\(.value)"'
kubectl -n tracing get pods
kubectl -n tracing logs deploy/otel-collector --tail=200 | grep -iE 'error|Everything is ready' | tail -5
kubectl -n tracing get secret anime-langfuse -o jsonpath='{.data.LANGFUSE_AUTH}' | wc -c
make -s prom Q='count(up{namespace="tracing"} == 1)'
```

Expected:
- `OTEL_EXPORTER_OTLP_ENDPOINT=http://otel-collector.tracing.svc.cluster.local:4318`,
  `OTEL_RESOURCE_ATTRIBUTES=anime.llm.provider=gemini`, `OTEL_CAPTURE_CONTENT=true`;
- the collector and Tempo pods `Running`;
- `Everything is ready` in the collector's log, and no errors;
- a non-zero length for `LANGFUSE_AUTH`;
- at least `1`: the collector's span-metrics endpoint is scraped.

---

## 2. Criterion #11 — a real request, in both sinks — ops

**2.1 — one gemini request, and its trace id.** The response carries the trace id (`trace_id`).

```bash
cd ~/Anime-Recommender && export KUBECONFIG=$HOME/.kube/anime
E=~/anime-evidence; mkdir -p $E
curl -s -X POST https://api.anime.recruitai.io.vn/recommend -H 'content-type: application/json' \
  -d '{"query":"a quiet slice-of-life about cooking"}' | tee $E/trace-gemini-response.json | jq -r '.model, .trace_id'
jq -r .trace_id $E/trace-gemini-response.json > $E/trace-gemini.id
```

Expected: the model's name (not `fake`), and a 32-character hex id. `null` means tracing is off in the pod: see 1.1.

**2.2 — from Tempo.** Wait 30 s for the batch and the export, then read the trace through a port-forward.

```bash
cd ~/Anime-Recommender && export KUBECONFIG=$HOME/.kube/anime
E=~/anime-evidence; ID=$(cat $E/trace-gemini.id)
sleep 30
kubectl -n tracing port-forward svc/tempo 3200:3200 >/dev/null 2>&1 & PF=$!; sleep 3
curl -s http://localhost:3200/api/traces/$ID > $E/trace-gemini-tempo.json; kill $PF
jq -r '[.. | objects | select(has("spanId") and has("name"))] | .[] |
  "\(.name)  kind=\(.kind)  " + ([.attributes[]? | "\(.key)=\(.value | to_entries[0].value)"
    | select(test("^(gen_ai|rag)\\.") and (test("messages=|observation") | not))] | join(" "))' \
  $E/trace-gemini-tempo.json | tee $E/trace-gemini-tempo.txt
jq -r '[.. | objects | select(has("key") and .key == "anime.llm.provider")][0].value.stringValue' $E/trace-gemini-tempo.json
```

Expected:
- a `POST /recommend` span; `rag.retrieve` with `rag.top_k` and `rag.docs_returned`; and `chat <model>`;
- on `chat <model>`: `kind=SPAN_KIND_CLIENT`, `gen_ai.provider.name=gcp.gemini`, `gen_ai.request.model=<model>`, and
  `gen_ai.usage.input_tokens` and `gen_ai.usage.output_tokens`, both **above zero**. Missing token attributes mean the
  provider reported no usage. Report that as it is: the code no longer writes a zero (Tracing A6.3);
- `gemini`: the resource attribute the Langfuse pipeline keys on.

**2.3 — from Langfuse.** The same trace id, read through Langfuse's public API with the project's keys
(`make langfuse-obs`, which prints the HTTP status first). Also open it in the browser: **Tracing → Traces**, search
the id, and check that the generation shows the prompt and the answer.

```bash
cd ~/Anime-Recommender && export KUBECONFIG=$HOME/.kube/anime
E=~/anime-evidence; ID=$(cat $E/trace-gemini.id)
make -s langfuse-obs ID=$ID | tee $E/trace-gemini-langfuse.txt
```

Expected: `langfuse http 200`, then observations for the same spans. The `chat` observation has type `GENERATION`,
the model, and non-zero input and output usage. `observations: 0` right away can be ingestion's delay: wait two
minutes and rerun. `401` is the keys or the region, never an absence. A persistent `0` is the false pass to rule out:
see troubleshooting.

**2.4 — a fake-mode request is in Tempo and not in Langfuse.** Put the api in fake mode with **only the first block**
of [stage 5, section 2](../delivery/guide.md#2-fake-mode-for-the-drills--ops) — not its k6 traffic. Then:

```bash
cd ~/Anime-Recommender && export KUBECONFIG=$HOME/.kube/anime
E=~/anime-evidence
curl -s -X POST https://api.anime.recruitai.io.vn/recommend -H 'content-type: application/json' \
  -d '{"query":"space bounty hunters"}' | jq -r '.model, .trace_id' | tee $E/trace-fake.txt
# A request right after the switch can still reach a draining gemini pod: the id only counts if the model says fake.
[ "$(head -1 $E/trace-fake.txt)" = fake ] || echo "NOT FAKE — send the request again"
ID=$(tail -1 $E/trace-fake.txt); sleep 60
kubectl -n tracing port-forward svc/tempo 3200:3200 >/dev/null 2>&1 & PF=$!; sleep 3
curl -s -o $E/trace-fake-tempo.json -w 'tempo: %{http_code}\n' http://localhost:3200/api/traces/$ID | tee -a $E/trace-fake.txt
kill $PF
jq -r '[.. | objects | select(has("key") and .key == "anime.llm.provider")][0].value.stringValue' $E/trace-fake-tempo.json \
  | sed 's/^/provider on the fake trace: /' | tee -a $E/trace-fake.txt
```

Expected: `fake` and an id; `tempo: 200`; `provider on the fake trace: fake`.

Then put the api back in gemini mode, as in [stage 5, section 5](../delivery/guide.md#5-back-to-gemini--ops), and
prove the absence **after** a later real trace has arrived. A later gemini trace that is visible means ingestion has
caught up past the fake one, so its absence is an answer and not a delay (design §6, row 11).

```bash
cd ~/Anime-Recommender && export KUBECONFIG=$HOME/.kube/anime
E=~/anime-evidence
L=$(curl -s -X POST https://api.anime.recruitai.io.vn/recommend -H 'content-type: application/json' \
  -d '{"query":"mecha with a quiet ending"}' | jq -r .trace_id); echo "later gemini trace: $L"
for i in $(seq 20); do make -s langfuse-obs ID=$L | grep -qE 'observations: [1-9]' && break; sleep 30; done
{ echo "== later gemini trace $L"; make -s langfuse-obs ID=$L | head -2
  echo "== fake trace $(tail -3 $E/trace-fake.txt | head -1)"; make -s langfuse-obs ID=$(sed -n 2p $E/trace-fake.txt) | head -2
} | tee $E/trace-fake-langfuse.txt
```

Expected: for the later gemini trace, `langfuse http 200` and `observations:` above zero; for the fake trace,
`langfuse http 200` and `observations: 0`. Any other status for either means the check did not run: it is not an
absence.

---

## 3. Criterion #12 — cost per 1,000 requests, in gemini mode — ops, then browser

**3.1 — some real traffic.** About 40 gemini requests in four minutes (the baseline script adds one minute to 30 at
10 per minute). The baseline target overwrites stage 4's `baseline*` files, so they are copied aside first.

```bash
cd ~/Anime-Recommender && export KUBECONFIG=$HOME/.kube/anime
kubectl -n anime get rollout anime-api -o jsonpath='provider={.spec.template.spec.containers[0].env[?(@.name=="LLM_PROVIDER")].value}{"\n"}'
mkdir -p ~/anime-evidence/stage4-baseline && cp -n ~/anime-evidence/baseline* ~/anime-evidence/stage4-baseline/
TARGET_REQUESTS=30 RATE_PER_MINUTE=10 make loadtest-baseline
```

**3.2 — the value, by model.** The panel's ratio, over a 10-minute window so the whole run is inside it. Run it within
ten minutes of 3.1.

```bash
cd ~/Anime-Recommender && export KUBECONFIG=$HOME/.kube/anime
M='model=~"gemini-.*|gemma-.*"'
make -s prom Q="1000 * sum by (model) (increase(anime_llm_cost_usd_total{$M}[10m])) / sum by (model) (increase(anime_llm_request_duration_seconds_count{outcome=\"ok\",$M}[10m]))" \
  | tee ~/anime-evidence/cost-per-1000.txt
make -s prom Q='sum by (model) (increase(anime_llm_cost_usd_total[10m]))' | tee ~/anime-evidence/cost-all-models.txt
grep -m1 'page last updated' config/pricing.yaml | tee ~/anime-evidence/cost-pricing-date.txt
grep -A2 "^  $(kubectl -n anime get rollout anime-api -o jsonpath='{.spec.template.spec.containers[0].env[?(@.name=="MODEL_NAME")].value}'):" config/pricing.yaml
```

Expected:
- one line with `model="<the real model>"` and a dollar value **above zero**, the cost per 1,000 requests. A
  confident `0` is the second false pass of criterion #12: a model missing from `config/pricing.yaml`, or one priced
  at zero (design §6, row 12);
- the second query may also show `model="fake"` from the drills. That is exactly what the panel's filter keeps out
  (Tracing A6.2);
- the pricing page's date, and the model's two non-zero prices.

**3.3 — the dashboard.** In the laptop's browser, through the VPN: `https://grafana.anime.recruitai.io.vn` → Dashboards
→ **Anime — LLM**. The **Cost per 1,000 requests** panel shows the same model and about the same value. Its legend
shows `model=<name>`, so the filter is visible. The **Span duration p95** panel shows exemplar dots; clicking one
opens the trace in Tempo. No dots means one of the four exemplar settings is missing (Tracing A4.2).

---

## 4. Evidence

Report the files in `~/anime-evidence/` whose names start with `trace` and `cost`, and say what the Langfuse page and
the Grafana panels showed. They become `docs/evidence/tracing.md`. Every figure names its mode: the traces are one
gemini and one fake, and the cost is gemini, for the named model.

---

## Troubleshooting

| Symptom | Likely cause | What to do |
|---|---|---|
| The root stops at wave -1 | `anime/langfuse` has no value, so `tracing-secret` is Degraded | Section 0; `kubectl -n tracing describe externalsecret anime-langfuse` |
| `trace_id` is `null` | Tracing is off in the pod | 1.1: `OTEL_EXPORTER_OTLP_ENDPOINT` on the Rollout; the pod must be of the new template |
| Tempo returns 404 for a fresh id | The collector did not export, or the batch is not flushed yet | Wait 30 s; `kubectl -n tracing logs deploy/otel-collector \| grep -i tempo` |
| Collector `CrashLoopBackOff` | Invalid config, or `LANGFUSE_AUTH` missing | Its log names the key; `kubectl -n tracing get secret anime-langfuse` |
| Langfuse `observations: 0` for the gemini trace too | The export is failing, or the wrong region | Collector log: `otlphttp/langfuse` with 401 (keys), 404 (endpoint or region) |
| Langfuse has the FAKE trace | The filter does not match | The trace's `anime.llm.provider` in Tempo; the filter in `tracing.yaml` |
| No token attributes on `chat` | The provider returned no usage metadata | Report it; the code writes none rather than a zero |
| Langfuse shows the generation with no prompt or answer | The attribute names are not the ones this Langfuse version maps | Look at the span's attributes in Langfuse's raw view; report which ones arrived |
| The cost query is empty | No real-model request succeeded in the window, or more than 10 minutes passed | 3.1 in gemini mode, then 3.2 at once |
| The cost is `0` | The model is not in `config/pricing.yaml`, or priced at zero | `kubectl -n anime logs -l app=anime-api \| grep -i pricing`; the model's entry |
| `NO NEW VERSION STARTED` in section 1 | Argo CD did not sync the change | [Delivery troubleshooting](../delivery/guide.md#troubleshooting); nothing was promoted, so rerun the block |
| `langfuse http 401` | Wrong keys, or the keys belong to another region | `anime/langfuse`; `langfuse.otlpEndpoint` in the root values |
| No exemplar dots in Grafana | One of the four exemplar settings is missing | The connector's `exemplars`, `enable_open_metrics`, Prometheus's `exemplar-storage`, the datasource's `exemplarTraceIdDestinations` |
| Span-metric panel empty | The metric name differs in this collector version | `make -s prom Q='count by (__name__) ({__name__=~"traces_span_metrics.*"})'` |

---

[README](README.md) · [Concepts](concepts.md) · [Design §4.2](../eks-sre-llmops-design.md#42-opentelemetry-and-llm-observability) ·
Previous: [Scaling guide](../scaling/guide.md)
