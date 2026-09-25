# Stage 8 — Concepts

Every idea [`README.md`](README.md) relies on, defined once. Each section answers **what it is**, **how it runs
here**, and **what breaks without it**. Pipelines, attributes, exemplar settings and the cost query are in
[design §4.2](../eks-sre-llmops-design.md#42-opentelemetry-and-llm-observability).

---

## 1. A trace and its spans

**What it is.** A *trace* is the record of one request's path through a system, made of *spans*: timed pieces of work,
each with a name, a parent and attributes. Nesting shows what happened inside what; durations show where the time went.

**How it runs here.** A `/recommend` request produces a request span with retrieval and generation spans inside it, plus
a few small spans the web framework adds on its own. When tracing is enabled, the response carries the trace id, so a
single request someone complains about can be found.

**What breaks without it.** Latency is one number per request. When it rises the choice is between guessing and adding
timers afterwards — by which time the incident is usually over.

---

## 2. OpenTelemetry and the collector

**What it is.** OpenTelemetry is a vendor-neutral standard and set of libraries for producing traces, metrics and logs. The
*collector* is a separate process that receives telemetry, processes it, and exports it to one or more backends.

**How it runs here.** The api exports spans in batches, in the background, to one collector in the cluster; the collector
decides what goes to Tempo, to Langfuse and to Prometheus. Tracing is enabled only when the api is told where the
collector is.

**What breaks without the collector.** Every backend's credentials, filtering and retry logic would live in the application,
and adding a destination or changing a filter would mean redeploying the app. The export is already asynchronous, so a slow
backend would drop spans rather than slow requests — the cost of doing without the collector is control, not latency.

---

## 3. GenAI semantic conventions

**What it is.** *Semantic conventions* are OpenTelemetry's agreed attribute names. The generative-AI set defines
names for the operation, the model, the provider and the token counts, and a span-naming rule of "operation, then
model". The set is still marked as in development.

**How it runs here.** The generation span is named by that rule and carries the operation, model and token
counts, the provider attribute, and the `CLIENT` kind the conventions expect for a call out to a remote model.

**What breaks without them.** Each backend needs a mapping from home-made names, and an LLM-aware tool sees the
generation as an ordinary span — no model, no tokens, no cost.

---

## 4. Pipelines and a filter

**What it is.** In the collector, a *pipeline* joins receivers to exporters through its own list of processors.
Several pipelines can read from one receiver, each seeing its own copy of the data. A *filter* processor drops
telemetry that matches a condition, which can test a span's attributes or its *resource* — the attributes
describing the process that produced it, shared by every span it emits.

**How it runs here.** Two trace pipelines read the same receiver. The one bound for Langfuse drops everything
whose resource marks it as coming from a fake-mode pod; the mark is set once per pod, from the same value that
picks the provider.

**What breaks with a span-level filter.** A condition on an attribute that only one span carries drops that span
and forwards the rest of the trace. The filter appears to work — the generation spans are gone — while every
drill still sends most of each trace downstream.

---

## 5. Span metrics, and two tools that disagree

**What it is.** A span-metrics connector counts spans and records their durations as metrics. It can attach
*exemplars*: for a point on a graph, the id of one trace that contributed to it.

**How it runs here.** Span metrics exist to carry exemplars, so a slow bucket on a graph links to a real trace.
Every decision — SLI, gate, threshold — reads the api's own histograms instead.

**What breaks without the rule.** The two sources measure the same requests from different start and end points,
with different buckets, and disagree. Without a rule about which decides, a threshold is enforced on one and
reported from the other. And the exemplar link itself breaks silently if any of its settings is missing: the
graphs still draw, with nothing to click.

---

## 6. Capturing content

**What it is.** Recording the prompt and the model's response as span attributes, so a trace shows *what* was
said as well as how long it took. OpenTelemetry treats it as opt-in, because content can be sensitive.

**How it runs here.** `OTEL_CAPTURE_CONTENT` controls it: off in the code, on in this chart for the demonstration, off
by default anywhere regulated. Only real-model traces carry it to Langfuse.

**What breaks either way.** Off, a bad answer can be timed but not read. On, whatever a user types into a
free-text box is copied to a third party, whatever the box was meant for. The decision has to be made openly, not
inherited from a default.

---

## 7. Tokens and the cost of a request

**What it is.** Models are billed per token, at different prices for input and output. A *list price* is the
published rate on the paid tier. An estimated cost multiplies each call's token counts by the list price; cost
per thousand requests divides the cost rate by a request rate and multiplies by a thousand.

**How it runs here.** Prices come from a checked-in, dated file. The project itself runs on a free tier, so the
figure is what the traffic *would* cost. Both halves of the ratio are restricted to real models, which means the
denominator must be a request count that carries a model label.

**What breaks without the labels.** The fake provider is priced like a real model, so an unfiltered numerator
reports realistic dollars from synthetic tokens; an unfilterable denominator counts every drill request and
dilutes the result. Either way the number looks plausible.

---

## 8. An attribute that is present and zero

**What it is.** A value written with a default when the real value is missing looks, downstream, exactly like a
real value that happens to be zero.

**How it runs here.** When the model reports no usage, the token attributes are written as zero. Checks on traces
require non-zero token counts, from real-model requests.

**What breaks without the distinction.** "The span carries token attributes" passes while token capture is
broken, and the cost derived from those tokens is zero for the same reason — a failure that reads as an unusually
cheap day.

---

## 9. Where traces live

**What it is.** A trace backend stores traces somewhere and keeps them for some time. Tempo writes blocks to
whatever storage it is given and keeps them until they age out or the storage goes; a hosted service keeps them
on its own infrastructure, for as long as the plan allows.

**How it runs here.** Tempo runs in the cluster with scratch storage that disappears with its pod. Langfuse Cloud
is outside, and keeps real-model traces across teardowns within its retention.

**What breaks without knowing it.** Evidence is looked for the next morning in the place that no longer has it.
Tempo is for the session; Langfuse is for later; evidence is captured before the teardown.

---

[README](README.md) · [Design §4.2](../eks-sre-llmops-design.md#42-opentelemetry-and-llm-observability)
