# Stage 2 — GitOps: evidence

Criteria **#2** (every Argo CD Application Synced and Healthy), **#15** (HTTPS on both public names) and **#16**
(the four admin interfaces answer only through the VPN), from the [GitOps guide](../2-gitops/guide.md). Run
2026-09-22 on the cluster.

## How this file was recorded, and what that is worth

**The checks were run and each matched the guide's expected output; the terminal output was not captured
verbatim.** The operator confirmed each step against the expectations printed in the guide rather than pasting
the text, under the session convention that a step not reported is a step that matched.

That is weaker than the other evidence files in this directory, and it is stated here rather than glossed: stage
1's counts, stage 3's digests, stage 4's histogram readings, stage 5's AnalysisRun values and stage 7's
timestamps are all quoted from output. These three criteria are not. What is recorded is that the checks ran and
agreed with the guide — not the numbers they produced.

**What to say about these three in an interview:** that the cluster converged from Git, that HTTPS and the
VPN-only rule were checked both ways, and that the capture was not kept. Claiming a figure from here would be
claiming something this file does not hold.

## #2 — every Application Synced and Healthy

The app-of-apps tree reached **8 of 8** Applications `Synced`/`Healthy` after bootstrap, by name, count, revision
and readiness (guide section 3). The check that makes it mean anything is the health definition: an Argo CD
Application is `Healthy` by default as soon as its resources exist, so the root chart requires **`Healthy` and
`Synced` together** — a tree that is Healthy while still drifting from Git is the false pass this criterion
exists to exclude.

Later sessions extend the same tree: stage 5 added `alerting-secret` and `slo`, stage 7 added `keda` and
`cluster-autoscaler`, and every one of them is recorded `Synced`/`Healthy` in
[scaling](scaling.md#scale-out) and [slo](slo.md).

## #15 — HTTPS on the public names

For both `anime.recruitai.io.vn` and `api.anime.recruitai.io.vn`, from **off the VPN**: port 80 redirects with a
`301`, and HTTPS answers `200` with a chain that verifies without `-k` (guide section 6).

The certificate is **ACM's**, attached to the ALB by annotation, issued and renewed by AWS. Nothing in the
cluster holds a private key for these names, which is the difference from Medical's cert-manager and the reason
this criterion has no renewal drill: there is nothing of ours to renew.

## #16 — the admin interfaces answer only through the VPN

Checked **from the laptop, both ways** (guide section 7), because the assertion is about what an outsider
cannot reach, and the ops workstation sits inside the VPC where everything is reachable:

- **VPN off:** all four names — `argocd`, `grafana`, `prometheus`, `alertmanager` — resolve to a **private
  `10.30.x.x` address** and the connection does not succeed.
- **VPN on:** the same four names are reachable, and the interfaces open.

The resolved address is the real assertion, not the failed connection. A name that does not exist also fails to
connect, so `reachable=False` alone would pass this check for a service that was never deployed.

The configuration half was checked on ops in the same session: the internal ALB's security group admits 443 only
from the VPC and the VPN range, and the names point at the internal load balancer rather than the public one.

**#2, #15, #16: pass as run, unquoted.** If these are ever needed as quoted evidence — for the CV, or for a
question that asks for a number — the three blocks in guide sections 3, 6 and 7 reproduce them in about ten
minutes on a live cluster.
