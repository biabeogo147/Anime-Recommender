# Stage 6 — Concepts

Every idea [`README.md`](README.md) relies on, defined once. Each section answers **what it is**, **how it runs
here**, and **what breaks without it**. Objectives, windows, factors, routing and the drill's arithmetic are in
[design §4.3](../eks-sre-llmops-design.md#43-slos-and-alerting-deployslo).

---

## 1. SLI, SLO and error budget

**What it is.** A *service level indicator* is a ratio of good events to all events — requests that succeeded, requests
faster than a target. A *service level objective* is the value that ratio should hold over a period. The *error budget*
is what the objective leaves over: the share of requests allowed to fail.

**How it runs here.** Two objectives on the api's main route, one for availability and one for latency under T. Their
period does two jobs: it fixes the size of the budget, and it is what the alert factors are derived from. On a cluster
that lives hours at a time, it is never observed as a measured span — so the objectives are definitions that shape the
alerts, not claims of attainment.

**What breaks without it.** Alerts are set on raw error rates chosen by feel. There is no shared answer to "how bad is
this?", so every threshold is an argument, and the ones that survive are the ones that stopped paging.

---

## 2. Burn rate

**What it is.** How fast the error budget is being spent, relative to spending it exactly over the objective's period.
At 1× the budget lasts the whole period; at a burn rate of *n*, it lasts one *n*-th of it.

**How it runs here.** Every alert is a threshold on burn rate, over a pair of windows.

**What breaks without it.** An error-rate threshold means different things for different objectives: the same 1% of
failures is ten times a strict objective's budget and a fifth of a loose one's. Burn rate normalises that, so one
alert shape serves every objective and every threshold reads as "how soon the budget runs out".

---

## 3. Multiple windows, and why two per alert

**What it is.** A *multi-window* alert computes the burn rate over a long window and a short one — about a twelfth as
long — and fires only when both exceed the threshold.

**How it runs here.** Four alert conditions, each a long window paired with a short one.

**What breaks with one window.** A long window alone starts slowly and, after a large burn, keeps firing long after the
problem has stopped. A short window alone fires on every spike. The pair is prompt in both directions.

---

## 4. Page and ticket

**What it is.** Two severities with two costs. A *page* interrupts someone now. A *ticket* is work for the coming days.

**How it runs here.** The fast-burn pairs page and the slow-burn pairs open tickets, both to one Discord channel,
told apart by `[PAGE]` and `[TICKET]` in the title.

**What breaks without the split.** Everything pages, and people learn to ignore pages — or everything is a ticket, and
an outage waits for Monday.

---

## 5. Generated rules, committed

**What it is.** Sloth takes a short SLO spec and generates the recording rules that compute burn-rate ratios and the
alert rules that fire on them, with factors derived from the objective's period. Its output can be applied by an
operator, templated into a chart, or committed as a plain file.

**How it runs here.** Committed as a plain `PrometheusRule`, with no operator; CI regenerates it and fails on any
difference. The monitoring stack is configured to load rules whatever their labels.

**What breaks otherwise.** Templated through a chart, the rules' own brace-delimited annotations are read as template
code. Hand-edited, they drift from the spec. And a rule file the monitoring stack does not select is accepted by the
cluster and loaded by nothing — no error, no alert.

---

## 6. A window older than the data

**What it is.** A range query such as `rate(x[3d])` is computed from whatever samples fall inside the window. For a
*ratio* of two such rates — which is what a burn rate is — data younger than the window gives the ratio over the data
that exists, not an empty result and not a diluted one.

**How it runs here.** The store is emptied by every teardown, so it is always younger than most of the windows. The
one-hour pair is full after an hour; the six-hour, one-day and three-day windows are computed from whatever hours
exist.

**What breaks without knowing it.** A rule keeps its threshold but evaluates a shorter span than its name says, so a
rule designed to ignore short bursts can fire on one. Before any data at all, every window is empty and nothing can fire.
Neither state announces itself; both are recognised only by checking how much data each window actually holds.

---

## 7. Time-to-alert, and what it is made of

**What it is.** The time from a fault beginning to a person being told. It is a chain: the next scrape carries the
failures; recording rules turn counters into ratios on their own interval; the alert rule's evaluation sees both windows
over the threshold and fires; Alertmanager waits to group related alerts; the notification is delivered.

**How it runs here.** The generated alert rules have no extra waiting period of their own, so they fire at the first
evaluation that satisfies them. Alertmanager's wait depends on whether the alert opens a new group or joins one that
has already notified. The drill records each link, and how much clean traffic came first.

**What breaks without the parts.** A single number from fault to message cannot be explained or improved. Only the window
arithmetic is about the objective; the rest is configuration, and a slow page could be any link.

---

## 8. A runbook written before the alert

**What it is.** A short entry for each alert: what it means, how to confirm it, what to do first. The alert carries a
link to it.

**How it runs here.** Every routed alert has a runbook link, and its entry exists before the drill that fires it.

**What breaks without it.** The page arrives at the worst moment with no context, and the first minutes go on working out
what it is asking for. Writing the entry first also tests whether anyone could act on the alert at all.

---

## 9. Proving delivery, not just firing

**What it is.** Showing that a specific alert reached a person, as distinct from a rule firing or some message reaching
a channel. A *dead-man's switch* is the standing version of that proof: an always-firing alert sent to an outside
service, which complains when it stops arriving.

**How it runs here.** Delivery is proven at each drill, by the alert's name, its objective and the pair that fired.
There is no dead-man's switch; the monitoring stack's heartbeat alert is not routed anywhere.

**What breaks without it.** A rule can fire into a webhook that refuses it, and nothing arrives. Between drills, that
failure is silent — which is recorded as a limit rather than covered by a check that could not see it.

---

[README](README.md) · [Design §4.3](../eks-sre-llmops-design.md#43-slos-and-alerting-deployslo)
