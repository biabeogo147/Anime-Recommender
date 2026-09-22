# Local verification — 2026-09-15

Environment: Windows 11, Docker Desktop (engine 29.7.2), images `anime-api:local`, `anime-ui:local` (Python 3.12).

## Build and tests

| Check | Result |
|---|---|
| `docker build -f services/api/Dockerfile --target test .` | ruff clean, **17 passed** |
| Image sizes | previous single image built from `HEAD` **6.45 GB** (pulled PyTorch via unused `sentence-transformers`) → api **619 MB (−90%)**, ui **559 MB**. No PyTorch in either; the UI image has no LangChain. |
| Dependencies | locked with `uv.lock` (132 packages, linux/amd64): langchain-core 1.6.3, chromadb 1.5.9, fastapi 0.141.1 |
| Index stage during `docker compose build` | 269/269 anime embedded via HF Inference API in **8.5 s**, content hash `aa0c3ace7f67` |
| HF token leakage | token string found **0 times** in `docker history` and **0 times** in `docker save` output (BuildKit secret mount) |
| Negative test `--build-arg EXPECTED_DOCS=270` | build **fails**: `IndexValidationError: Loaded 269 documents …, expected 270` |

## Runtime (Gemini `gemini-3.5-flash-lite`)

| Check | Result |
|---|---|
| `docker compose up -d` | api healthy in ~6 s, ui healthy after api |
| `POST /recommend` "school romance with comedy" | 200 in **3.0 s**; retrieved School Rumble, Happy☆Lesson, Onegai☆Teacher, Boys Be... |
| `POST /recommend` "giant robots and war" | 200 in **2.7 s**; retrieved Fafner, Koukaku Kidoutai, Gad Guard, Gundam 0080 |
| Token / cost metrics after 2 requests | input 1,829, output 790 tokens; **$0.0025** estimated at paid-tier list price (~$0.0013 per request) |
| UI → API call from inside the ui container | 200 |
| Container user | `uid=10001(app)` |

## Failure drill (fake provider)

`LLM_PROVIDER=fake FAULT_RATE=0.2 FAKE_LATENCY_MS=50`, 100 sequential requests:

| Status | Count | `anime_http_requests_total` | `anime_llm_request_duration_seconds_count` |
|---|---|---|---|
| 200 | 80 | 80 | outcome="ok" 80 |
| 503 | 20 | 20 | outcome="error" 20 |

## Startup resilience

The first local `docker compose up` failed to bind port 8000, because another stack was using it. That left the api container without networking (`Temporary failure in name resolution`).

This exposed a design flaw: the index/model load ran once and never retried. Now:
- Loading runs in the background with capped exponential backoff (1 s → 30 s).
- `/readyz` reports the last error while it retries.
- `/healthz` stays 200, so the orchestrator's startup probe decides when to give up.

Covered by `test_transient_startup_failure_is_retried`.
