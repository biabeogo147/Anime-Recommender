# Stage 2 — Concepts

Every idea [`README.md`](README.md) relies on, defined once, in the order the README first needs it. Each
section answers **what it is**, **how it runs here**, and **what breaks without it**. Versions, annotations and
rules are in the [design](../eks-sre-llmops-design.md#47-names-tls-and-the-two-ways-in).

---

## 1. GitOps, pull not push, and the app-of-apps

**What it is.** GitOps means the desired state of the cluster is a directory in Git, and a controller inside
the cluster keeps pulling it and making the cluster match. *Push* deployment is the opposite: a pipeline
outside holds credentials and applies changes itself. The *app-of-apps* pattern is one root Application whose
only job is to create the other Applications.

**How it runs here.** Argo CD and a root Application are installed once by the bootstrap configuration. From
then on every component is a file in Git, and CI's last act is a commit, not a deployment.

**What breaks without it.** CI would need credentials to an API server that has no public address, and the
cluster's state would be whatever the last successful pipeline left. Nobody could answer "what is running" by
reading anything, or put it back after a teardown.

---

## 2. Custom resources and their definitions

**What it is.** Kubernetes can be taught new kinds of object. A *CustomResourceDefinition* (CRD) teaches it
one — `Rollout`, `ScaledObject`, `ExternalSecret`. Until the CRD exists, the API server rejects any object of
that kind as unknown. Controllers usually install their own CRDs.

**How it runs here.** The ExternalSecrets and the monitoring objects are custom kinds from this stage on; the
app's Rollout and ScaledObject join them in stages 5 and 7. Each controller's CRDs have to be in place before
anything written in that kind arrives.

**What breaks without the ordering.** The app's Application fails to sync with "no matches for kind". It
usually recovers on a later retry, once the CRD lands — which is exactly why the bug survives: a rebuild
that *usually* converges hides the ordering problem until the day the retries run out.

---

## 3. Sync waves, and the health check that makes them wait

**What it is.** A *sync wave* is a number on an object. Within one sync, Argo CD applies lower waves first and
waits for everything in a wave to be healthy before starting the next.

**How it runs here.** The waves are on the child Applications, inside the root's sync. So "healthy" means
*the child Application is healthy* — and since Argo CD 1.8 there is no built-in check for that kind. The
bootstrap values add one to Argo CD's configuration, in the form Medical's ended up with: a child is healthy only
when it is both *Healthy* and *Synced*. Health alone is not enough, because Argo CD leaves resources that do not
exist yet out of an Application's health — a child that has applied half its manifests still reads Healthy.

**What breaks without the health check.** Every child counts as healthy the moment it is created. The root
starts every wave at once, the numbers become decoration, and the cluster converges only through retries.
Nothing reports an error, because nothing is technically wrong with any single object.

---

## 4. What Healthy means to Argo CD

**What it is.** Argo CD reports two things per Application: *Synced* — the cluster matches Git — and
*Healthy* — the objects are working. Health comes from built-in checks for common kinds and from custom ones
you add.

**How it runs here.** Several kinds this project depends on have no meaningful built-in check, and for those
Argo CD reports `Healthy` unconditionally. *Synced* also has a narrower meaning than it sounds: synced to the
revision Argo CD has *fetched*, which can be behind `main`.

**What breaks without knowing it.** "Every Application is Healthy and Synced" becomes a sentence that can be
true of a cluster where half the objects do nothing and the rest run yesterday's commit — and it is also true
of an empty list. A check worth running names the Applications, counts them, compares each one's revision with
`main`, and reads a real readiness field for each custom kind.

---

## 5. The AWS Load Balancer Controller, and IngressGroups

**What it is.** A controller that watches Ingress objects and builds AWS load balancers from them. By default
each Ingress gets its own ALB; Ingresses that share a *group name* are merged into one ALB, even across
namespaces. An Ingress's *scheme* decides whether its ALB is internet-facing or internal.

**How it runs here.** One public Ingress, and four internal ones in one group — five objects, two load
balancers. It finds subnets by tag: one tag marks public subnets, another private ones. From stage 5 it also
applies the traffic weights that Argo Rollouts decides.

**What breaks without it.** EKS has no built-in way to turn an Ingress into a load balancer; the object is
accepted and sits there looking fine. Without the group, the internal side would become four load balancers,
four sets of costs and four things for the teardown to find. Without the subnet tags, one scheme fails while
the other works, which reads like a problem with the Ingress rather than the network.

---

## 6. Target type, health checks and readiness gates

**What it is.** A target group registers either *instances* — nodes, reached through a node port — or
*IPs* — pods, reached directly. The load balancer health-checks each target on a path. A *readiness gate* is
an extra condition on a pod: the load balancer controller holds the pod not-Ready until its target is healthy.

**How it runs here.** IP targets, explicit health-check paths for both apps, and readiness gates on the app's
namespace.

**Why readiness gates matter so much.** When every target in a group fails its health check, an ALB **fails
open**: it sends traffic to all of them anyway. So a wrong health-check path is invisible — users are served,
nothing alarms, and "health" means nothing. With readiness gates the same mistake keeps new pods from ever
becoming Ready, and the rollout stops on the first deploy. The failure is the same; readiness gates change it
from silent to loud.

**What breaks without IP targets.** Not the split itself — two Services with different selectors still map to
two node ports. What is lost is the direct path: a node port can forward to a pod on another node, including,
in some configurations, a pod of the other version. And readiness gates need IP targets to mean anything.

---

## 7. TLS at the edge

**What it is.** *TLS termination* is where the encrypted connection ends and plain traffic begins. At the edge
means at the load balancer, rather than at a controller or pod inside the cluster.

**How it runs here.** Both load balancers serve one ACM certificate, named explicitly on every Ingress. The
public load balancer's port 80 answers only with a 301; the client then reconnects to 443 itself.

**Why name the certificate.** Left unnamed, the controller chooses a certificate by matching the Ingress hosts
against every ACM certificate in the account. An account holding another project's certificates can offer a
match nobody intended — and the chain still verifies.

**What breaks without it.** Nothing that can be terminated in the cluster can be served by an ALB, and nothing
at the ALB can come from a Kubernetes Secret. Terminating inside the cluster means a different front door —
an NLB and an ingress controller — and brings back the certificate backup that ACM was chosen to avoid.

---

## 8. External Secrets

**What it is.** A controller that reads values from an external store and writes them into Kubernetes Secrets.
An *ExternalSecret* in Git names what to fetch and what to call the result; a *store* object says where to
fetch from and how to authenticate.

**How it runs here.** One store, authenticated with the controller's own identity
([stage 1 concepts §7](../terraform/concepts.md#7-workload-identity-pod-identity-irsa-and-the-node-role)),
allowed to read three named secrets. Git holds ExternalSecret objects — names and keys, never values.

**Why names and not a pattern.** A policy on `anime/*` would also cover every secret anyone later adds under
that prefix, including the VPN gateway's keys. With named scopes a new secret is unreadable until someone
decides it should be readable — the safe direction to fail.

**What breaks without it.** Values end up in Git, in chart values or in Terraform state — each a place where a
value is hard to rotate and easy to leak.

---

## 9. Alias records and external-dns

**What it is.** An *alias record* is Route 53's way of pointing a name at an AWS resource such as a load
balancer; it needs that resource's DNS name and zone id when it is written. *external-dns* is a controller
that watches Ingresses and writes records for their hosts. It marks every record it owns with an accompanying
TXT record, and only ever changes records it owns.

**How it runs here.** It publishes the two public names and the four admin names. A filter limits it to names
under `anime.recruitai.io.vn`, and separately its identity can only change records under that prefix — in a
zone that belongs to another project.

**Why two limits.** The filter is configuration and can be wrong; the permission is what still holds when it
is. Two safeguards that fail independently are the point.

**What breaks without it.** Terraform runs before any load balancer exists, so it cannot write these aliases.
The records would need a manual step after every rebuild — or would point at yesterday's load balancers.

---

## 10. A public name for a private address

**What it is.** A record in a public zone whose value is a private address. The name resolves for nearly
anyone; the address cannot be routed to from the internet, so only a client inside the network can connect.

**How it runs here.** The four admin names point at the internal load balancer. A laptop reaches it over
WireGuard: its profile gives it an address in a small client range, and routes only the VPC's range through
the tunnel. The gateway forwards packets between the tunnel and the VPC, and rewrites their source to its own
address so replies know the way back.

**What breaks without the public record.** A private zone answers only clients using the VPC's resolver, so
every VPN profile would need a DNS setting kept correct forever.

**What breaks at the gateway.** Without forwarding, packets from the tunnel are dropped at the gateway and never
reach the VPC. With forwarding but without the source rewrite, requests arrive and replies have no route back
to the client range. Both look, from the browser, like the app is down.

**Where it does not work.** Some resolvers — many home routers among them — discard public answers that
contain private addresses, as protection against DNS rebinding. On such a network the name simply does not
resolve, VPN or not.

---

## 11. Telling an app its own name

**What it is.** Web applications build absolute links and redirects from the name and scheme they think they
are served on. Behind a load balancer that ends TLS, an app sees plain HTTP from an internal address, so it
has to be told its public name.

**How it runs here.** Each admin UI gets its external URL through its own setting — Argo CD's `url`, Grafana's
root URL, the external URL flag of Prometheus and Alertmanager — and Argo CD is additionally told to stop
redirecting plain HTTP to HTTPS itself, since the load balancer already did.

**What breaks without it.** Redirect loops, links to `http://localhost`, logins that return to the wrong page.
Every one of them is invisible through a port-forward and appears the first time the UI has a hostname.

---

[README](README.md) · [Design §3](../eks-sre-llmops-design.md#3-architecture) ·
[Design §4.7](../eks-sre-llmops-design.md#47-names-tls-and-the-two-ways-in)
