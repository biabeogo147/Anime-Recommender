# Anime Recommender — EKS, SRE and LLMOps (Ops Upgrade Design)

- **Date:** 2026-09-15
- **Timebox:** Days 4–7 of a 7-day plan shared with Medical-RAG-Chatbot (self-managed K8s)
- **Budget:** ~0.22 USD/hour while running; destroyed when idle
- **Target role:** DevOps / Platform / SRE, with LLMOps

## 1. Goal

Run this recommender on **Amazon EKS** the way a production SRE team would:

- **SLOs** with multi-window burn-rate alerting
- **Progressive delivery** (Argo Rollouts canary with automated Prometheus analysis and rollback)
- **Autoscaling** on the right signal (in-flight requests, not CPU)
- **Load-tested capacity numbers**
- **LLM observability:** OpenTelemetry `gen_ai.*` traces, token and cost metrics

Every P0 item must leave measurable evidence in `docs/evidence/`.

This is the **managed** counterpart to Medical-RAG-Chatbot, which runs self-managed kubeadm. Features are split deliberately:

| Concern | Medical (self-managed) | Anime (this repo, EKS) |
|---|---|---|
| Cluster | kubeadm on EC2 | EKS managed node group (Spot) |
| CI | Jenkins in-cluster | GitHub Actions (OIDC to AWS) |
| Image signing | Cosign + AWS KMS | Cosign keyless (GitHub OIDC / Sigstore) |
| Focus | Cluster ops, delivery, supply chain | SLOs, canary, autoscaling, LLM observability |

### Non-goals
- Custom domain or TLS (the ALB serves HTTP on its AWS DNS name).
- Multiple environments: a single `prod` namespace, with a canary instead of a dev env.
- Kyverno or etcd operations (those belong to Medical).
- Self-hosted Langfuse.

## 2. Current state (verified 2026-09-15)

- **App:** a single Streamlit process with LangChain RetrievalQA (default k=4) over a Chroma index of 269 anime.
  - Generation: Gemini API `gemma-3n-e2b-it`.
  - Embeddings: HF Inference API.
- **Metrics:** `prometheus_client` on :8000 (request/exception counters, latency histogram), scraped by a ServiceMonitor.
- **Deploy:** images `v1.0.1`–`v1.0.3` built by hand; one `llmops-k8s.yaml`; no CI.

**Known issues this design fixes:**
1. **Streamlit is not load-testable and has no API.** It talks over a websocket, so SLIs cannot be measured at the HTTP layer.
2. **The index is not reproducible.** `chroma_db/` is gitignored and baked from the local disk by `COPY . .`. A clean build silently ships an empty index.
3. **`LATENCY.observe(0.0)` records a fake zero sample** at startup, so the histogram count disagrees with the request count.
4. **Heavy dead dependency.** `sentence-transformers` (which pulls in PyTorch) is installed but unused since Sep 10 2025.
5. **Histogram too short.** The top bucket is 10s, too low for LLM calls.
6. **No health endpoints.** The probes hit `/`.

### Prerequisites
- AWS account and AWS CLI v2, Terraform ≥ 1.10, kubectl, Helm 3 (**to install**).
- GitHub repo admin, to create the OIDC trust and the Actions secrets and variables.
- An HF token **with the "Inference Providers" permission** and a Gemini API key.
- A Langfuse Cloud project (free tier) with its public and secret keys.
- A Discord (or Slack) incoming webhook URL for alerts.

## 3. Architecture

```
 User ─► ALB (AWS LBC, weighted target groups) ─┬─► anime-ui (Streamlit, Deployment) ──HTTP──┐
                                                └─► anime-api (FastAPI, Argo Rollout)  ◄───────┘
                                                        │ stable + canary Services
                                                        ├─► Chroma index (baked, validated in CI)
                                                        ├─► LLM provider: gemini | fake
                                                        └─► OTLP ─► OTel Collector ─┬─► Tempo (in-cluster)
                                                                                      ├─► Langfuse Cloud (OTLP/HTTP)
                                                                                      └─► spanmetrics ─► Prometheus
 Prometheus ◄─ ServiceMonitor(api) ─ Sloth-generated rules ─► Alertmanager ─► Discord
 KEDA ─(Prometheus: in-flight requests)─► HPA on the anime-api Rollout
 Argo Rollouts ─AnalysisRun(Prometheus: success rate, p95)─► promote | abort + rollback
 Argo CD ◄─ deploy/ in this repo ◄─ GitHub Actions (test → build → Trivy → ECR → cosign keyless → bump tag)
```

### AWS resources (Terraform, `infra/terraform/`)
- **State:** S3 backend with native lockfile.
- **Network:** VPC across 2 AZs with private node subnets and public ALB subnets, 1 NAT gateway. Subnet tags for AWS LBC discovery.
- **EKS** via `terraform-aws-modules/eks`:
  - Latest version in **standard support** at implementation time (pin exactly).
  - API endpoint public but **restricted to the operator's IP CIDR**, plus the private endpoint.
  - Access entries (no `aws-auth` ConfigMap).
- **Managed node group, Spot:**
  - Instance types `[t3.large, t3a.large, m5.large, m6i.large]`, desired 2, min 2, max 4.
  - gp3 encrypted volumes, IMDSv2 hop limit 1.
- **Addons:** vpc-cni, coredns, kube-proxy, aws-ebs-csi-driver, eks-pod-identity-agent.
- **Pod Identity associations:**
  - AWS Load Balancer Controller
  - external-secrets (read `anime/*` in Secrets Manager)
  - ebs-csi
- **Registry:** ECR `anime-api` and `anime-ui`, scan on push, lifecycle policy keeping the last 20 images.
- **GitHub OIDC provider and role:**
  - Trust is limited to `repo:biabeogo147/Anime-Recommender:ref:refs/heads/main`.
  - Permissions: push to the two ECR repos only.
- **Secrets Manager:**
  - `anime/llm`: GEMINI_API_KEY, HF_TOKEN
  - `anime/langfuse`: public/secret key
  - `anime/alerting`: Discord webhook
- **Budgets:** alarms at 50 and 100 USD. Default tags as in Medical.
- **Argo CD:** Terraform installs only Argo CD (`helm_release`) and applies the root app-of-apps. Everything else is reconciled from Git.

### In-cluster components (Argo CD apps, `deploy/argocd/apps/`)
Each component has a pinned chart version:

- aws-load-balancer-controller
- external-secrets
- kube-prometheus-stack: Prometheus retention 48h, Alertmanager with the Discord receiver
- argo-rollouts
- keda
- opentelemetry-collector (deployment mode)
- tempo (single binary, local PV)
- anime-api
- anime-ui

## 4. Components

### 4.1 App split (`src/anime/`, `services/api/`, `services/ui/`)

**Shared package `src/anime/`** holds the existing data loader, vector store, recommender and prompt, refactored behind interfaces:
- `Embeddings` with `hf-endpoint` and `fake` implementations.
- `LLM` with `gemini` and `fake` implementations.

The `fake` providers are selected by `LLM_PROVIDER=fake`:
- **Embeddings:** a deterministic 384-d hash vector, no network.
- **LLM:** sleeps `FAKE_LATENCY_MS` (lognormal around the configured median).
- **Errors:** raises with probability `FAULT_RATE`.
- **Tokens:** returns synthetic token counts, so the token and cost pipelines are exercisable.

The fake mode exists **only** for load tests and failure-injection demos. It is set per-rollout through values and is never the default.

**`services/api` (FastAPI + uvicorn)**

Endpoints:
- `POST /recommend {query}` returns `{recommendations, model, trace_id}`. Input is validated (1–500 characters).
- `GET /healthz`: liveness.
- `GET /readyz`: index loaded, with collection count == `EXPECTED_DOCS`.
- `GET /metrics`

Metrics, all under the `anime_` prefix:

| Metric | Type | Labels / buckets |
|---|---|---|
| `http_requests_total` | Counter | route, method, status |
| `http_request_duration_seconds` | Histogram | route; buckets 0.1, 0.25, 0.5, 1, 2, 4, 8, 16, 32 |
| `http_requests_in_flight` | Gauge | — |
| `retrieval_duration_seconds` | Histogram | — |
| `llm_request_duration_seconds` | Histogram | model, outcome |
| `llm_tokens_total` | Counter | model, type=input\|output |
| `llm_cost_usd_total` | Counter | model |
| `index_info` | Info | version, docs |

- **Cost:** computed from `config/pricing.yaml` (USD per 1M input and output tokens per model), with a file comment recording the date the prices were checked.
- **Removed:** the fake `observe(0.0)` and `sentence-transformers`.

**`services/ui` (Streamlit)**
- A thin client that calls `ANIME_API_URL/recommend`. No LangChain.
- Probe: `/_stcore/health`.

**Index reproducibility**
- A CI step builds the Chroma index from `data/anime_with_synopsis.csv` and asserts `count == 269`, failing the build otherwise.
- The step writes `index/manifest.json` (content hash, count, embedding model), and the Dockerfile copies it in.
- `.dockerignore` excludes any local `chroma_db/`, so the image can only contain the CI-built index.

**Container hardening**
- Multi-stage builds, non-root, read-only root filesystem, `emptyDir` for `/tmp`, dropped capabilities.

**Tests (pytest)**
- Provider selection.
- Fake LLM honors `FAULT_RATE` statistically (seeded).
- Cost calculation.
- `/readyz` returns 503 when the index count mismatches.
- `/recommend` validation.
- Metrics are exported with the expected names.

### 4.2 OpenTelemetry and LLM observability
- **Instrumentation in the api:**
  - `opentelemetry-instrumentation-fastapi`
  - `opentelemetry-instrumentation-langchain` (OpenLLMetry), which emits `gen_ai.*` attributes
  - manual spans `rag.retrieve` and `rag.generate`
- **Span attributes:**
  - `gen_ai.request.model`, `gen_ai.usage.input_tokens`, `gen_ai.usage.output_tokens`
  - `rag.top_k`, `rag.docs_returned`, `index.version`
- **Prompt/response content capture:** **on** for Langfuse (the data is anime preferences, not sensitive) and controlled by `OTEL_CAPTURE_CONTENT` (documented as default-off in regulated contexts).
- **OTel Collector pipelines:**
  - `receivers: otlp`
  - `processors: memory_limiter, batch, attributes (drop http.request.header.*)`
  - `exporters`:
    - `otlp/tempo`
    - `otlphttp/langfuse`: endpoint = Langfuse OTLP URL; Basic auth from an ExternalSecret-provided header
  - `connectors: spanmetrics → prometheusremotewrite` or a `prometheus` exporter scraped by a ServiceMonitor
- **Grafana:**
  - Tempo datasource with trace-to-metrics links.
  - Dashboards **as code** (JSON in `deploy/dashboards/`, loaded via the sidecar ConfigMap label): **SLO overview**, **LLM (latency split, tokens/min, cost/1k requests)**, **Rollout**.

### 4.3 SLOs and alerting (`deploy/slo/`)
- **Sloth spec `anime-api.sloth.yaml`:**
  - Generated PrometheusRule YAML is committed as a plain manifest in `deploy/slo/generated/` and synced by its own Argo CD app.
  - It is kept out of Helm templates because alert annotations contain `{{ $labels }}`, which would clash with Helm templating.
  - CI checks the generated rules are up to date.
  - The SLOs:
  - **Availability SLO 99.5% / 28d.** SLI = `1 - rate(anime_http_requests_total{route="/recommend",status=~"5.."}) / rate(anime_http_requests_total{route="/recommend"})`.
  - **Latency SLO 95% of `/recommend` requests < T / 28d.** **T is set from the k6 baseline in gemini mode** (expected 4s or 8s bucket boundary) and recorded in the spec.
- **Alerts:** Sloth multi-window multi-burn-rate:
  - page: 1h/5m at 14.4×, 6h/30m at 6×
  - ticket: 1d/2h at 3×, 3d/6h at 1×
  - Alertmanager routes page → Discord `#alerts` and ticket → Discord `#tickets`. Each alert has a `runbook_url` label pointing to `docs/runbooks/`.
- **Demo:** run k6 with a `FAULT_RATE=0.5` rollout pinned (analysis disabled for the drill), wait for the fast-burn page alert, and record time-to-alert.
  - **Why 0.5, not 0.1:** at 10% errors the burn rate is 20×, and the 1h window needs about 43 min to average above 14.4×. At 50% the burn rate is 100×, so the alert should fire in about 9 min.

### 4.4 Progressive delivery (Argo Rollouts)
- **`anime-api` is a `Rollout`**, not a Deployment. It has `anime-api-stable` and `anime-api-canary` Services, and ALB traffic routing through the AWS LBC Ingress annotations.
- **Steps:**
  1. setWeight 10 → pause 2m → analysis
  2. setWeight 50 → pause 2m → analysis
  3. setWeight 100
- **`AnalysisTemplate success-rate-and-latency`**: Prometheus provider, interval 30s, count 4, failureLimit 1.
  - Canary success rate ≥ 0.99, filtered by the `rollouts-pod-template-hash` label.
  - Canary p95 ≤ T.
  - Minimum traffic guard: if requests < 20 in the window, the result is `Inconclusive`, and the rollout pauses rather than promoting blindly.
- **Traffic during demos:** a k6 job at constant arrival rate (`loadtest/k6/steady.js`, **20 RPS**, fake mode), so the analysis has data.
  - At the 10% step the canary gets about 2 RPS, which is about 120 requests per 1m query window. That is well above the 20-request guard.
  - At 5 RPS the analysis would always be Inconclusive.
- **Failure demo:** push an image or values change with `FAULT_RATE=0.2`. The analysis fails at the 10% step and the Rollout aborts, shifting 100% back to stable. **Record the elapsed time from rollout start to abort** and the error budget consumed.

### 4.5 Autoscaling and load testing
- **KEDA `ScaledObject`** targeting the Rollout:
  - Prometheus trigger `sum(anime_http_requests_in_flight)`, threshold 4 per pod.
  - min 2, max 8 replicas, cooldown 120s.
- **Node capacity:** cluster capacity is bounded by the node group max 4. Karpenter is P1.
- **k6 scripts (`loadtest/k6/`):**
  - `baseline.js`: gemini mode, low rate (respects Gemini/HF rate limits), 5 min. Measures real p50/p95 to set T.
  - `ramp.js`: fake mode, ramp 1 → 60 VUs over 10 min. Records RPS, p95 and error rate, plus pod count over time from Prometheus.
  - `steady.js`: canary and alert-drill traffic, 20 RPS constant arrival rate.
- **Output:** `k6 --out json` summaries saved to `docs/evidence/loadtest/`.

### 4.6 CI/CD (GitHub Actions, `.github/workflows/`)

**`ci.yml`** runs on PR and push to main:
1. `ruff`, `pytest`, `hadolint`, and the `sloth generate` diff check.
2. **Build index:** assert 269 docs. Uses secrets HF_TOKEN; in PRs from forks the step is skipped.
3. `docker buildx` build of api and ui.
4. `trivy image --severity CRITICAL --ignore-unfixed --exit-code 1`, with the SARIF uploaded to GitHub code scanning.
5. **main only:** `aws-actions/configure-aws-credentials` (OIDC role) → push to ECR by digest.
6. **main only:** `cosign sign --yes <digest>` (keyless; `id-token: write`) and `cosign attest` of the SPDX SBOM (from `anchore/sbom-action`).
7. **main only:** a bot commit updates `deploy/charts/anime-*/values.yaml` image digests with `[skip ci]`. Argo CD auto-syncs, and the Rollout starts the canary.

**`eval.yml`** (P1) runs on PR touching `src/`, `data/` or `prompts/`:
- Retrieval-only evaluation over `eval/golden.jsonl` (20 queries → expected titles).
- Computes hit@4 and fails if it drops below the baseline stored in `eval/baseline.json`.
- No LLM calls, so no cost.

## 5. Error handling and failure modes

| Failure | Behavior |
|---|---|
| Gemini 429/5xx | 1 retry with jitter, then 503 with `Retry-After`. Counted in `llm_request_duration_seconds{outcome="error"}` and the 5xx SLI. |
| HF embedding failure at query time | 503, same accounting. The readiness probe does not flap on upstream errors; readiness reflects only local state. |
| Spot interruption | Node termination handling via the EKS managed node group rebalance. PDB minAvailable 1 on the api; min 2 replicas, spread across nodes. |
| Canary regression | AnalysisRun fails → automatic abort → stable keeps 100%. The Argo CD app shows Degraded until Git is fixed or reverted. |
| Insufficient canary traffic | Inconclusive → rollout pauses for a human; never auto-promotes. |
| OTel Collector or Langfuse down | SDK batch exporter drops spans (bounded queue); requests are unaffected. Collector `memory_limiter` prevents OOM. |
| Index missing or wrong in image | `/readyz` 503, the new pods never Ready, and the Rollout does not progress. The CI assertion should prevent this. |

## 6. Verification and evidence (definition of done)

| # | Item | Verification | Evidence for CV |
|---|---|---|---|
| 1 | Terraform | Apply from empty; plan shows no changes | resource count, apply time |
| 2 | GitOps | All Argo CD apps Synced/Healthy after bootstrap | screenshot |
| 3 | CI | Push to main → signed image in ECR → Argo CD synced | `cosign verify` output with GitHub identity, pipeline duration |
| 4 | Image | Size before (with PyTorch) vs after | MB before/after |
| 5 | Index | CI fails when the CSV is truncated (negative test) | CI run link |
| 6 | Baseline | k6 baseline in gemini mode | real p50/p95 → SLO threshold T |
| 7 | Scale | k6 ramp in fake mode | max RPS at p95 < T, pods 2 → N, error rate |
| 8 | Canary success | Good version promotes through 10/50/100 | Rollout timeline |
| 9 | Canary rollback | `FAULT_RATE=0.2` version auto-aborts | time to abort, % of requests affected |
| 10 | Alerting | Fast-burn page fires to Discord during the fault drill | screenshot, time-to-alert |
| 11 | Tracing | A `/recommend` trace in Tempo and Langfuse shows retrieve/generate spans with tokens | screenshots |
| 12 | Cost metric | Dashboard shows cost per 1k requests in gemini mode | value |
| 13 (P1) | Eval gate | PR degrading retrieval blocked | CI run link, hit@4 |

## 7. Repo layout (after)

```
src/anime/                    shared package (loader, vector store, providers, recommender, pricing)
services/api/                 FastAPI app + Dockerfile
services/ui/                  Streamlit app + Dockerfile
tests/  eval/  loadtest/k6/  config/pricing.yaml  data/
infra/terraform/{bootstrap/, *.tf}
deploy/{argocd/, charts/anime-api/, charts/anime-ui/, slo/, dashboards/}
.github/workflows/{ci.yml, eval.yml}
docs/{evidence/, runbooks/, superpowers/specs/}
Makefile
```

The following are removed:
- `app/app.py`, replaced by `services/ui`.
- `pipeline/`, folded into `src/anime`.
- `llmops-k8s.yaml`, replaced by the Helm charts.
- The `MLops-Common` submodule, since this repo no longer uses the on-prem scripts; the README notes the history.

## 8. Make targets and teardown

| Target | What it does |
|---|---|
| `make up` | `terraform apply` (includes the Argo CD bootstrap) |
| `make down` | Delete Argo CD apps (the ALB and PVs are released by their controllers), then `terraform destroy` |
| `make loadtest-baseline`, `make loadtest-ramp`, `make drill-canary`, `make drill-alert` | Run the corresponding k6 test or failure drill |
| `make grafana`, `make argocd` | Port-forwards; no public admin UIs |

**Teardown order matters.** The ALB and target groups created by AWS LBC must be deleted before destroying the VPC, so `make down` deletes Ingresses first and waits.

## 9. Schedule (days 4–7)

| Day | Work |
|---|---|
| 4 | Terraform EKS + Argo CD bootstrap + addons; app split (api/ui, providers, metrics, health); CI build/scan/push/sign/bump; app reachable via ALB. |
| 5 | Rollout + AnalysisTemplate + ALB traffic routing; Sloth SLOs + Alertmanager Discord; KEDA; canary success and rollback drills. |
| 6 | OTel instrumentation + Collector → Tempo + Langfuse; cost metrics + dashboards; k6 baseline (sets T) + ramp; alert drill. |
| 7 | Evidence capture for both projects, READMEs, CV bullet rewrite with real numbers, `make down` on both. P1 items only if time remains. |

## 10. Risks

| Risk | Mitigation |
|---|---|
| Gemini/HF free-tier rate limits distort numbers | Real-provider runs are limited to the low-rate baseline; scale and canary numbers use fake mode, and **CV claims state which mode**. |
| Spot capacity unavailable | 4 instance types; fall back to On-Demand for the node group (≈ +0.10 USD/h). |
| ALB traffic routing setup time | Fallback: replica-ratio canary (no traffic router) with the same AnalysisTemplate. |
| OpenLLMetry LangChain instrumentation lags the LangChain version | Pin compatible versions; manual `gen_ai.*` spans around the LLM call as fallback. |
| Langfuse Cloud outage or limits | Tempo remains the source of truth; Langfuse is an additional export. |
| Day 4–7 overrun | Cut order: P1 → KEDA (keep a CPU HPA) → alert drill (keep rules) → Langfuse export (keep Tempo). Never cut SLO rules, canary analysis + rollback, or the k6 numbers. |

## 11. Resolved decisions

| Decision | Choice |
|---|---|
| Cluster | EKS with Spot managed node group (Medical uses kubeadm) |
| Repo layout | Everything in this repo |
| CI | GitHub Actions |
| CD | Argo CD |
| Signing | Cosign keyless |
| Delivery strategy | Argo Rollouts canary via ALB |
| SLO tooling | Sloth |
| Autoscaling | KEDA on in-flight requests |
| Traces | Tempo (in-cluster) + Langfuse Cloud via OTel Collector fan-out |
| App shape | Split into api + ui, with a fake LLM mode for load and failure tests |
