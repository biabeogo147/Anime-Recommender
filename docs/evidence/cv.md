# Measured for the CV

Every number in the CV's Anime entry, with the file it came from and the mode it was measured in. Procedure:
[`guide-measurements.md`](guide-measurements.md). A value stays *pending* until its measurement's conditions are met.

| Placeholder | Measurement | Value | Mode | Source |
|---|---|---|---|---|
| `[T-SLO]` | M1 | *pending* | real: openai `gpt-4o-mini` | `t-value.txt`, from `t-buckets.txt` (load 2.2) |
| `[N-BASELINE]` | M1 | *pending* | real: openai `gpt-4o-mini` | `t-count.txt` |
| `[KNEE-RPS]` | M2 | *pending* | fake, 2 replicas | `ramp-rate.txt`, `ramp-p95.txt` (load 3.4) |
| `[INFLIGHT-KNEE]` | M2 | *pending* | fake, 2 replicas | `ramp-inflight.txt` |
| `[T-ABORT]` | M3 | *pending* | fake, 20 RPS | `rollback-time.txt` (delivery 4.2) |
| `[AFFECTED-PCT]` | M3 | *pending* | fake, 20 RPS | `rollback-affected.txt` (delivery 4.3) |
| `[T-PAGE]` | M4 | *pending* | fake, 20 RPS, short drill | Discord message time − `alert.fault` (slo 3.3) |
| `[PODS-MAX]` | M5 | *pending* | fake, ramp | `scaling-desired.txt`, `scaling-ready.txt` |
| `[NODES-MAX]` | M5 | *pending* | fake, ramp | `scaling-nodes.txt` |
| `[ERR-SCALEIN]` | M5 | *pending* | fake, RPS=5, 30-min return | `scaling-errors-scalein.txt` (k6 `failed`) |
| `[COST-PER-1K]` | M6 | *pending* | real: openai `gpt-4o-mini` | `cost-per-1000.txt`, `cost-pricing-date.txt` (tracing 3.2) |
| `[N-DRILL]` | M7 | *pending* | fake, 20 RPS, 5 min | `m7-counts.txt` |
| `[LF-LEAK]` | M7 | *pending* | fake | `m7-counts.txt` (`langfuse-count`) |
| `[T-REBUILD]` | M8 | *pending* | — | `m8.txt` |
| `[N-APPS]` | M8 | *pending* | — | `m8.txt` |

## Context the CV does not carry

- **M4:** which window pair fired first, the 1h/5m pair's own crossing time, each window's burn rate at firing, the
  store's age, and the error ratio at firing. *Pending.*
- **M5:** the node prediction from scaling 2.4, and whether it held. *Pending.*
