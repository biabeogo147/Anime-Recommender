# Stage 3 — CI/CD: evidence

Criteria **#3**, **#4** and **#5** ([design §6](../eks-sre-llmops-design.md#6-verification-and-evidence-definition-of-done)),
from the [CI/CD guide](../3-cicd/guide.md), 2026-09-22. Output as reported. Rows marked *pending* have not been
reported yet; nothing below is inferred.

## #3 — pushed, signed, and running

Guide step 4, positive half, run on the ops workstation after the merge release:

| Image | Digest in Git (`deploy/charts/anime-*/values.yaml`) | Deployment | Pods | Signature | SBOM attestation |
|---|---|---|---|---|---|
| anime-api | `sha256:187f3fe92ac5f31552c37f13ff2ba997e80f2b3724c4daa9706df3efd1e6dab0` | names it | every pod runs it | OK (this workflow, `main`) | OK |
| anime-ui | `sha256:b2e48256ab3deb2694d0d6215dac5a9d05987e84854de617f89405cc8713ce1d` | names it | every pod runs it | OK (this workflow, `main`) | OK |

The verified reference is the one the cluster pulls. The identity checked is exact:
`https://github.com/biabeogo147/Anime-Recommender/.github/workflows/ci.yml@refs/heads/main`.

The negative half passed as expected: a signature checked against another branch's identity was refused
(`wrong identity rejected: correct`). Steps not reported otherwise gave their expected output.

The hands-off release also passed: a trivial pull request was merged, and step 3.2's loop and step 4 passed again
with the new digests. **#3: pass.**

| Still needed for #3 | Status |
|---|---|
| That run's duration: the pipeline duration of #3 | *pending*: a measured number, not an expected output |

**Found on the way.** The first release run failed at *AWS credentials (OIDC, no key)* with
`Could not load credentials from any providers`. The action prints this when `role-to-assume` is empty, which
points at the repository variable `AWS_CI_ROLE_ARN` (guide 1.2). The failure came before the push, so ECR and
Git were unchanged. A later release passed (above). What was changed in between is not recorded.

## #4 — both images

From the merge run's summary:

| Image | Size | Measured with |
|---|---|---|
| anime-api | **619 MB** | docker 28.0.4, store overlay2 |
| anime-ui | **559 MB** | docker 28.0.4, store overlay2 |
| Before: the single original image | **6.45 GB** | local build ([local.md](local.md)) |

Together the two images are **1.18 GB**, against the 6.45 GB single image they replace. The api alone is not the
comparison: quoting it alone would compare one image against two. With the overlay2 store Docker reports
uncompressed sizes, as the local measurement did. **#4: pass.**

## #5 — a truncated catalogue fails, for the right reason

*Actions → index-negative*, `drop_rows` 10:

```
#13 1.963 IndexValidationError: Loaded 259 documents from /app/data/anime_with_synopsis.csv, expected 269
failed on IndexValidationError, as it must
```

The job is green because the build failed, and failed with the named error. A failure for any other reason
would have turned it red. **#5: pass.** Run URL: *pending*.

## The Trivy gate's positive control

A manual `ci` run with `trivy_severity` = `MEDIUM,HIGH,CRITICAL`:

| Image | All findings | Fixable (the gate counts these) |
|---|---|---|
| anime-api | 169 | 5 |
| anime-ui | 165 | 5 |

| Threshold | Gate |
|---|---|
| `MEDIUM,HIGH,CRITICAL` | **red** at `trivy — gate (fixable only)` |
| `HIGH,CRITICAL` | green |
| `CRITICAL` (the normal runs) | green |

The lowest threshold that turns the gate red is **MEDIUM**: the fixable findings on these images are all MEDIUM.
So the gate **can** fail: it is proven, not just passing (design §4.6). At the severities the gate uses on every
build, CRITICAL, no finding has a fix, as the design predicted for Debian 12. That is why it stays green.
The normal run's `all findings` count at `CRITICAL` was not reported separately.
