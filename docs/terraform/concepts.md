# Stage 1 — Concepts

Every idea [`README.md`](README.md) relies on, defined once, in the order the README first needs it. Each
section answers three things: **what it is**, **how it runs here**, and **what breaks without it**. Numbers and
resource names live in the [design](../eks-sre-llmops-design.md#3-architecture); this page is about what they
mean.

---

## 1. State, configurations and a blast radius

**What it is.** Terraform keeps a *state* file that maps each resource in the code to the real object it
created. A *configuration* is one directory of code plus its own state. `terraform destroy` acts on exactly
one configuration's state — no more, no less.

**How it runs here.** Three configurations — `shared`, `cluster`, `bootstrap` — each with its own state, all
stored under one prefix in one bucket, with S3's own locking so two applies cannot write the same state at
once. `cluster` reads values from `shared` through data sources; it never writes them.

**Why that makes it a blast radius.** Everything sharing a state file shares a lifetime, because one
`destroy` reaches all of it. So dividing configurations is a decision about *time*: what must survive a
teardown, and what is meant to die with it. A configuration boundary is also a safety boundary — a command
can only destroy what its state knows about.

**What breaks without it.** With one state, the nightly teardown takes the registry, the secrets and the
certificate with it. Images vanish, so nothing can start until CI rebuilds them; the certificate is re-issued
instead of renewed; and `make down` becomes a command you have to be brave to type.

---

## 2. Providers, and why apply order is not optional

**What it is.** A *provider* is the plugin Terraform uses to talk to one API — AWS, Kubernetes, Helm. Each is
configured with an address and credentials. Terraform works out the order of *resources* from references
between them, but it cannot reason about whether a *provider's* address is reachable.

**How it runs here.** `shared` and `cluster` use only the AWS provider, which talks to AWS's public service
endpoints and always works. `bootstrap` uses the `helm` and `kubernetes` providers, which talk to the cluster's
API server — at `127.0.0.1:6443`, the local end of the tunnel.

**Why the order is forced.** The tunnel ends at a gateway `cluster` creates. So `bootstrap` can only run after
`cluster` has finished *and* the tunnel is open. Putting everything in one configuration would ask a provider
to connect to an address that does not answer yet.

**What breaks without it.** The characteristic failure is a plan that succeeds and an apply that fails
halfway, because the plan never had to connect and the apply did. The state is then left describing half of
what was intended — the worst kind of partial success, because it looks like progress.

---

## 3. Refresh, drift and a saved plan

**What it is.** Before planning, Terraform normally *refreshes*: it asks the real APIs what each resource
looks like now. *Drift* is any difference between that and the state — something changed outside Terraform. A
*saved plan* is a plan written to a file and applied later.

**How it runs here.** Criterion #1 is "apply, then plan, and see no changes". That sentence means something
only if the second plan refreshed, against the right configuration, and was compared against a resource count
written down in advance.

**What breaks without it.** `plan -refresh=false` skips comparing managed resources with reality — it still reads
data sources, so it does talk to AWS — and reports "no changes" regardless of drift. Re-reading a saved plan
reports what was true when it was saved. Neither is lying about what it did; both answer a different question
from the one being asked. That is the most common way a check passes while the thing it guards is broken — and
why the criterion names the refresh and the count, not just the verdict.

---

## 4. A managed control plane

**What it is.** A Kubernetes control plane is the API server, etcd, the scheduler and the controller manager.
On EKS, AWS runs all four. You cannot log in to those machines and you do not patch them.

**How it runs here.** The version is pinned exactly, to one still in standard support, so an upgrade is
something you decide to do rather than something that happens to you.

**What you give up.** Direct access to etcd — there is no snapshot to take — and control over the API
server's certificate. The second one reaches into this stage: a tunnelled `kubectl` needs the certificate to
match the name it connects to, and a managed certificate cannot be reissued to include `127.0.0.1`.

**What it would take without it.** Everything Medical spends its effort on: three API servers, an etcd quorum,
certificate rotation, upgrades one node at a time. Handing that away is the reason this project exists beside
that one — the subject moves from *keeping Kubernetes alive* to *running a service well on it*.

---

## 5. Public and private endpoints, and the name on the certificate

**What it is.** The API server is an HTTPS endpoint. EKS can give it a public address, a private address
inside the VPC, or both. By default it is public and open to everyone; a list of allowed addresses is an
extra, optional step.

**How it runs here.** Public access is off. The private endpoint exists from the moment the cluster does, but
nothing outside the VPC can reach it except through the tunnel.

**The name on the certificate.** A TLS client checks two things: the certificate chains to a trusted
authority, and one of the names it lists — its *SAN list* — matches the name the client meant to reach. The
client also sends that name at the start of the connection (*SNI*). Tunnelling breaks the match: `kubectl`
connects to `127.0.0.1`, while the certificate names the real endpoint. `tls-server-name` in the kubeconfig
tells the client which name to send and to verify, independent of the address it dials.

**What breaks without it.** With a public endpoint behind an allowlist, nothing breaks immediately — which is
the problem. The day the list is wrong, `kubectl` hangs and times out, the same symptom as a cluster that is
down. Without `tls-server-name`, every tunnelled command fails with a certificate-name error, again reading
like an outage. Both are symptoms that point away from their cause.

---

## 6. Spot capacity and the disruption budget

**What it is.** Spot is spare EC2 capacity at a large discount, which AWS can take back with a two-minute
**interruption notice**. It may also send an earlier, softer *rebalance recommendation* when an instance is at
elevated risk.

**How it runs here.** The managed node group acts on the rebalance recommendation: it launches a replacement,
then cordons and drains the old node. If the interruption notice arrives first, draining starts then and is
best-effort inside the two minutes. Several instance types across two zones keep one shortage from emptying
the group.

**The disruption budget.** A *PodDisruptionBudget* tells Kubernetes how many of a set of pods must stay
available during **voluntary** evictions — a drain is the usual one. Here it keeps at least one API replica
running while a node is drained. It says nothing about involuntary loss: when AWS reclaims the instance, the
pods on it are gone whatever the budget says. What survives a reclaim is the *spread* — replicas on different
nodes.

**What breaks without it.** A single replica on Spot has an availability ceiling set by somebody else's
capacity. An SLO measured on it measures AWS, not the code. And any analysis that averages over a window has
to be able to say "a node went away" — or it will blame the release.

---

## 7. Workload identity: Pod Identity, IRSA and the node role

**What it is.** Three ways a pod can get AWS permissions without a stored key:

- **The node's instance role** — every pod on a node can, in principle, use the node's permissions.
- **IRSA** — the cluster publishes an OIDC issuer; each role trusts tokens for one exact
  `namespace:serviceaccount`; the pod exchanges its ServiceAccount token for that role.
- **EKS Pod Identity** — an agent on the node hands a pod its role's credentials; the association between a
  ServiceAccount and a role is an EKS API object.

**How it runs here.** Pod Identity, one association per controller. Ordinary pods cannot fall back to the node's
role: IMDSv2 with a hop limit of 1 means the metadata service answers the node, not a container behind it. Pods on
the host network are the exception — the VPC CNI is one, and it uses the node's role for its own network rights.

**How it compares.** Medical builds IRSA by hand — a self-hosted issuer and one role per workload — because a
kubeadm cluster has no managed issuer. It works, and it is a lot of machinery. Pod Identity does the same job
with no issuer to host: every role carries the same trust policy for `pods.eks.amazonaws.com`, independent of
any cluster, and the per-workload binding moves into the association. The difference is where the binding
lives and how much there is to get wrong, not what is possible.

**What breaks without any of them.** Either a key sitting in a Secret, or every pod borrowing the node's
permissions — so any compromised pod inherits everything on its node.

---

## 8. OIDC federation for CI

**What it is.** GitHub Actions can request a short-lived token describing the running workflow: the
repository, the branch, the event. AWS can be told to trust that issuer and exchange a matching token for a
role.

**How it runs here.** The trust names one repository **and** one branch, and the role may push images to this
project's registry and nothing else.

**The trap.** A trust condition that names the repository but not the branch is satisfied by any workflow run
on any branch of it — including branches the maintainer did not write. The branch is not a detail; it is the
difference between "our release pipeline" and "anything that runs in our repository".

**What breaks without it.** An access key stored as a GitHub secret: it does not expire, anyone who can edit a
workflow can print it, and revoking it depends on somebody remembering it exists.

---

## 9. ACM, and what renewal depends on

**What it is.** AWS's certificate service. It issues a certificate after proving control of the name, renews
it before expiry, and with default issuance never lets the private key leave AWS.

**How it runs here.** One certificate, created once in `shared`, validated by a DNS record in the zone.

**What proving control means.** ACM checks a `_<token>` CNAME record it asked you to create, and consults the
zone's CAA records to confirm Amazon is allowed to issue for the name. It does not look at the name's A
record, so it does not care what address the name resolves to.

**What renewal depends on.** The validation record must still be there when renewal runs, months later —
delete it and the certificate is fine today and fails to renew next year, long after anyone remembers why.
Whether renewal also requires the certificate to be *in use* by a load balancer at that moment has not been
verified; on a stack torn down nightly, it often is not. The design records that as an open risk rather than
assuming it away.

**What breaks without it.** A certificate issued by something we operate has to be renewed by something we
operate, and stored somewhere between rebuilds. ACM moves both jobs to AWS — but only if the certificate lives
in the configuration that is never destroyed.

---

## 10. WireGuard and SSM port forwarding

**What it is.** *WireGuard* is a VPN: each side holds a keypair, and packets that do not authenticate are
dropped without a reply, so a scan sees nothing. *SSM Session Manager* opens a session to an instance through
a connection the instance makes outward — no inbound port, no SSH key. Its port-forwarding mode relays a local
port to a host the instance can reach.

**How they combine here.** One gateway instance does both. As a VPN it puts a laptop inside the VPC. As an SSM
target it relays the workstation's local port to the private API endpoint — `make tunnel`.

**Whose agent does the forwarding.** The SSM agent **on the gateway** opens the connection to the API server.
So the gateway is what must resolve the private endpoint and be allowed through the cluster's security group.
The workstation only holds the local end of the pipe.

**Key handling.** The gateway's own keys live in a secret that only the gateway's role can read. Each operator
generates their own keypair, keeps the private half on their own machine, and hands over only the public half.
A private key that has travelled is no longer private.

**What breaks without the gateway.** The service keeps serving — the gateway is not in the request path — but
every admin UI and every `kubectl` go at once. A rebuild also gives the gateway a **new Elastic IP**. Profiles
name the gateway rather than its address, so they follow the new record — but a laptop whose resolver cached the
old address fails its handshake silently until the cache expires, which reads like a firewall problem.

---

[README](README.md) · [Design §3](../eks-sre-llmops-design.md#3-architecture) ·
[Design §4.7](../eks-sre-llmops-design.md#47-names-tls-and-the-two-ways-in)
