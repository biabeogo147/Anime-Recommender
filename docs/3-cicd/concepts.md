# Stage 3 — Concepts

Every idea [`README.md`](README.md) relies on, defined once. Each section answers **what it is**, **how it runs
here**, and **what breaks without it**. The workflow's steps and flags are in
[design §4.6](../eks-sre-llmops-design.md#46-cicd-github-actions-githubworkflows). OIDC federation, which CI uses
to reach AWS, is defined in [stage 1](../1-terraform/concepts.md#8-oidc-federation-for-ci).

---

## 1. CI and CD as separate jobs

**What it is.** *Continuous integration* turns a change into a verified artefact. *Continuous delivery* puts an
artefact into an environment. They can be one pipeline, or two systems that meet at a hand-off.

**How it runs here.** Two systems. GitHub Actions ends by committing a digest to Git; Argo CD, inside the
cluster, pulls Git and deploys. The hand-off is a commit — visible, reviewable, revertible.

**What breaks without the separation.** CI needs credentials to the cluster and becomes the thing that decides
what runs. The cluster is then "whatever the last pipeline did", and rolling back means re-running an old
pipeline rather than reverting a line.

---

## 2. A digest, not a tag

**What it is.** A *tag* such as `v1.4` is a movable name in a registry. A *digest* is the SHA-256 of an image's
manifest — the document that lists its layers by their own digests — so it pins the content indirectly but
completely. When a build pushes an *index* (several manifests, for platforms or attached provenance), the index
has a digest of its own, and that is the one to use.

**How it runs here.** The same digest is pushed, written into Git, deployed, signed and attested.

**What breaks without it.** With tags, the thing Git names, the thing that runs and the thing that was signed can
drift apart without any of them changing: re-point a tag and all three still "match".

---

## 3. A check wired to fail

**What it is.** A check whose failing case has been produced on purpose and seen. The opposite is a check that
has only ever passed — for which "it passed", "it never ran" and "it could not fail" look the same.

**How it runs here.** The index check was made to fail locally by changing the expected count. Criterion #5 makes
it fail in CI a different way, by truncating the data — the fault that would actually occur — and requires the
named error rather than any failure.

**What breaks without it.** Every check becomes a claim nobody has tested. The pipeline stays green through the
exact mistakes it was built to catch, and the first anyone hears of it is in production.

---

## 4. Vulnerability scanning, and a gate that can fail

**What it is.** A scanner lists known vulnerabilities in an image's packages, each with a severity and sometimes a
fixed version. A *gate* fails the build above a threshold. A *positive control* is a deliberate run constructed so
that a working gate must fail.

**How it runs here.** The gate counts critical findings that have a fix. Every run also records the total, so
"nothing fixable" is visibly different from "nothing there". A positive control turned it red at MEDIUM, so the gate
is proven, not just passing.

**Why the count alone is not enough.** The gate fails whenever the fixable count is above zero — so every run that
passes records zero, by definition. A recorded zero is a restatement of the pass, not evidence about the gate.

**What breaks without it.** A filter that excludes everything looks exactly like a clean image. On a base where no
critical finding has a fix, a gate that has never been seen to fail is a gate that cannot.

---

## 5. SBOM and attestation

**What it is.** An *SBOM* (software bill of materials) lists every package in an image. An *attestation* is a
signed statement about an artefact — here, "this is the package list of this digest".

**How it runs here.** Generated in CI and attached to the digest as a signed attestation.

**What the signature does and does not stop.** Anyone who can push can attach a *second* attestation to the same
digest. The signed one is distinguishable only if verification pins who signed it, the same way image
verification does.

**What breaks without it.** When a new vulnerability is announced, finding which images contain the package means
pulling and rescanning each one. An SBOM is an inventory that can be queried without touching the images at all.

---

## 6. Keyless signing

**What it is.** Sigstore's way of signing without a long-lived key. The signer generates a throwaway key pair in
memory, proves its identity with an OIDC token, and receives a certificate valid for minutes that binds that key
to that identity. The signature and certificate are recorded in *Rekor*, a public append-only log, whose timestamp
shows the signing happened while the certificate was valid. The throwaway key is then discarded.

**How it runs here.** Only on `main`, after the scan. The identity is the release workflow on that branch.

**What breaks without it.** Nobody can later show that the image running came out of this pipeline rather than off
somebody's laptop. The alternative, a long-lived key, has to be stored, rotated and protected — which is what
Medical does with KMS.

---

## 7. Verifying a keyless signature

**What it is.** Checking that the certificate chains to Sigstore's root, that the signature is in the log, and —
since there is no fixed key to compare against — that the identity in the certificate and the issuer that vouched
for it are the ones expected.

**How it runs here.** By hand, for criterion #3: the digest Git recorded, the issuer fixed to GitHub's, and the
identity given **exactly** — this repository, the release workflow file, the `main` branch.

**What a looser identity accepts.** A regular-expression identity is a substring search unless anchored. Anchored
to the repository, it still accepts any workflow on any branch. Only the exact identity says *this pipeline,
releasing*.

**What breaks without verification.** Nothing visible — which is the problem. A signature nobody checks proves an
image *could* be checked.

---

## 8. The bot commit, and a pipeline that cannot trigger itself

**What it is.** A commit made by the pipeline, to the branch the pipeline listens to — so it could start the
pipeline again.

**How it runs here.** One line, on `main`, marked `[skip ci]`, written by the single identity the ruleset exempts
from "pull requests only".

**Why the marker stays.** A push made with the workflow's own token does not start new runs; a push made with any
other credential — a deploy key, an app token — does. The bot uses a deploy key, so its pushes do start runs, and
the marker is the only guard.

**What breaks without it.** Either an endless loop of builds and commits, or protection weakened for everyone so
that one robot can write.

---

## 9. Forks and secrets

**What it is.** A pull request from a fork runs without the repository's secrets, because its code was written by
someone outside the project and has not been reviewed.

**How it runs here.** The index needs a token to build, and the index is inside the image, so a fork's pull request
stops after lint and unit tests. A pull request from this repository builds and scans; no image leaves the runner.

**What breaks without the distinction.** Either secrets are handed to unreviewed code, or the pipeline appears to
have checked something from outside that it never built.

---

## 10. An evaluation gate, and its baseline

**What it is.** A check on *quality* rather than correctness: run fixed questions with known good answers, compute
a score, fail if it drops below a stored baseline.

**How it runs here.** P1, on pull requests, as its own workflow. Retrieval only — no model is called — but the
queries are still embedded through the Hugging Face API, so it needs the token and can be rate-limited.

**What breaks without a fixed baseline.** A pull request that regenerates the baseline along with its change is
comparing the change with itself and always passes. The baseline has to come from before the pull request began.

---

[README](README.md) · [Design §4.6](../eks-sre-llmops-design.md#46-cicd-github-actions-githubworkflows)
