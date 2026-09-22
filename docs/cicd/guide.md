# Stage 3 — Guide: from a merged change to a signed digest in Git

Commands and checks only; the reasoning is in the comments of `.github/workflows/ci.yml` and `index-negative.yml`, and in
[README](README.md) · [concepts](concepts.md).

Machines: **laptop** (Windows: git), **browser** (GitHub's web UI, on the laptop), **ops** (the workstation, inside tmux,
each block starting with `cd ~/Anime-Recommender && export KUBECONFIG=$HOME/.kube/anime`).

Criteria closed ([design §6](../eks-sre-llmops-design.md#6-verification-and-evidence-definition-of-done)): **#3** push to
`main` → signed image in ECR → Argo CD synced · **#4** image size before and after, both images · **#5** CI fails on a
truncated catalogue, with the literal `IndexValidationError`.

From this stage on, Argo CD follows **`main`**: CI commits digests there.

---

## 0. Before you start — ops

Stage 2 passed. The workflows' action pins (commit SHAs) were reported by `make pins` in stage 2 and committed with the
other pins — `git grep -n '@PIN_ME' -- .github` must print nothing.

```bash
cd ~/Anime-Recommender && export KUBECONFIG=$HOME/.kube/anime
git grep -n '@PIN_ME' -- .github || echo "actions pinned"
yq --version; cosign version 2>&1 | grep -i gitversion
make -s shared-init >/dev/null && terraform -chdir=infra/terraform/shared output -raw ci_role_arn; echo
```

Expected: `actions pinned`, `mikefarah … v4.x`, a cosign version, and the CI role's ARN.

---

## 1. GitHub settings

**1.1 — ops: a deploy key for the bot.** A ruleset cannot exempt the workflow's own token, so the bot pushes with a key
of its own — the ruleset's one bypass (CI/CD A5.1). Its pushes start new runs; `[skip ci]` is what stops the loop.

```bash
cd ~/Anime-Recommender && export KUBECONFIG=$HOME/.kube/anime
( umask 077; ssh-keygen -t ed25519 -N '' -C anime-ci-release -f /tmp/anime-release-key -q )
echo "--- public (deploy key) ---"; cat /tmp/anime-release-key.pub
echo "--- private (Actions secret) ---"; cat /tmp/anime-release-key
```

**1.2 — browser**, repository *Settings*:

1. *Deploy keys → Add deploy key*: title `anime-ci-release`, the **public** line, **Allow write access**.
2. *Secrets and variables → Actions → Secrets*: `RELEASE_DEPLOY_KEY` = the **private** key (all lines, including
   `-----BEGIN…` and `-----END…`). Then on ops: `shred -u /tmp/anime-release-key /tmp/anime-release-key.pub; clear`.
3. *Secrets*: `HF_TOKEN` = the Hugging Face token. On ops:
   `aws secretsmanager get-secret-value --secret-id anime/llm --query SecretString --output text | jq -r .HF_TOKEN`,
   copy, then `clear`.
4. *Secrets and variables → Actions → Variables*: `AWS_CI_ROLE_ARN` = the ARN from step 0.
5. *Actions → General → Actions permissions*: allow actions from GitHub **and** third parties (aquasecurity, sigstore,
   anchore, aws-actions, docker). Leave *Workflow permissions* at **Read**: every job grants itself what it needs.

The ruleset comes in step 2, after the checks have run once — its picker only lists checks it has seen.

---

## 2. Merge the build branch into `main`

**2.1 — laptop:**

```powershell
git -C D:\DS-AI\LLMops\Anime-Recommender push origin anime/build
```

**2.2 — browser:** open a pull request `anime/build → main`. Its checks run as a pull request from this repository:
`lint-test`, `build (api)`, `build (ui)`, `ci-ok` — build and scan, **no push, no signature**. Expected: all green. Red at
`trivy — gate`: a critical finding with a fix exists — a real result; report it before merging.

**2.3 — browser: the ruleset.** *Settings → Rules → Rulesets → New branch ruleset*: name `main`, **Enforcement status:
Active**, target *Default branch*. Rules: **Require a pull request before merging** (required approvals **0** — a single
owner cannot approve their own pull request), **Require status checks to pass** → add `ci-ok` (source GitHub Actions),
**Block force pushes**. *Bypass list → Add bypass → Deploy keys*, "Always allow". Save.

`ci-ok` is the only required check: a fork's pull request skips `build`, whose matrix then never appears, and requiring
`build (api)` would leave such a pull request waiting for ever.

**2.4 — browser: merge** with **Create a merge commit** (not squash or rebase, so `anime/build` stays an ancestor of
`main`). The merge is a push to `main`: push by digest, sign, attest, and the bot commit `release: <sha> [skip ci]`.
Meanwhile Argo CD still follows `anime/build` — harmless until step 3.

**2.5 — browser: Actions**, filtered by branch `main`. Expected: the `ci` run of the merge commit with `release-commit`
green, exactly **one** new commit by `anime-ci[bot]`, and **no** `ci` run for that bot commit (it was skipped by
`[skip ci]`). Note the run's total duration.

---

## 3. Point Argo CD at `main` — ops

**3.1 — edit and plan.**

```bash
cd ~/Anime-Recommender && export KUBECONFIG=$HOME/.kube/anime
git fetch origin && git checkout main && git pull --ff-only
F=infra/terraform/bootstrap/terraform.tfvars
if grep -q '^target_revision' $F; then sed -i 's/^target_revision .*/target_revision           = "main"/' $F
else echo 'target_revision           = "main"' >> $F; fi
grep -q '^target_revision *= *"main"' $F && echo "target main" || echo "TARGET NOT SET"
make bootstrap-plan
```

Expected: `target main`, then `Plan: 0 to add, 1 to change, 0 to destroy.`

**3.2 — apply and wait for the new digests to run.**

```bash
cd ~/Anime-Recommender && export KUBECONFIG=$HOME/.kube/anime
make bootstrap
kubectl -n argocd annotate application root argocd.argoproj.io/refresh=hard --overwrite
HEAD=$(git rev-parse origin/main)
for i in $(seq 40); do
  s=$(for a in root anime-api anime-ui; do kubectl -n argocd get application $a \
        -o jsonpath='{.status.sync.revision} {.status.sync.status} {.status.health.status}{"\n"}'; done)
  [ "$(grep -c "^$HEAD Synced Healthy$" <<<"$s")" = 3 ] && { echo "root, api, ui at $HEAD, Synced Healthy"; break; }
  sleep 15
done
kubectl -n anime rollout status deploy/anime-api --timeout=5m && kubectl -n anime rollout status deploy/anime-ui --timeout=5m
```

Expected: `… Synced Healthy`, then both rollouts `successfully rolled out`. Every other child should follow too — re-run
stage 2, step 3 with the line `HEAD=$(git rev-parse origin/main)` in place of the `anime/build` one.

---

## 4. Criterion #3 — pushed, signed, and running — ops

cosign reads registry credentials from `~/.docker/config.json`, not from the instance role, so log in first.

```bash
cd ~/Anime-Recommender && export KUBECONFIG=$HOME/.kube/anime
git fetch -q origin && git pull -q --ff-only
REG=$(aws sts get-caller-identity --query Account --output text).dkr.ecr.ap-southeast-1.amazonaws.com
aws ecr get-login-password | docker login --username AWS --password-stdin "$REG" >/dev/null
ID='https://github.com/biabeogo147/Anime-Recommender/.github/workflows/ci.yml@refs/heads/main'
ISS=https://token.actions.githubusercontent.com
for svc in api ui; do
  d=$(yq '.image.digest' deploy/charts/anime-$svc/values.yaml)
  case "$d" in sha256:*) ;; *) echo "NO DIGEST IN GIT for $svc ($d)"; continue ;; esac
  running=$(kubectl -n anime get deploy anime-$svc -o jsonpath='{.spec.template.spec.containers[0].image}')
  echo "== anime-$svc  git: $d"
  [ "${running#*@}" = "$d" ] && echo "Deployment names the digest Git records" || echo "DEPLOYMENT NAMES $running"
  pods=$(kubectl -n anime get pods -l app=anime-$svc -o jsonpath='{range .items[*]}{.status.containerStatuses[0].imageID}{"\n"}{end}')
  [ -n "$pods" ] && ! grep -qv "$d\$" <<<"$pods" && echo "every pod runs it" || echo "PODS RUN: $pods"
  cosign verify "$running" --certificate-identity "$ID" --certificate-oidc-issuer "$ISS" -o text \
    > ~/anime-evidence/cosign-$svc.txt 2>&1 && echo "signature OK (this workflow, main)" || { echo "SIGNATURE FAILED"; tail -3 ~/anime-evidence/cosign-$svc.txt; }
  cosign verify-attestation "$running" --type spdxjson --certificate-identity "$ID" --certificate-oidc-issuer "$ISS" \
    > /dev/null 2>/tmp/att.err && echo "SBOM attestation OK" || { echo "SBOM ATTESTATION FAILED"; tail -3 /tmp/att.err; }
done
```

Expected per image: `Deployment names the digest Git records`, `every pod runs it`, `signature OK`, `SBOM attestation
OK`. The reference verified is the one the cluster pulls; the identity is **exact** — this workflow file on `main` — not a
pattern that would accept a feature branch (design §6 #3).

**The negative half — ops**, same shell or a new one:

```bash
cd ~/Anime-Recommender && export KUBECONFIG=$HOME/.kube/anime
ID='https://github.com/biabeogo147/Anime-Recommender/.github/workflows/ci.yml@refs/heads/main'
ISS=https://token.actions.githubusercontent.com
img=$(kubectl -n anime get deploy anime-api -o jsonpath='{.spec.template.spec.containers[0].image}')
ok=$(cosign verify "$img" --certificate-identity "$ID" --certificate-oidc-issuer "$ISS" >/dev/null 2>&1 && echo y)
out=$(cosign verify "$img" --certificate-identity "${ID%main}anime/build" --certificate-oidc-issuer "$ISS" 2>&1); rc=$?
[ "$ok" = y ] && [ $rc -ne 0 ] && grep -qi 'identit' <<<"$out" && echo "wrong identity rejected: correct" \
  || { echo "INCONCLUSIVE (positive=$ok rc=$rc)"; tail -3 <<<"$out"; }
```

Expected: `wrong identity rejected: correct`. It counts only if the right identity passed in the same run and the failure
is about the identity — not a network or login error.

**One more release, hands off — laptop + browser.** Criterion #3 must also hold without the manual switch of step 3:
make a trivial change on a branch (for example a comment in `README.md`), open a pull request, merge it. Expected: the
`ci` run on `main` releases, and within a few minutes — no command from you — step 3.2's wait loop and step 4 pass again
with the **new** digests (the build is not reproducible, so the digest changes). Report this run's duration: it is the
pipeline duration of #3.

---

## 5. Criterion #4 — both images — browser

The merge run's *Summary* carries `anime-api <size> (docker …, store: …)` and the same for `anime-ui`. Report both lines.
The "before" is the local single image, **6.45 GB** (`docs/evidence/local.md`). State both new sizes against it — never
the api alone (CI/CD A7.1) — together with the store type, which changes what "size" means.

---

## 6. Criterion #5 — a truncated catalogue fails, for the right reason — browser

*Actions → index-negative → Run workflow* (branch `main`, `drop_rows` 10).

Expected: the job is **green** — it passes only when the build fails **and** the log carries
`IndexValidationError: Loaded 259 documents …, expected 269`. Its summary says `failed on IndexValidationError, as it
must`. Red means the truncated build succeeded, or failed for another reason (a missing `HF_TOKEN` shows as
`HF_TOKEN is not set`) — report it.

---

## 7. The Trivy positive control — browser

The gate ignores findings with no fix; on Debian 12 every critical finding may be unfixable, and then the gate passes
every build by construction (CI/CD A3.5). Prove it can fail: *Actions → ci → Run workflow* on `main`, `trivy_severity` =
`HIGH,CRITICAL`. A dispatched run scans but never pushes.

Expected: **red** at `trivy — gate (fixable only)` for at least one image. Still green: `MEDIUM,HIGH,CRITICAL`. Report the
lowest threshold that turned it red, and from the **normal** run's summary the `all findings` and `fixable (the gate)`
lines. Until one run has gone red, the gate is recorded as **unproven**.

---

## 8. Evidence

Report: the hands-off run's duration (4), the output of step 4 and its negative half, the two size lines (5), the
`index-negative` run URL and its error line (6), and the positive control's threshold and counts (7). They become
`docs/evidence/cicd.md`.

---

## Troubleshooting

| Symptom | Likely cause | What to do |
|---|---|---|
| No run starts | Third-party actions not allowed | 1.2, item 5 |
| A step fails `unable to resolve action … @PIN_ME` | An action pin was not committed | Step 0 must print `actions pinned` |
| *Run workflow* button missing | The workflow is not on the default branch yet | Merge first; the default branch must be `main` |
| `Could not assume role with OIDC` | Variable wrong, or the run is not a push to `main` | The trust names exactly `…:ref:refs/heads/main`; pull requests and dispatches cannot assume it, by design |
| `build (api)` fails with `HF_TOKEN is not set` | Secret missing, or a fork/Dependabot pull request | 1.2 item 3; forks and Dependabot never have it (build is skipped for them) |
| `trivy — gate` red on a normal run | A critical finding with a fix | Real: bump the base image or the package; details in *Security → Code scanning* |
| Merge blocked: "Expected — waiting for status" | The required check name does not match | The only required check is `ci-ok` |
| `release-commit`: `GH013: Repository rule violations` | The deploy key is not in the bypass list, or has no write access | 1.2 item 1 and 2.3 |
| `release-commit`: `Permission denied (publickey)` | `RELEASE_DEPLOY_KEY` secret is not the private half, or was truncated | Regenerate (1.1) and replace both halves |
| `release-commit` says "newer commit … will release" | Two merges close together | Expected: the newer run releases |
| `release-commit`: "more than the digest line changed" | The values file's digest line has another format | Report the diff; the sed expects `  digest: <value>` |
| A second `ci` run starts on the bot commit | `[skip ci]` missing from its message | The workflow always writes it; check the commit |
| `cosign verify`: `denied`, `401`, `token has expired` | No or stale ECR login for cosign | The `docker login` line at the top of step 4 |
| `cosign verify`: `no matching signatures` while CI signed | Wrong identity, or a signature format mismatch between cosign versions | Identity must match exactly; retry with `--new-bundle-format=false` and report the cosign version in CI's installer log |
| `cosign verify`: Rekor/Fulcio unreachable | Sigstore down, or no internet from ops | Retry later; signing on `main` fails the same way (CI/CD A9.1) |
| SARIF upload fails | Code scanning unavailable (private repository without Advanced Security) | Fine while the repository is public |
| Applications stay on `anime/build` | Bootstrap not re-applied | 3.1 must print `target main`; `make bootstrap-plan`, `make bootstrap` |
| Pods do not move to the new digest | Argo CD has not fetched `main` yet | Hard refresh (3.2); `make -s apps` |

---

[README](README.md) · [Concepts](concepts.md) · [Design §4.6](../eks-sre-llmops-design.md#46-cicd-github-actions-githubworkflows) ·
Previous: [GitOps guide](../gitops/guide.md)
