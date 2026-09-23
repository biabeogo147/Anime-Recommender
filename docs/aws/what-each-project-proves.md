# What each project proves

Two projects, one subject split in half. This page is for the half-hour before an interview: which skill each
project actually demonstrates, so neither one is sold as the other and the same story is not told twice.

**No measured value appears on this page.** Every row cites a criterion number and the file that holds the
measurement, and nothing else. The values live in one place per project — `docs/evidence/` — and a figure copied
into a second file goes stale the day the drill is re-run. That has already happened once here: an Anime answer
quoted Medical's rebuild time long after Medical's own evidence had superseded it and called the old number not
comparable. Cite the path; read the number from the path.

Related: [the design differences](compare-to-medical-rag-chatbot.md), [the same comparison stage by
stage](compare-by-stage.md), and the spoken answers in [questions.md](questions.md) / [answers.md](answers.md).

## In one sentence each

**Medical answers "can you run Kubernetes?"** Terraform makes three EC2 instances and Ansible turns them into a
kubeadm cluster where every node is both control plane and worker. The cluster is the work product: etcd, the
certificates, the upgrade path and the CI system all belong to whoever built it.

**Anime answers "can you run a service on Kubernetes?"** AWS runs the control plane; the work moves up a level,
to the reliability of one service on top of it — what it promises, how it is released, when it scales, and what
each request costs.

Both designs say this themselves, and split the subject deliberately so neither repeats the other:
[Anime design §1](../eks-sre-llmops-design.md#1-goal) and §1 of
`Medical-RAG-Chatbot/docs/selfmanaged-k8s-ops-design.md`, each of which carries the same split table.

## The capability matrix

| Capability | Project | Criterion | Where the measurement lives |
|---|---|---|---|
| Infrastructure from empty, then a re-plan with no changes | both | #1 each | `A: docs/evidence/terraform.md` · `M: docs/evidence/terraform.md` |
| Building a control plane, and a second run that changes nothing | Medical | #2 | `M: docs/evidence/ansible.md` |
| Surviving the loss of a control-plane node | Medical | #3 | `M: docs/evidence/ansible.md` |
| etcd backup, and a timed restore | Medical | #12 | `M: docs/evidence/drills.md` |
| A Kubernetes upgrade run as a procedure | Medical | #14 | `M: docs/evidence/drills.md` |
| CI a team hosts itself | Medical | #8 | `M: docs/evidence/jenkins.md` |
| Signing with a key you own, and refusing unsigned images at admission | Medical | #9, #13 | `M: docs/evidence/jenkins.md`, `drills.md` |
| Certificates issued and renewed by something you operate | Medical | #4, #5 | `M: docs/evidence/gitops.md` |
| Promotion between environments, gated by a person | Medical | #10 | `M: docs/evidence/jenkins.md` |
| CI on a hosted runner, federated into AWS with no stored key | Anime | #3 | `A: docs/evidence/cicd.md` |
| A check that can say no, proven by making it fail | Anime | #5 | `A: docs/evidence/cicd.md` |
| A latency objective taken from real traffic, not chosen | Anime | #6 | `A: docs/evidence/load.md` |
| The capacity of a known deployment, measured | Anime | #7 | `A: docs/evidence/load.md` |
| A release that judges itself and rolls itself back | Anime | #8, #9 | `A: docs/evidence/delivery.md` |
| An alert that fires on a burning error budget, not on a symptom | Anime | #10 | `A: docs/evidence/slo.md` |
| Scaling on the signal that saturates first | Anime | #14 | `A: docs/evidence/scaling.md` |
| Knowing what one request costs, and where its time went | Anime | #11, #12 | `A: docs/evidence/tracing.md` |
| A GitOps tree that converges from nothing | both | A #2 · M #5 | `A: docs/evidence/gitops.md` · `M: docs/evidence/gitops.md` |
| Internal interfaces reachable only through a VPN | both | A #16 · M #4 | `A: docs/evidence/gitops.md` · `M: docs/evidence/gitops.md` |

`A:` is this repository, `M:` is Medical-RAG-Chatbot. A path that does not exist yet means the stage that fills
it has not run — see [status](#status-what-is-built-and-what-is-designed) before claiming that row.

## Only Medical proves it

Every item here needs something EKS takes away.

- **That a control plane can be built and rebuilt.** kubeadm on three EC2 instances, an HA API server behind an
  internal NLB, and a second Ansible run that changes nothing. On EKS there is no control plane to build.
- **That etcd can be restored.** Snapshots to S3 on a schedule, and a restore drill timed end to end. EKS gives
  no etcd access at all, so Anime has nothing to snapshot and no restore to practise — its recovery path is Git
  plus a rebuild.
- **That a cluster can be upgraded deliberately.** A playbook, node by node, gated on compatibility. On EKS, AWS
  upgrades the control plane; what is left is the node group and the add-ons.
- **That CI can be hosted rather than rented.** Jenkins inside the cluster, with its own agents, its own
  credentials and its own failure modes — reachable only through the VPN, which is why it polls instead of being
  called by a webhook.
- **That a signature can be enforced, not just produced.** Cosign with an AWS KMS key, and Kyverno refusing
  unsigned images in prod. Anime signs keylessly but verifies by hand once: enforcement is a stated non-goal
  there, written down rather than quietly skipped.
- **That certificates can be operated.** cert-manager, a Let's Encrypt wildcard by DNS-01, and a bought
  certificate for one host. Anime's certificates come from ACM, which AWS issues and renews.
- **Network policy that is actually enforced.** Calico, including blocking the metadata address. With the VPC
  CNI, Anime has none unless it is switched on separately.
- **IRSA assembled by hand**, including hosting the OIDC issuer, against Anime's EKS Pod Identity.

## Only Anime proves it

Every item here needs a service worth measuring, and a cluster someone else keeps alive.

- **That a promise to users can be a number.** A latency target read server-side from real traffic, at a
  histogram boundary that exists, and an SLO written against it. Medical has no SLO, so it never needed the
  number.
- **That a release can judge itself.** A canary walking 10 → 50 → 100 on measurements, and a bad version
  aborting without a human. Medical promotes by a pull request that a person merges — which is a different,
  equally defensible answer, and the contrast is the interesting part.
- **That scaling can follow the right signal.** In-flight requests rather than CPU, with the threshold taken
  from where the service actually saturates. In this service CPU stays low while the thread pool saturates, so
  CPU-based scaling would react late or not at all.
- **That capacity is a figure, not an adjective.** A ramping arrival rate against a known replica count, with
  the break-away rule written down before the run.
- **That an LLM's cost and latency can be seen per request.** OpenTelemetry `gen_ai.*` spans, token counts and
  a dollar estimate. Medical exposes metrics and has no traces, no token accounting and no cost.
- **That managed services have to be wired, not just switched on.** An ALB built from an Ingress, one
  IngressGroup for four interfaces, readiness gates, external-dns writing the names, ACM on the listener, and
  one IAM role per controller's ServiceAccount. None of this exists in a self-managed cluster — and none of it
  is free of failure modes, which is the honest half of the story.

## Both prove it — say it once

These are the rows where two projects sound like one. Pick the project the question is about, lead with the
detail that differs, and do not tell the second version unless asked.

| Shared ground | Lead with, in Medical | Lead with, in Anime |
|---|---|---|
| Terraform from empty, re-plan clean | state and lifetime split across stacks, and Ansible taking over where Terraform stops | the same split, plus what the plan file is for and why it can go stale |
| Argo CD app-of-apps with sync waves | ordering a cluster's own components into existence | the health check that requires Synced as well as Healthy, and `ignoreDifferences` |
| Secrets that never enter Git or state | values typed into Secrets Manager, rights from the node role | the same, with rights scoped per ServiceAccount through Pod Identity |
| Internal interfaces on a VPN only | ingress-nginx allowing VPC addresses, in front of an internal NLB | a security group on an internal ALB, and a check run from the laptop both ways |
| Evidence for every claim | the drills, and what they superseded | the same discipline, including a load run discarded by its own rule |

## If asked, answer from

| The question | Answer from | Because |
|---|---|---|
| "Have you run Kubernetes, not just used it?" | Medical | it is the only one with a control plane of its own |
| "What do you do when the cluster will not come up?" | Medical | its failures are cluster failures, and they are written down |
| "How do you recover from losing the cluster's state?" | Medical | a timed etcd restore exists; Anime rebuilds instead |
| "How do you decide when to scale?" | Anime | the threshold comes from a measured saturation point |
| "How do you know a release is safe?" | Anime | the canary decides on measurements, with no human in the path |
| "What do you alert on?" | Anime for the principle, Medical for the contrast | one alerts on burning budget, the other on causes |
| "How do you secure a software supply chain?" | Medical | it both signs and enforces; Anime signs and says so |
| "What does your AI feature cost to run?" | Anime | tokens and dollars per request are instrumented there |
| "Tell me about a time you were wrong" | either — both record their own defects | the evidence files name what tripped, including the mistakes |

## What neither project proves

Worth knowing before being asked. **(stated)** means the design names it as out of scope; **(absent)** means it
simply is not there.

| Gap | Anime | Medical |
|---|---|---|
| Multi-region, or DR beyond etcd | (absent) — one region, and an untimed rebuild as the recovery path | (stated) non-goal |
| Service mesh | (absent) | (stated) non-goal |
| Real user traffic | (absent) — all load is generated, and the cluster is destroyed between sessions | (absent) — the same |
| On-call, paging, escalation | (absent) — alerts reach a chat webhook; no rotation, no dead-man's switch | (stated) — the lab does not run continuously |
| Multi-tenancy | (absent) — one namespace by design | (absent) — two namespaces, one owner |
| Admission policy beyond signatures | (stated) non-goal, and left to Medical | partly — signatures are enforced; baseline pod-security policy is not |
| Compliance frameworks (SOC 2, CIS, PCI) | (absent) | (absent) |
| Authentication in front of internal interfaces | (absent) — the VPN is the only gate | (stated) — a deferred P2, with the gap written down |
| Highly available NAT | (stated) — one NAT gateway, a documented single point of failure | (stated) — the same choice, documented |
| Chaos engineering | (absent) | (absent) — the closest is one manual node-stop drill |

The right posture on these is not apology. Each one was a scoping decision made under a budget and a deadline,
and both designs name the ones they knowingly dropped.

## Status: what is built, and what is designed

**Read this from `docs/evidence/`, not from this page.** A criterion's evidence file exists when the stage that
produces it has run; a row in the matrix above whose path does not exist yet is designed, not proven. As a
starting point: Medical is built and its drills phase is done; Anime, at the time of writing, has built the
cluster, the GitOps tree and the pipeline, and is part-way through the load stage.

Saying "designed" out loud about the parts that are designed costs nothing. Saying "built" about them is the
one thing an interviewer can check in a minute, from the repository itself.
