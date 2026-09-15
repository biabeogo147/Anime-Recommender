# Anime Recommender — LLMOps on Kubernetes

> **Source & Credits**: Based on [data-guru0/ANIME-RECOMMENDER-SYSTEM-LLMOPS], customized for this project.

An end-to-end **LLMOps** demo for anime recommendation: **Gemini LLM** for reasoning/UX, **Hugging Face** embeddings for text → vectors, **ChromaDB** as vector store, packaged with **Docker**, deployed on **Kubernetes**, and observed with **Prometheus/Grafana** (both **app metrics** and **node metrics**).

---

## ✨ Features
- 🔮 **LLM (Gemini)** for prompting/explanations.
- 🧠 **Hugging Face embeddings** to normalize text into vectors.
- 🗂️ **ChromaDB** as a local/embedded vector database.
- 🐳 **Docker** image, ☸️ **Kubernetes** manifests.
- 📈 **Observability** with Prometheus (scrapes `/metrics` on port **8000**) and Grafana dashboards. Node metrics via kube-prometheus-stack (node-exporter).
- 🌐 **NGINX Ingress** with internal hostnames: `streamlit.local`, `grafana.local`, `prometheus.local`.

---

## 🐳 Run locally with Docker

The app is split into a **FastAPI recommendation API** (`services/api`) and a thin **Streamlit UI** (`services/ui`).

```bash
cp .env.example .env               # fill GOOGLE_API_KEY and HF_TOKEN
docker compose up --build -d       # API on :8000, UI on http://localhost:8501
curl -X POST localhost:8000/recommend -H 'content-type: application/json' \
     -d '{"query": "light hearted anime with school settings"}'
```

- **Index is built inside the image build**, with the HF token passed as a BuildKit secret, never baked into a layer. The build **fails if the index does not contain all 269 anime**.
- **Fake provider** (no network, for load tests and failure drills): `LLM_PROVIDER=fake FAULT_RATE=0.2 docker compose up -d api`.
- **Lint + tests:** `docker build -f services/api/Dockerfile --target test .`

| API endpoint | Purpose |
|---|---|
| `POST /recommend` | `{query}` → 3 explained picks, retrieved titles, model, trace id |
| `/healthz`, `/readyz` | Liveness / readiness (index loaded and complete) |
| `/metrics` | Prometheus metrics (see cheat-sheet below) |

> The Kubernetes sections below describe the previous single-pod Streamlit deployment and will be replaced by the EKS setup.

---

## 🏗️ Architecture Overview
```
[User Browser]
   └─> NGINX Ingress Controller
         ├─ streamlit.local  ──> anime-recommender-service:80 ──> Pod (Streamlit :8501)
         ├─ grafana.local    ──> monitoring-grafana:80        ──> Grafana UI
         └─ prometheus.local ──> monitoring-kube-prometheus-prometheus:9090 ─> Prom UI

[Anime Recommender Pod]
  - Image: biabeogo147/anime-recommender-app:v1.0.1
  - Ports:
      * HTTP app: 8501 (Streamlit)
      * Metrics: 8000 (Prometheus client at /metrics)
  - Secrets (env): GOOGLE_API_KEY, HUGGINGFACEHUB_API_TOKEN

[ChromaDB]
  - Persisted on local path / PVC (if configured)
  - Populated by an ingest step (Hugging Face embeddings)

[Monitoring]
  - kube-prometheus-stack (Prometheus, Grafana, node-exporter, CRDs)
  - ServiceMonitor scrapes app metrics via anime-recommender-metrics Service
```

---

## ✅ Prerequisites
- A working **Kubernetes** cluster with **nginx-ingress**.
- **Helm** available to install **kube-prometheus-stack** (namespace `monitoring`, release name `monitoring`).
- Hostname mapping (for a lab environment without external DNS):
  ```
  <NODE_IP> streamlit.local grafana.local prometheus.local
  ```
  Replace `<NODE_IP>` with a node/LoadBalancer IP reachable from your machine.
- App image available at `biabeogo147/anime-recommender-app:v1.0.3` (or import the image to each node via containerd if you are offline).

---

## 🔐 Environment & Secrets
The app reads these environment variables from a **Kubernetes Secret**:

| Key                        | Description               | Example                                  |
|----------------------------|---------------------------|------------------------------------------|
| `GOOGLE_API_KEY`           | API key for Google Gemini | `AIza...`                                |
| `HUGGINGFACEHUB_API_TOKEN` | Token for Hugging Face    | `hf_...`                                 |
| `MODEL_NAME`               | LLM model name            | `gemma-3n-e2b-it`                        |
| `EMBEDDING_MODEL_NAME`     | Embedding model name      | `sentence-transformers/all-MiniLM-L6-v2` |
| `METRICS_PORT`             | Metrics port              | `8000`                                   |

---

## Bash scripts
All the bash scripts setting up project in [biabeogo147/MLops-Common]
```bash
git submodule update --init --recursive
```

---

### Secret creation script (`create-secret.sh`)
```bash
#!/usr/bin/env bash

kubectl create namespace anime-recommender --dry-run=client -o yaml | kubectl apply -f -

kubectl -n anime-recommender create secret generic anime-recommender-secrets \
  --from-literal=GOOGLE_API_KEY="$GOOGLE_API_KEY" \
  --from-literal=HUGGINGFACEHUB_API_TOKEN="$HUGGINGFACEHUB_API_TOKEN" \
  --dry-run=client -o yaml | kubectl apply -f -
```

> The app `Deployment` uses `envFrom.secretRef.name: anime-recommender-secrets` to load these values.

---

## ☸️ Deploy to Kubernetes
This repository uses a single manifest **`llmops-k8s.yaml`** that contains:
- **Deployment** (1 replica) exposing ports `http:8501` and `metrics:8000`
- **Service** (ClusterIP) for web traffic (80 → 8501)
- **Service** (ClusterIP) for metrics (8000 → 8000)
- **ServiceMonitor** (in `monitoring` namespace, labeled `release: monitoring`)
- **Ingress** rules for:
  - `streamlit.local` → `anime-recommender-service:80`
  - `grafana.local` → `monitoring-grafana:80`
  - `prometheus.local` → `monitoring-kube-prometheus-prometheus:9090`

**Apply**
```bash
kubectl apply -f llmops-k8s.yaml
```

**Delete**
```bash
kubectl delete -f llmops-k8s.yaml
```

---

## 🔍 Post‑Deploy Verification
```bash
# App namespace
kubectl -n anime-recommender get pods,svc,ingress

# Monitoring namespace
kubectl -n monitoring get pods,svc,ingress

# Secrets
kubectl -n anime-recommender get secrets

# ServiceMonitor
kubectl -n monitoring get servicemonitor anime-recommender-servicemonitor -o yaml
```

**Hosts mapping** (lab): add to `/etc/hosts` on your workstation.
```
<NODE_IP> streamlit.local grafana.local prometheus.local
```

**Open UIs**
- App (Streamlit): http://streamlit.local/
- Grafana: http://grafana.local/
- Prometheus: http://prometheus.local/

**Grafana admin password** (for release `monitoring`):
```bash
kubectl -n monitoring get secret monitoring-grafana -o jsonpath="{.data.admin-password}" | base64 -d; echo
```

**Prometheus targets**
- Navigate to **Status → Targets** and verify the ServiceMonitor target is **UP** (HTTP 200).

---

## 📊 Metrics Cheat‑Sheet
The API exposes:
- `anime_http_requests_total{route,method,status}` (Counter)
- `anime_http_request_duration_seconds{route}` (Histogram, buckets 0.1 … 32s)
- `anime_http_requests_in_flight` (Gauge, the autoscaling signal)
- `anime_retrieval_duration_seconds`, `anime_llm_request_duration_seconds{model,outcome}` (Histograms)
- `anime_llm_tokens_total{model,type=input|output|reasoning}` (Counter)
- `anime_llm_cost_usd_total{model}` (Counter, estimated from `config/pricing.yaml`)
- `anime_index_info` (Info: content hash, document count, embedding model)

Prometheus/Grafana queries:
```promql
# QPS
sum(rate(anime_http_requests_total{route="/recommend"}[1m]))

# P95 latency
histogram_quantile(0.95, sum(rate(anime_http_request_duration_seconds_bucket{route="/recommend"}[5m])) by (le))

# Error rate
sum(rate(anime_http_requests_total{route="/recommend",status=~"5.."}[5m]))
  / sum(rate(anime_http_requests_total{route="/recommend"}[5m]))

# Estimated cost per 1k requests
1000 * sum(rate(anime_llm_cost_usd_total[1h])) / sum(rate(anime_http_requests_total{route="/recommend",status="200"}[1h]))
```

---

## ⚙️ Resource Defaults
From the `Deployment`:
```yaml
resources:
  requests:
    cpu: "100m"
    memory: "256Mi"
  limits:
    cpu: "700m"
    memory: "2Gi"
```
Tweak based on your traffic and workload. Since LLM/embeddings may be remote APIs, CPU/memory usage here often reflects I/O and data processing.

---

## 🔐 Security Notes
- Never commit API keys/tokens to the repo.
- Use Kubernetes **Secrets** (as shown).
- For stronger hygiene, consider **sealed-secrets** or **external-secrets**.

---

## 📄 License
Keep the original repository’s license and update as needed for your modifications.

---
