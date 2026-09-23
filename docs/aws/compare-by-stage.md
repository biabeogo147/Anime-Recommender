# Anime and Medical, stage by stage

**For each stage the two projects share, what each one decided and why they decided differently. For each stage
only one of them has, why the other does not need it.** The overview, including why one uses NLBs and the other
ALBs, is in [compared with Medical](compare-to-medical-rag-chatbot.md). This page goes one level down.

Every reason below comes from the two projects' own documents. Medical's are cited by path in the
`Medical-RAG-Chatbot` repository. The design is `docs/selfmanaged-k8s-ops-design.md`, and each stage has
`docs/<stage>/README.md`, with evidence in `docs/evidence/<stage>.md`. Where neither project writes down a
reason, the row says so instead of inventing one.

**The stages line up like this:**

| Medical | Anime | Section |
|---|---|---|
| terraform | [1-terraform](../1-terraform/README.md) | [Terraform](#terraform) |
| app | the app phase before stage 1 ([design §4.1](../eks-sre-llmops-design.md#41-the-application)) | [The application](#the-application) |
| gitops | [2-gitops](../2-gitops/README.md) | [GitOps](#gitops) |
| jenkins | [3-cicd](../3-cicd/README.md) | [CI](#ci) |
| ansible, drills | — | [Only in Medical](#only-in-medical) |
| — | 4-load, 5-delivery, 6-slo, 7-scaling, 8-tracing | [Only in Anime](#only-in-anime) |

Medical's phases ran in the order terraform → ansible → app → gitops → jenkins → drills. Anime fixed its app first,
before stage 1.

**One reason is behind many rows, so it is stated once here.** The two projects split features on purpose, so
that together they tell two stories:
- Medical covers cluster operations, delivery and the supply chain.
- Anime covers SLOs, canary releases, autoscaling and LLM observability.

Medical's design lists canary releases and SLO alerting as non-goals because "these belong to Anime"
(`selfmanaged-k8s-ops-design.md` §1). When a row says *by the split*, this is the reason.

---

## Terraform

**Medical** creates the machines Kubernetes will be installed on. **Anime** asks AWS for a cluster, and creates
what the cluster needs around it.

| Decision | Medical | Anime | Why they differ |
|---|---|---|---|
| The three stacks | `bootstrap` (state bucket and ops workstation, applied from CloudShell, never destroyed), `shared`, `cluster` | `shared`, `cluster`, and a `bootstrap` that installs Argo CD **through the tunnel** | Anime reuses Medical's state bucket and workstation, so it has no stack of its own for them. Its third stack exists for another reason: with no public API endpoint, Argo CD can only be installed once `make tunnel` is open, so it cannot be part of the apply that creates the cluster. Same name, opposite meaning: Medical's `bootstrap` is never destroyed, Anime's is applied last and discarded first |
| What `shared` keeps | ECR, the index artifacts bucket, a KMS signing key, the IRSA issuer bucket and 4 roles, 10 secrets, the Route 53 zone, the budget | ECR, 4 secrets, the GitHub OIDC role, the budget, **the ACM certificate** | Each of Medical's extra items belongs to a choice Anime made differently:<br>• The artifacts bucket holds an index that "costs Hugging Face quota to build". Anime builds its much smaller index into the image.<br>• A new KMS key "invalidates every existing signature". Anime signs keylessly.<br>• The issuer exists because a self-managed cluster has no IRSA. EKS has Pod Identity.<br>Anime's certificate is here because in `cluster` it would be re-issued on every rebuild, and "AWS renews it" would never be true ([1-terraform, Decision 1](../1-terraform/README.md#decision-1--split-by-lifetime-not-by-topic)).<br>Anime has no zone of its own: it writes into Medical's, "because a second registered domain costs money every year" (design §10). Medical's `shared` has since gained the etcd backup bucket too, in its drills phase |
| Network | VPC `10.10.0.0/16`, 3 AZs, 3 public and 3 private subnets, 1 NAT | VPC `10.30.0.0/16`, 2 AZs, 2 private and 2 public subnets, **2 small subnets for the control plane's network interfaces**, 1 NAT, subnets tagged for load balancers | **3 AZs vs 2:** Medical puts "one machine per availability zone", so losing a zone leaves "two of three etcd members… still a quorum" (`docs/ansible/README.md`). Anime runs no control plane of its own. Its documents give no reason for two zones; AWS requires at least two for EKS.<br>**Control-plane subnets:** they let the VPN gateway drop tunnel traffic to the API while still forwarding 443 to the internal ALB.<br>**Subnet tags:** without them "an Ingress is created and simply never gets a load balancer" (design §3). Medical has no controller that reads them |
| One NAT | "Saves about 0.12 USD/hour"; a single point of failure, documented | Same | Same trade, carried over |
| Nodes | 3× `m7i-flex.large` On-Demand, one per AZ, each both control plane and worker | Managed node group, **Spot** `m7i-flex.large`, 2 to 4 | Both types come from the same limit: the AWS Free plan launches only free-tier-eligible types (both evidence files).<br>**Medical's three:** three etcd members survive the loss of one. Its documents do not discuss Spot.<br>**Anime's Spot:** chosen for cost ([1-terraform, Decision 3](../1-terraform/README.md#decision-3--spot-and-what-it-forces-on-every-later-stage)). A single type, because "one node group needs one size for the Cluster Autoscaler's template" (design §3) |
| Load balancers in Terraform | Two NLBs: 6443 for the API, 443 and 80 for ingress-nginx | None | Covered in the [overview, section 5](compare-to-medical-rag-chatbot.md#5-why-medical-uses-nlbs-and-anime-uses-albs) |
| How `kubectl` reaches the API | SSM port-forward **through node 1** to the internal NLB; `127.0.0.1` added to the API certificate's names | SSM port-forward **through the WireGuard gateway** to the private endpoint; `tls-server-name` in the kubeconfig | Medical issues its own API certificate, so it can add `127.0.0.1`. EKS's certificate "is not ours to reissue".<br>Anime tunnels through the gateway because it is already an instance inside the VPC, built for the VPN, "exactly what an SSM port-forward needs as its far end" ([1-terraform, Decision 2](../1-terraform/README.md#decision-2--the-api-server-has-no-public-address)) |
| AWS rights for pods | Self-built IRSA for the app and CI:<br>• a signing key in Secrets Manager, placed by Ansible;<br>• a public S3 issuer;<br>• no webhook.<br>The controllers use the node role | EKS Pod Identity, one role per controller. The app holds no AWS identity at all | Medical: "no IRSA or Pod Identity out of the box" on a self-managed cluster, so it built IRSA by hand, first for the one pod reachable from the internet. It skipped the upstream webhook because it "quietly falls back to the node role" when down.<br>Anime gets Pod Identity from EKS. Its app needs no AWS rights: secrets arrive as Kubernetes Secrets, and the index is in the image |
| Secrets | Created empty; values typed with the CLI; nodes read 8 named secrets, never a wildcard | Created empty; values typed with the CLI; External Secrets reads 3 named secrets | Same rule: a wildcard would include keys a cluster must never read. In Anime, that is the VPN gateway's keys ([1-terraform, Decision 4](../1-terraform/README.md#decision-4--six-identities-and-none-of-them-is-a-key)); in Medical, also the service-account signing key (`sa-signer`) |
| The instance metadata service | Calico NetworkPolicy blocks `169.254.169.254` in four namespaces, because every pod could otherwise borrow the node role | IMDSv2 with a hop limit of 1 keeps ordinary pods off the node role; no NetworkPolicy yet | Medical's platform pods need the node role, so its hop limit stays at 2 and the fence is the policy: "the hop limit is not the fence" (`docs/app/README.md`). Anime's pods get rights from Pod Identity and need no metadata access, so the hop limit alone does the job ([1-terraform, Decision 4](../1-terraform/README.md#decision-4--six-identities-and-none-of-them-is-a-key)) |
| DNS | Terraform writes all 9 records, the aliases included | Terraform writes `vpn.anime` and the ACM validation record; external-dns writes the six load-balancer names | Anime's load balancers do not exist when Terraform runs ([2-gitops, Decision 4](../2-gitops/README.md#decision-4--the-names-follow-the-objects)) |
| Time to build the cluster stack | `make infra` 3 m 47 s at 84 resources, then `make cluster` (Ansible) 6 m 10 s | `make infra` 12 m 18 s at 92 resources | Anime's apply includes the EKS control plane, which Medical builds afterwards with Ansible. How the 12 m 18 s splits between resources is not measured |

**What Anime took from Medical:**
- stacks split by lifetime;
- the S3 state bucket with its native lockfile;
- the ops workstation, so nothing is installed on the laptop;
- secrets created empty, with values typed outside Terraform;
- secret access scoped by name, not by pattern;
- `m7i-flex.large`, which Medical found by being refused `t3.large` on the Free plan.

**Where each tripped:**
- **Medical:**
  - CloudShell ran out of disk;
  - the Free plan refused two instance types;
  - the default VPC had no subnets;
  - the gateway failed at boot, most likely because its secret was still empty (`docs/evidence/terraform.md`).
- **Anime:** the apply itself was clean, with every count matching ([evidence](../evidence/terraform.md)), but
  three things tripped around it:
  - the account check, run before stage 1, found all four instance types it had planned ineligible
    ([account check](../evidence/account.md));
  - `make down` failed with `NoSuchHostedZone: None`, because the JMESPath filter that looks for leftover DNS
    records read `!Config.PrivateZone` as `(!Config).PrivateZone` (fixed in the `Makefile`, commit `e8740b4`);
  - a saved plan file outlived the state it was planned against, so `make infra` refused it as stale. The
    plan file is local; the state is in S3. Re-running `make plan` is the fix.

## The application

Both began from an existing app with known defects, and both closed them before any infrastructure existed
(each design's §2). The apps differ,
so the fixes differ.

| Decision | Medical | Anime | Why they differ |
|---|---|---|---|
| Shape | One Flask app, moved to gunicorn with 2 workers | Split into two images: a FastAPI **api** and a Streamlit **ui** | Different starting defects.<br>• **Medical:** the Flask development server ran in production, and the only health check was `/`.<br>• **Anime:** everything was one Streamlit process, so there was "no HTTP status code to count and no request to replay: no SLI, no load test" (design §2). Anime's later stages all measure the api, so the split came first |
| The search index | FAISS, 7,079 chunks, built by a Kubernetes Job in 149 s. Stored in S3 under a version hash, pinned in Git, pulled by an init container | Chroma, 269 documents, **built during the image build**, with the count asserted in CI | **Medical:** rebuilding at every start was slow and "costs HF API quota", so the index became a versioned artifact.<br>**Anime:** the index is small, and the defect found was different: "a clean build ships an **empty** index and nothing complains". Building it into the image puts it under the same digest, and the same signature, as the code |
| Environments | `dev` and `prod`, two namespaces; prod changes only by pull request | One namespace, with a canary instead of a dev environment | By the split. Anime's design: "The canary replaces a dev environment: a change is proven on real traffic in small slices instead of on synthetic traffic in a copy of production" |
| TLS for the app | None: HTTP only | HTTPS only, ACM | Medical's design lists app TLS as a non-goal without a reason, and its app README accepts the risk as "out of scope in the design; the internal UIs use TLS". Anime's certificate costs nothing to run, since AWS renews it |
| Health endpoints | `/healthz` and `/readyz`, readiness after the index loads | The same, plus: readiness requires the index count to match, and the handlers are `async` | Anime's autoscaler reads `/metrics` while the api is saturated. A synchronous scrape would "queue behind forty busy threads" just when KEDA needs the number (design §4.1) |
| How pods are scraped | Service-based, with metrics summed across gunicorn workers | A **PodMonitor**, copying the Rollout's hash label onto every series | From stage 5 three Services select the same api pods. A ServiceMonitor would scrape each pod once per Service, and the canary analysis filters on the hash (design §4.1) |
| Graceful shutdown | `preStop` 5 s, grace 45 s | `preStop` 15 s, deregistration delay 30 s, grace 45 s | Anime's ALB sends traffic straight to pod IPs, so a pod must stay alive while the load balancer deregisters it ([2-gitops, 4](../2-gitops/guide.md#4-five-ingresses-two-load-balancers-and-the-readiness-gates--ops)) |

## GitOps

Both use Argo CD with an app-of-apps and sync waves. The shape of the root, and how Argo CD itself is
installed, differ.

| Decision | Medical | Anime | Why they differ |
|---|---|---|---|
| Installing Argo CD | `make bootstrap` runs Helm once. An `argocd` Application then adopts the release, so Argo CD manages itself (`prune: false`) | A Terraform stack (`bootstrap`) installs Argo CD and the root, through the tunnel. Argo CD does not manage itself | Not the tunnel: both clusters' APIs are reachable only through one, and both install Argo CD after it opens ("Medical splits the same way for the same reason", design §3). Why Anime uses a Terraform stack where Medical runs Helm from the Makefile is not written down. Whether Anime's Argo CD should also upgrade itself from Git "is still open" ([2-gitops, Decision 5](../2-gitops/README.md#decision-5--admin-uis-a-public-name-a-private-address)). Medical's self-management cost it a Helm server-side-apply conflict on the second bootstrap (`docs/evidence/gitops.md`) |
| The root | `root.yaml` creates one Application per file in `apps/`: nine in the GitOps phase, 16 now | The root is a small **Helm chart**. It renders only the stages listed in `enabled_stages` | **Anime:** all stages were written before any ran, and the cluster is built one stage at a time. So the whole repository is in Git from the start, and switching a stage on is a change to `terraform.tfvars`, not a commit.<br>**Medical:** it adds a file to `apps/` as each phase is written. It chose plain files over a template because its components differ in wave, finalizer, prune and sync options, and plain files are easier to review (`docs/gitops/answers.md` A1.6) |
| The health check that makes waves wait | Healthy **and** Synced, learned from a real rebuild | The same check, in the bootstrap values from the start | Carried over. On Medical's rebuild of 2026-09-18, a health-only check let every wave start at once. cert-manager then ordered a new certificate before the backup had been restored |
| Ingress | ingress-nginx on fixed NodePorts, `externalTrafficPolicy: Local` | The AWS Load Balancer Controller, one IngressGroup for the four UIs | See the [overview, section 5](compare-to-medical-rag-chatbot.md#5-why-medical-uses-nlbs-and-anime-uses-albs) |
| Certificates | cert-manager and a Let's Encrypt wildcard, backed up to Secrets Manager and restored on every rebuild. The backup is seeded with an invalid placeholder. Rancher uses a bought Sectigo certificate | One ACM certificate, nothing in the cluster | Let's Encrypt allows 5 certificates per name set per week, and Medical is rebuilt more often than that, so it needs the backup. Anime lists "certificates issued or renewed by anything we operate" as a non-goal precisely so "that burden does not exist here" (design §1) |
| Private admin UIs | Three layers: names resolve to private addresses; the gateway forwards only 443; ingress-nginx allows only the VPC | The same first two layers; the third is the internal ALB's security group | Same design, and each is enforced where that cluster can enforce it |
| External Secrets' AWS rights | The node role, 8 named secrets | Pod Identity, 3 named secrets | Pod Identity comes with EKS. Medical gave its own IRSA roles to the app, the index builder and the CI build pods, but left the platform pods on the node role: "They are not internet-facing, and each permission names its resources" (`docs/app/README.md`) |
| Monitoring | Retention 24 h, with volumes; scrapes the control plane and etcd; alerts by email (SMTP); a custom CPU alert | Retention 2 d, **no volume**; control-plane targets off; alerts to Discord from stage 6 | **Anime's volume:** "the cluster lives hours and every teardown destroys metrics anyway", and a volume would pin Prometheus to one zone, "and after a Spot reclaim it could stay Pending" (`gitops-monitoring.yaml`).<br>**Control-plane targets:** EKS has none that can be scraped the kubeadm way.<br>**Medical's CPU alert:** its `m7i-flex` nodes publish no CPU-credit metric |
| A cluster UI | Rancher, behind the VPN | None | Part of Medical's cluster-operations story. Anime's documents give no reason for leaving it out |
| Teardown | Delete the Applications that own volumes, then the claims, then wait for the volumes to go | Delete every Ingress, wait for both ALBs and for external-dns to remove its records, then the claims; discard the bootstrap state | Each deletes what Terraform cannot see. In Medical that is the EBS volumes. In Anime it is the volumes, the load balancers and the DNS records in Medical's zone, plus a state file describing a cluster that will no longer exist |

**Where each tripped:**
- **Medical:**
  - the wave collapse above;
  - a restore that deadlocked its own wave;
  - a staging certificate committed on a live cluster;
  - a cached `ComparisonError` from a typo (`docs/evidence/gitops.md`).
- **Anime, on its first run:**
  - a YAML syntax error in the root chart (`805c9a2`);
  - the load balancer controller's webhook CA not matching its Secret (`9f05258`), fixed by one manual sync of
    that Application and a restart of its pods
    ([troubleshooting](../2-gitops/guide.md#troubleshooting)).

## CI

Both build, scan, attach an SBOM, sign, and hand off to Argo CD by committing a digest. Where the pipeline runs,
and how it signs, differ, mostly *by the split*.

| Decision | Medical | Anime | Why they differ |
|---|---|---|---|
| Where CI runs | Jenkins **inside the cluster**, configured entirely in Git (JCasC), installed by Argo CD | GitHub Actions, hosted runners | By the split. Medical's own answer (`docs/jenkins/answers.md` A2.2): a self-managed project runs its CI too, and at a company GitHub Actions with OIDC would be simpler. Later in the same file, it adds that most of the effort went into running Jenkins rather than the pipeline |
| What starts a build | Polling every 2 minutes | A push or a pull request | Jenkins is reachable only through the VPN, so GitHub cannot call it |
| Building images | Rootless BuildKit in an agent pod | Docker Buildx (`docker/build-push-action`) on the runner | Inside a cluster, the docker socket "gives the build the node", Docker-in-Docker needs a privileged pod, and Kaniko was archived upstream. A hosted runner is disposable, so the question does not arise |
| AWS rights | IRSA role `medical-rag-ci` for the agent's ServiceAccount; push, sign and read the corpus | A role assumed through GitHub OIDC, trusted for one repository **and one branch**; push only | Each uses its platform's keyless federation. Anime's trust names the branch, so a workflow on any other branch cannot push |
| Tests | The Dockerfile's `test` target, built in a BuildKit agent pod before any credential exists | The Dockerfile's `test` target too (`lint-test`, on the hosted runner), plus the index count assertion and the `index-negative` workflow | Both run the tests inside the Dockerfile, so tests run the same way locally and in CI. The index checks differ with the index designs. Medical checks that the Git corpus matches S3 before writing a version. Anime asserts the count baked into the image, and proves that check can fail by truncating the data (criterion #5) |
| Scan gate | Trivy; fail on any fixable CRITICAL | Trivy; fail on any fixable CRITICAL (the severity can be lowered for a manual run) | Same idea, and the same caveat: a gate that ignores unfixable findings may never fail. Medical proved its gate in the drills phase; Anime runs a deliberate positive control ([3-cicd, Decision 2](../3-cicd/README.md#decision-2--every-check-must-be-able-to-say-no)) |
| SBOM | From Trivy, in SPDX | From the Anchore SBOM action, in SPDX | Medical: "one container fewer". Anime's documents give no reason for its choice |
| Signing | cosign with a **KMS key**, no transparency log | cosign **keyless**, recorded in Sigstore's public log (Rekor) | By the split, and by privacy. Medical's images are private, "so their digests, repository name and account id have no business" in a public log. Anime's repository is already public, and the log is what lets anyone verify without a key |
| Deploying | A bot commit updates dev; for prod, the bot opens a pull request that a person merges | A bot commit updates the digest on `main`; the canary does the judging | By the split: two environments against one environment with a canary |
| Stopping the bot's commit from triggering another build | A skip guard on the author and the changed paths | `[skip ci]` in the commit message | The same problem: a pipeline that commits must not start itself. Anime's bot pushes with a deploy key, the ruleset's only bypass, and that push **does** start a run, so `[skip ci]` is the guard (`ci.yml`, release-commit) |
| Checking signatures at deploy time | Kyverno refuses unsigned images in prod | Nothing; checked once, by hand, for criterion #3 | Medical's drills phase closes this gap. For Anime it is a stated non-goal, "left open deliberately and written down" (design §4.6) |

**Where each tripped:**
- **Medical** recorded 23 defects, all but one in its guide. Among them:
  - Jenkins plugin versions out of step, which cost four builds;
  - an ECR token printed into a build log.
- **Anime** recorded one defect ([evidence](../evidence/cicd.md)): the first release run failed at *AWS
  credentials (OIDC, no key)* with `Could not load credentials from any providers`, which the action prints
  when `role-to-assume` is empty — the repository variable `AWS_CI_ROLE_ARN` was missing. The failure came
  before the push, so ECR and Git were untouched, and a later release passed. Criteria #3, #4 and #5 are
  closed; the pipeline's own duration is still pending.

---

## Only in Medical

**Ansible.** Anime has no machines to configure. Every job Medical's playbooks do is done by EKS or the managed
node group:

| Medical's Ansible does this | In Anime it is done by |
|---|---|
| Kernel modules and swap, containerd and kubelet installed and pinned | The EKS node image the managed node group launches |
| `kubeadm init` and `join`, the HA control plane | EKS itself |
| Calico, in VXLAN mode | The VPC CNI add-on |
| `ecr-credential-provider` | Already on the node image |
| `upgrade.yml`, one node at a time | EKS upgrades the control plane; the node group rolls its own nodes |

**Drills: etcd restore, Kyverno, upgrade.** Medical's drills test the **cluster**.
- **etcd restore:** Anime has no etcd to restore. Its recovery path is a rebuild from Git, to be timed as
  [M8](../evidence/guide-measurements.md#m8--a-timed-rebuild) (not yet run). Medical has timed such a rebuild:
  21 m 47 s for 17 Applications.
- **Kyverno:** Anime's design lists "Kyverno or etcd operations" as a non-goal: "Those belong to Medical, which
  has an etcd to operate".
- **Upgrade:** AWS upgrades Anime's control plane. Upgrading the node group and the add-ons stays Anime's job,
  but it plans no upgrade drill, and gives no reason.

Anime's drills test the **service** instead: a bad release rolling itself back (stage 5), and an alert reaching
a person (stage 6).

## Only in Anime

All five exist because of the split. Medical's design lists canary releases and SLO alerting as non-goals
belonging to Anime, and names autoscaling and LLM observability as Anime's focus. Each also depends on
something Medical does not have.

- **4 · Load.** It measures two numbers: T, the latency target of the SLO, and the knee, which sets the
  autoscaler's threshold. Medical has neither an SLO nor an autoscaler, so it needs neither number. Its app
  phase sized pod resources from Prometheus data instead (`docs/evidence/app.md`).
- **5 · Delivery.** Medical promotes dev → prod by a pull request that a person merges. Anime replaces that with
  a canary that judges itself. The canary also needs something Medical's ingress path does not offer as built:
  the ALB's weighted target groups, driven by Argo Rollouts
  ([overview, section 5](compare-to-medical-rag-chatbot.md#5-why-medical-uses-nlbs-and-anime-uses-albs)).
- **6 · SLO.** Medical alerts on causes (the chart's default rules, plus a CPU alert) and sends email. Anime
  alerts only on what users feel, as burn rates of an error budget, and sends to Discord.
- **7 · Scaling.** Medical's documents never discuss autoscaling. The only written reason is the split, which
  names autoscaling as Anime's focus. For context: Medical's three nodes are also its control plane, and their
  number was set by the etcd quorum. Anime's nodes carry only workloads. A Cluster Autoscaler adds and removes
  them, and KEDA scales pods on in-flight requests.
- **8 · Tracing.** LLM observability is Anime's half of the split. Medical exposes Prometheus metrics, and has no
  traces, no token accounting and no cost per request.
