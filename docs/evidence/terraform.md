# Stage 1 — Terraform: evidence

Criterion **#1** ([design §6](../eks-sre-llmops-design.md#6-verification-and-evidence-definition-of-done)), run from the ops
workstation on 2026-09-22 following [the terraform guide](../1-terraform/guide.md). Account `242834061265`, region
`ap-southeast-1`. Output as reported, from the guide's section 6 block and the steps before it.

## #1 — apply from empty, then a plan with no changes, against a count written down first

| Stack | Plan (written down) | Applied | Managed in state | Re-plan (refreshing) | Apply time (`real`) |
|---|---|---|---|---|---|
| `shared` | 15 | 15 | 15 | `No changes.` | 0m55s |
| `cluster` | 92 | 92 | 92 | `No changes.` | 12m18s |
| `bootstrap` | 2 | 2 | 2 | `No changes.`, `exit=0` | 1m14s |

The three `count OK` lines printed `shared count OK: 15`, `cluster count OK: 92` and `bootstrap count OK: 2`. The
re-plans ran without `-refresh=false`, so a resource that drifted from its configuration would have shown as a change.
**#1: pass.**

**One caveat on reproducibility, found afterwards.** This run resolved its providers against a range
(`version = "~> 6.0"`) with no lock file in Git, so "apply from empty, then no changes" was measured against
whichever provider versions `terraform init` happened to fetch that day — `aws` resolved to **6.66.0**. The three
`.terraform.lock.hcl` files were committed on 2026-09-23, after the measurement, so a rebuild from here on pins
the same versions and the claim becomes repeatable. The measurement itself is not re-run for this: what changed
is that the next one can be compared with it.

## The cluster, and the way in

| Check | Result |
|---|---|
| `describe-cluster` (version, platform, public endpoint) | `1.36  eks.14  False` |
| Nodes | two `Ready`, `SPOT`, `m7i-flex.large`, kubelet `v1.36.4-eks-a887778` (`ip-10-30-22-214`, `ip-10-30-49-224`) |
| API name from the workstation | resolves to `10.30.250.10` and `10.30.250.21`, private addresses in the control-plane subnets |
| API through the tunnel (`make ready`) | `ok`, and `kubectl get --raw /readyz` → `ok` |
| API called directly (guide 4.3, the negative half) | `curl: (28) Connection timed out after 10002 milliseconds` → `not reachable directly: correct (timeout)` |
| Kubeconfig | server `https://127.0.0.1:6443`, `tls-server-name` `B269F68CD1061506277480C01189E0FD.gr7.ap-southeast-1.eks.amazonaws.com`, context `anime` |

## Argo CD

| Check | Result |
|---|---|
| Chart versions (guide 5.1) | `argo-cd` **10.9.2**, `argocd-apps` **2.0.5**, now pinned as defaults in `infra/terraform/bootstrap/main.tf` |
| `target_revision`, `enabled_stages` | `anime/build`, `[]` |
| Pods in `argocd` | application-controller, applicationset-controller, redis, repo-server, server all `Running`; `argocd-redis-secret-init` `Completed` |
| Root Application | `root  Synced  Healthy`, `condition met`, and `root at the pushed commit` |

The root has no children: with `enabled_stages = []` its chart renders nothing. This proves Argo CD reads the branch
and renders the chart, and nothing more.

## Not in the reported output

These steps' outputs were not part of the report. The later stages depend on them, so they are listed rather than
assumed:

- static checks (section 1): the three `validate` results;
- ACM `ISSUED` and `exit=0` from the `shared` and `cluster` re-plans (2.2, 3.2). The re-plan files say `No changes.`;
- the gateway's `READY` and `wg0` block (3.3). The tunnel working through the gateway implies SSM reached it, but
  not that WireGuard is up;
- the secret lengths (2.4, 2.5);
- the WireGuard handshake from the laptop (4.4).
