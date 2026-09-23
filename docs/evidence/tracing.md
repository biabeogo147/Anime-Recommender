# Stage 8 — Tracing and cost: evidence

Criteria **#11** (a real request appears in both sinks, with non-zero tokens) and **#12** (cost per 1,000
requests, in real mode), from the [tracing guide](../8-tracing/guide.md). Run 2026-09-23 on **OpenAI
`gpt-4o-mini`**.

The collector fans one stream out to two sinks, and the split is the design:

```
anime-api ──OTLP──▶ otel-collector ──┬──▶ Tempo      every span, inside the cluster
                                     └──▶ Langfuse   LLM spans only, over the internet
```

Tempo answers *what happened inside this request*; Langfuse answers *what the model did, and what it cost*. Having
both is what made the first failure legible: Tempo held a complete trace while Langfuse held nothing, which
separates "the application produced no trace" from "the trace could not be exported".

## #11 — one trace, both sinks

Trace `d19d2834e2fb4216c71cb8fad4bf2f95`, one real request.

**In Tempo:**

| Span | Kind | Attributes |
|---|---|---|
| `POST /recommend` | `SPAN_KIND_SERVER` | |
| `rag.retrieve` | `SPAN_KIND_INTERNAL` | `rag.top_k=4`, `rag.docs_returned=4` |
| `chat gpt-4o-mini` | `SPAN_KIND_CLIENT` | `gen_ai.provider.name=openai`, `gen_ai.request.model=gpt-4o-mini`, **`gen_ai.usage.input_tokens=957`**, **`gen_ai.usage.output_tokens=461`** |

Resource attribute `anime.llm.provider = openai` — the key the Langfuse pipeline filters on.

**In Langfuse:** the same trace id, **7 observations**, with `chat gpt-4o-mini` typed `GENERATION`. The web UI
shows the model, **1,418 tokens** and **$0.00042** — and 1,418 is exactly 957 + 461, so the two sinks agree on
the same request rather than merely both holding data.

**#11: pass.**

### The negative half: drill traffic stays out

A filter that lets everything through looks exactly like a filter that works, so the absence is proven too.

| Reading | Value |
|---|---|
| Fake-mode request `f9a7299cc8c0d1f37b7e2d684ba6d2ad` in Tempo | **yes**, with `anime.llm.provider = fake` |
| The same trace in Langfuse | `http 200`, **observations: 0** |
| A **later** real trace `4b1d626c…` in Langfuse | `http 200`, **observations: 7** |
| M7 drill window: requests served (`[N-DRILL]`) | **6,343** |
| M7: spans through the collector | **6,076** |
| M7: **distinct traces in Langfuse** | **0** |

**Why the later real trace matters.** `observations: 0` on its own has two readings — the filter blocked it, or
ingestion has not caught up. Fetching a real trace created *after* the fake one, and waiting until it is visible,
settles it: ingestion has passed that point in time, so the fake trace's absence is an answer rather than a
delay. The same reasoning applies to any proof of absence — do not measure the absence, measure something that
would have had to appear first.

Over the whole drill window, **6,343 requests produced 0 Langfuse traces** while Tempo recorded 6,076 spans. Not
"few" — none.

## #12 — cost per 1,000 requests

40 real requests at 10 per minute, `15:18:08Z → 15:22:08Z`.

| Reading | Value |
|---|---|
| **Cost per 1,000 requests** | **$0.4186** (`model="gpt-4o-mini"`) |
| Total cost of the run | $0.01739 |
| `model="fake"` in the same window | **$0** — what the dashboard's filter keeps out |
| Prices used | `gpt-4o-mini`: **$0.15** per 1M input, **$0.60** per 1M output |
| Price source | `https://developers.openai.com/api/docs/pricing`, Standard tier, uncached input, **read 2026-09-22** |
| Client-side latency of the run | avg 5.03 s, p95 6.05 s |

**Three independent routes agree.** $0.01739 over 40 requests is $0.000435 each, so $0.435 per thousand, against
the $0.4186 the ratio reports over a ten-minute `increase()` window — and against the **$0.00042** Langfuse
computed for a single request from its own price table. Different arithmetic, different price tables, the same
answer to two significant figures.

**#12: pass.**

**The false pass this rules out** is a confident `0`: a model absent from `config/pricing.yaml`, or present at a
price of zero, produces a dashboard that draws a clean flat line at nothing. The check is not that the panel
renders but that the value is above zero and the price line behind it exists.

**Why the price carries a date.** These prices are not in any API; they are on a web page that can change without
notice, and the page itself shows no revision date. A cost figure without the date its prices were read is not
reproducible — the same tokens would produce a different number later, with nothing in the record to explain it.

## What this stage cost in incidents, and what each one taught

**1. The Langfuse region.** `otlpEndpoint` pointed at `cloud.langfuse.com` (EU) while the project lives at
`us.cloud.langfuse.com`. Langfuse Cloud keeps its regions on separate hosts with separate data and separate keys,
so the keys were refused. The failure was **one-sided and silent**: the collector's export was rejected, requests
kept returning 200, and nothing in the application showed it. The only visible symptom came from the read
command — and only because `make langfuse-obs` derives its API host from the same line, so one wrong value broke
both halves and made the silent one audible.

**2. The list endpoint hides the usage.** `/api/public/v2/observations` returns a summary whose `modelId` and
price fields are `null` even when Langfuse holds the model, the tokens and the cost. Reading only the list
reports `model=- usage={}`, which is **indistinguishable from a provider that reported no usage** — and that is a
real outcome the guide tells the operator to record honestly. Believing the list would have put a false sentence
into this file: "OpenAI returned no usage". The web UI contradicted it; `make langfuse-obs` now fetches each
generation by id.

**3. A half-promoted mode switch.** The Rollout paused on an inconclusive canary, so `stable` stayed on the
real-mode version while the spec already read `fake`. Nine requests in ten went to the old pods and came back
`gpt-4o-mini`, and the guide's guard could only say "send the request again" — which does not help at a 10%
weight. `promote-full` sets a flag the controller consumes once, so promoting past one pause lets the next step
run its own analysis and pause again. The mode-switch block now promotes until `Healthy`, and the check that
matters is **`stable = latest`**, not `provider=fake`: the second says the spec changed, the first says the
traffic moved.

All three were configuration or tooling faults that produced **plausible-looking wrong answers** rather than
errors. That is the shape of every failure worth writing down.
