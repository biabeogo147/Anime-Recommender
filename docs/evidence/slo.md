# Stage 6 — SLOs and alerting: evidence

Criterion **#10** — the fast-burn page reaches Discord during the fault drill — from the
[SLO guide](../6-slo/guide.md). Run 2026-09-23 in **fake mode** at 20 requests per second, against a **clean
hour**: 71,997 requests and **0 errors** in the hour before the fault, on a store 9.67 hours old, with the
Rollout Healthy and `stable = latest` so the hour ran on one version rather than a canary split.

The objective is 99.5% availability, so the error budget is 0.005 and the page's factors are 13.44 (1h/5m pair)
and 5.6 (6h/30m pair) on a 28-day period.

## The rules, before any drill

Three checks, each closing one of the criterion's false passes:

| Check | Result |
|---|---|
| Prometheus **evaluates** the rules, not merely holds them | **6** rule groups, **34** rules, **0** evaluation failures |
| Alertmanager routes exist | `receiver: null` at the root, `{severity="page"}` → `discord-page`, `{severity="ticket"}` → `discord-ticket` |
| The webhook is readable by Alertmanager | secret file present, non-empty (length checked, never printed) |
| Delivery works with **no rule involved** | an injected `AnimeDeliveryTest` reached Discord as `[PAGE] … FIRING`, and `RESOLVED` when its `--end` passed |

The first is the one that matters most: a PrometheusRule the monitoring stack does not select is accepted and
ignored, and a drill run against it would be silent with no error anywhere.

## #10 — time to page, in its parts

The fault is **50% of requests at all traffic**, promoted straight through rather than through a canary: a
canary's 10% share would dilute it below the page threshold, which is one of the criterion's documented false
passes.

| Step | Time | Elapsed |
|---|---|---|
| The faulty version has all traffic (`alert.fault`) | `11:05:23Z` | — |
| First failed request **scraped** | `11:06:08Z` | **+45 s** — the scrape |
| 5-minute error ratio **recorded** | `11:06:23Z` | **+15 s** — the recording rules |
| Page alert **firing** in Prometheus | `11:14:23Z` | **+8 m 00 s** — the window arithmetic |
| Seen by the polling loop (±10 s) | `11:14:25Z` | |
| `[PAGE] … FIRING` in Discord | `11:14Z` | Alertmanager's 30 s `group_wait` plus delivery |

**Fault → alert firing: 9 m 00 s. Fault → the message in Discord: 9 m 30 s.**

The Discord figure is bounded rather than exact, and the bound is stated rather than rounded away: Discord
displays minutes, so the message fell inside `11:14:00Z–11:14:59Z`; it cannot precede the alert's own
`11:14:23Z`, and Alertmanager holds a new group for 30 s (`group_wait`) before sending. That leaves
`11:14:53Z–11:14:59Z`, so **9 m 30 s to 9 m 36 s** from the fault. The figure quoted is the lower bound.

Only the first minute of that is system latency; the eight minutes in the middle are the window arithmetic, and
they are the point rather than a delay to be tuned away. The measured error ratio at that moment
was **0.497**, and Alertmanager's Discord delivery failures over the preceding 30 minutes were **0**.

### Which pair fired, and why it matters

| Window | Burn rate at firing | Factor it must pass | |
|---|---|---|---|
| 5m | **99.43** | 13.44 | over |
| **1h** | **14.66** | 13.44 | **over** |
| 30m | 29.25 | 5.6 | over |
| **6h** | **5.30** | 5.6 | **under** |
| 2h | 8.70 | 2.8 (ticket) | over |
| 1d | 3.79 | 2.8 (ticket) | over |
| 3d | 3.79 | 0.93 (ticket) | over |

The page is the OR of two pairs, and only the **1h/5m pair** was true: 5m and 1h both above 13.44, while the
6h/30m pair failed on its 6h leg at 5.30 against 5.6. **1h/5m is the calibrated pair** — the one whose 1-hour
window held the clean hour — so the 9 minutes is the calibrated crossing time and not an artefact of a window
that happened to be short of data.

The guide had expected about 4 minutes from the 6h/30m pair. That pair cannot win on a store already holding
hours of clean traffic: its 6h window has a denominator large enough that a 50% fault needs roughly twenty
minutes to push it past 5.6. The guide is corrected, with 5.30 recorded as the reason.

The ticket alert fired first, at about 3 minutes, from its own longer pairs. It is not the page and is not the
measurement; it is recorded here because on the night it happens, two messages arrive and only one of them is
the one being measured.

## Recovery, and why the alert took longer to clear than to fire

| Step | Time | Elapsed |
|---|---|---|
| Fault reverted, all traffic on the good version | `11:35:11Z` | — |
| Page alert **off** in Prometheus (`alert.resolved-seen`) | `12:01:17Z` | **+26 m 06 s** |
| `[PAGE] … RESOLVED` in Discord | `~12:04Z` | Alertmanager's `group_interval` |

The revert went through the **full canary** — 10% → 50% → 100% in 8 m 31 s — rather than being pushed through,
because traffic was flowing and the good version could be judged on measurements like any other release.

**The alert fired in 9 minutes and took 26 to clear, although the fault was fixed at 11:35:11.** By then the
1h/5m pair was already false — `rate5m` empties within five minutes — and what kept the page up was the
**6h/30m pair**, which had become true during the fault: at 11:50 the 30m burn rate was still 41.9 and the 6h
rate 13.35. The page cleared when the 30-minute window had aged enough of the fault out to fall under 5.6,
which it did between 12:00 (7.63) and 12:02 (3.86).

This asymmetry is inherent to burn-rate alerting, not a misconfiguration: the same long windows that stop a
single stray error from paging anyone also stop the page from clearing the moment a fix lands. It is worth
knowing before an incident rather than during one, because an operator who expects the page to clear with the
fix will conclude the fix did not work and go looking for a second fault that does not exist.

**Why the clearing is a real reading, not an artefact.** A page also clears when traffic stops — the denominator
disappears and the condition goes false — and on Discord the two look identical. Traffic was **40 req/s at
12:00 and at 12:02**, and 36.6 at 12:04, because a second k6 run was started to overlap the first, which ended
at 12:03:06Z. So the budget stopped burning while requests kept being served.

## A finding that arrived before the drill did

The latency SLO's **ticket** alert fired on its own, hours earlier, with no fault injected. It was correct: the
stage 4 ramp had driven p95 to 15.6 s against a T of 8 s, and those requests were still inside the 6h and 3d
windows. It cleared by itself at 09:33Z, within a minute of the ramp ageing out of the 6h window at 09:34:26Z.

Two things follow, and both belong in the record rather than in a footnote:

- **The SLI carries no mode label.** It filters on `route="/recommend"` and nothing else, so traffic generated
  by our own load tests burns the same error budget as traffic from a user. That is exactly what happens in
  production when someone runs a load test against a live service, and here it surfaced by itself.
- **Alerts clear themselves when the cause ends.** Nobody acknowledged or silenced anything. A system whose
  alerts must be cleared by hand teaches its operators to clear alerts by hand, and eventually they clear the
  one that mattered.

## Defects found in the guide by running it

| Where | What was wrong | Consequence if unfixed |
|---|---|---|
| 0.3 | expected `16` recording rules | the real number is 30; a correct run reads as a shortfall |
| 2.1 | expected `20` rules loaded | same miscount carried forward |
| 3.3 | expected the page in ~4 minutes from the 6h/30m pair | that pair cannot win on a store with hours of clean traffic |
| 3.4 | the pair-crossing helper omitted `max without (sloth_window)` | both pairs report `(none)` however true they are, because the recording rules carry `sloth_window` and the `and` then matches on it |

The last one is the instructive failure: the diagnostic said "no pair was ever true" while the alert it was
diagnosing was firing. The burn rates in the same output contradicted it, which is why the block prints both.

**#10: pass.** The criterion asks for the time until a **person** is reached, not until Prometheus raises the
alert, and that is the 9 m 30 s above: 45 s of scrape, 15 s of recording rules, 8 minutes of window arithmetic,
then Alertmanager's 30 s hold and the delivery itself.
