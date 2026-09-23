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

| Capability | Project | Criterion | Status | Where the measurement lives |
|---|---|---|---|---|
| Infrastructure from empty, then a re-plan with no changes | both | A #1 · M #1 | **measured** both | `A: docs/evidence/terraform.md` · `M: docs/evidence/terraform.md` |
| Building a control plane, and a second run that changes nothing | Medical | #2 | **measured** | `M: docs/evidence/ansible.md` |
| Surviving the loss of a control-plane node | Medical | #3 | **measured** | `M: docs/evidence/ansible.md` |
| etcd backup, and a timed restore | Medical | #12 | **measured** | `M: docs/evidence/drills.md` |
| A Kubernetes upgrade run as a procedure | Medical | #14 | **partly** — the patch path only; the minor upgrade #14 asks for has not run | `M: docs/evidence/drills.md` |
| CI a team hosts itself | Medical | #8 | **measured** | `M: docs/evidence/jenkins.md` |
| Signing with a key you own, and refusing unsigned images at admission | Medical | #9, #13 | **measured** | `M: docs/evidence/jenkins.md`, `drills.md` |
| Certificates issued and renewed by something you operate | Medical | — (no criterion of its own) | **partly** — configured and in use; the capture is listed as still to record | `M: docs/evidence/gitops.md` |
| Promotion between environments, gated by a person | Medical | #10 | **measured** | `M: docs/evidence/jenkins.md` |
| A GitOps tree that converges from nothing | Medical | #5 | **measured**, inside the rebuild drill | `M: docs/evidence/drills.md` |
| Internal interfaces reachable only through a VPN | Medical | #4 | **planned** — `gitops.md` lists the captures as still to record | `M: docs/evidence/gitops.md` |
| A commit reaching the cluster as a signed digest | Anime | #3 | **measured** | `A: docs/evidence/cicd.md` |
| One image split in two, and both measured | Anime | #4 | **measured** | `A: docs/evidence/cicd.md` |
| A check that can say no, proven by making it fail | Anime | #5 | **measured** | `A: docs/evidence/cicd.md` |
| A latency objective taken from real traffic, not chosen | Anime | #6 | **measured** | `A: docs/evidence/load.md` |
| The capacity of a known deployment | Anime | #7 | **planned** — the run that gives it has not produced a valid number yet | `A: docs/evidence/load.md` |
| A GitOps tree that converges, and HTTPS and VPN-only admin UIs | Anime | #2, #15, #16 | **run, recorded unquoted** — the checks ran and matched; the output was not captured | `A: docs/evidence/gitops.md` |
| A release that judges itself | Anime | #8 | **measured** | `A: docs/evidence/delivery.md` |
| A release that rolls itself back | Anime | #9 | **measured** | `A: docs/evidence/delivery.md` |
| An alert that fires on a burning error budget | Anime | #10 | **measured** | `A: docs/evidence/slo.md` |
| Scaling on the signal that saturates first | Anime | #14 | **measured** | `A: docs/evidence/scaling.md` |
| Cost and latency per request, for an LLM call | Anime | #11, #12 | **measured** | `A: docs/evidence/tracing.md` |

`A:` is this repository, `M:` is Medical-RAG-Chatbot. **Read the status column, not the path**: a file can exist
and still not hold the criterion — Anime's `load.md` holds #6 while #7 inside it is pending, and Medical's
`gitops.md` names captures it has not taken. Only a row marked **measured** may be spoken in the past tense.
Statuses are as of 2026-09-23; the evidence files are the live version.

## Only Medical proves it

Every item needs something EKS takes away: a control plane to build and rebuild, an etcd to snapshot and
restore, an upgrade to run node by node, a CI system to host, a signature to *enforce* at admission, certificates
to operate, and NetworkPolicy that is actually enforced. The itemised list, with why Anime has no counterpart
for each, is in [Only in Medical](compare-by-stage.md#only-in-medical).

The distinction worth making out loud: **Anime does not skip these — EKS removes the object**. There is no
control plane to build, no etcd to snapshot, and ACM issues and renews the certificates. The one real gap is
admission: Anime signs keylessly and verifies by hand once, and its design names enforcement a non-goal rather
than passing over it.

## Only Anime proves it

Every item needs a service worth measuring and a cluster someone else keeps alive: a latency target read from
real traffic, a canary that judges itself, scaling on in-flight requests rather than CPU, a measured capacity,
and per-request tokens and cost. The itemised list, with why Medical needs none of them, is in
[Only in Anime](compare-by-stage.md#only-in-anime).

Two things that list does not say, and that an interview will reach for:

- **Why CPU is the wrong signal here.** Under load this service's CPU stays near a fifth of a core per pod while
  its thread pool saturates — the threads are asleep waiting on the provider. A CPU-based autoscaler would react
  late or never, which is why the threshold comes from in-flight requests (#7 feeds #14).
- **That managed services must be wired, not switched on.** An ALB built from an Ingress, one IngressGroup for
  four interfaces, readiness gates, external-dns writing the names, ACM on the listener, and one IAM role per
  controller's ServiceAccount — each with its own failure modes, several of which this repo has hit and
  recorded ([design §3](../eks-sre-llmops-design.md)).

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
