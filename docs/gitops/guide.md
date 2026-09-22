# Stage 2 — Guide: Argo CD builds the two doors

Commands and checks only; the reasoning is in the comments of `deploy/argocd/root/**`, `deploy/platform/base/*` and
`deploy/charts/**`, and in [README](README.md) · [concepts](concepts.md).

Same conventions as [stage 1](../terraform/guide.md): **laptop** = Windows PowerShell + git + browser + WireGuard;
**ops** = the workstation, inside `tmux new -A -s anime`, every block starting with
`cd ~/Anime-Recommender && export KUBECONFIG=$HOME/.kube/anime`. AWS commands use the workstation's default region,
`ap-southeast-1`.

Criteria closed by this stage ([design §6](../eks-sre-llmops-design.md#6-verification-and-evidence-definition-of-done)):
**#2** every Application Synced and Healthy, checked by name · **#15** HTTPS on both public names with the intended
certificate · **#16** the four admin names answer only through the VPN.

How stages are switched on: the root Application is a small chart (`deploy/argocd/root`) that renders a stage's
Applications only when the stage is listed in `enabled_stages` in `infra/terraform/bootstrap/terraform.tfvars`. Pushing
code deploys nothing by itself; this stage adds `gitops` to that list.

---

## 0. Before you start — ops

Stage 1 passed: the tunnel is open, `make ready` prints `ok`, and `root` is `Synced Healthy` with no children.
`anime/llm` holds `GOOGLE_API_KEY` and `HF_TOKEN` (stage 1, 2.5). Tools this stage adds:

```bash
cd ~/Anime-Recommender && export KUBECONFIG=$HOME/.kube/anime
docker buildx version && which dig openssl curl && groups | grep -qw docker && echo "tools ok"
```

Expected: a buildx version and `tools ok`. `dig` missing: `sudo apt-get install -y bind9-dnsutils` (on ops).

---

## 1. Pins — the values only this account knows

Fourteen `PIN_ME` values:
- in `deploy/argocd/root/values.yaml`, the registry, the certificate ARN, nine chart versions and the Cluster
  Autoscaler's image tag;
- in the charts, the two image digests.

Plus the Sloth image tag in the `Makefile`, and the commit SHA of each GitHub Action in `.github/workflows/`
(stage 3). None is a secret. They are committed before `gitops` is switched on, so Argo CD never renders a guessed
value. The later stages' pins are read now too, so the pins round happens once.

**1.1 — ops: read them, and build the two images** (several minutes: the build embeds 269 anime).

```bash
cd ~/Anime-Recommender && export KUBECONFIG=$HOME/.kube/anime
make -s pins
make image > /tmp/anime-image.log 2>&1; echo "exit=$?"; tail -2 /tmp/anime-image.log
```

Expected:
- an account id, a registry and a certificate ARN;
- nine chart versions, none `null`. Argo Rollouts' is used from stage 5, KEDA's and the Cluster Autoscaler's from
  stage 7, Tempo's and the collector's from stage 8;
- the Cluster Autoscaler image tag and the Sloth release tag, neither `LOOKUP-FAILED`;
- ten action SHAs, none `LOOKUP-FAILED`;
- `exit=0`, then `api  digest: sha256:…` and `ui   digest: sha256:…`. `exit` not 0: read `/tmp/anime-image.log`.

**Report all of it.** The values are committed on the laptop (by me; you push), and nothing below runs before that.

**1.2 — ops: after the push, nothing is left to pin.**

```bash
cd ~/Anime-Recommender && export KUBECONFIG=$HOME/.kube/anime
git pull --ff-only
git grep -nE ':[[:space:]]*"?PIN_ME|@PIN_ME' -- deploy .github Makefile || echo "no PIN_ME left"
```

Expected: `no PIN_ME left`.

---

## 2. Switch the stage on — ops

**2.1 — add `gitops` and apply the bootstrap.**

```bash
cd ~/Anime-Recommender && export KUBECONFIG=$HOME/.kube/anime
F=infra/terraform/bootstrap/terraform.tfvars
if grep -q '^enabled_stages' $F; then sed -i 's/^enabled_stages .*/enabled_stages            = ["gitops"]/' $F
else echo 'enabled_stages            = ["gitops"]' >> $F; fi
grep -q '^enabled_stages.*"gitops"' $F && echo "gitops enabled" || echo "ENABLED_STAGES NOT SET"
make bootstrap-plan
```

Expected: `gitops enabled`, then `Plan: 0 to add, 1 to change, 0 to destroy.` (only the root's values
change). Then:

```bash
cd ~/Anime-Recommender && export KUBECONFIG=$HOME/.kube/anime
make bootstrap
kubectl -n argocd annotate application root argocd.argoproj.io/refresh=hard --overwrite
```

**2.2 — watch the waves.** −2 load balancer controller and External Secrets; −1 platform and external-dns; 0 monitoring
and Argo CD's Ingress; 1 api and ui. About 15 minutes.

```bash
cd ~/Anime-Recommender && export KUBECONFIG=$HOME/.kube/anime
for i in $(seq 60); do
  kubectl -n argocd get applications -o jsonpath='{range .items[*]}{.metadata.name} {.status.sync.status} {.status.health.status}{"\n"}{end}' > /tmp/apps.txt
  n=$(wc -l < /tmp/apps.txt); ok=$(awk '$2=="Synced" && $3=="Healthy"' /tmp/apps.txt | wc -l)
  echo "$(date +%T)  $ok/$n Synced+Healthy  $(awk '$2!="Synced"||$3!="Healthy"{printf "%s ", $1}' /tmp/apps.txt)"
  [ "$n" -eq 8 ] && [ "$ok" -eq 8 ] && break; sleep 20
done
make -s apps
```

Expected: the count climbs wave by wave to `8/8`, then a table of `root` and seven children, all `Synced Healthy`. If
every wave starts within the same few seconds, the Application health check is not active (troubleshooting).

---

## 3. Criterion #2 — by name, by count, by revision, by readiness — ops

```bash
cd ~/Anime-Recommender && export KUBECONFIG=$HOME/.kube/anime
git fetch -q origin
EXPECTED="anime-api anime-ui aws-load-balancer-controller external-dns external-secrets kube-prometheus-stack platform root"
GOT=$(kubectl -n argocd get applications -o jsonpath='{.items[*].metadata.name}' | tr ' ' '\n' | LC_ALL=C sort | tr '\n' ' ' | sed 's/ $//')
[ "$GOT" = "$EXPECTED" ] && echo "names OK (8)" || { echo "NAMES DIFFER"; echo " expected: $EXPECTED"; echo " got:      $GOT"; }
kubectl -n argocd get applications -o jsonpath='{range .items[*]}{.metadata.name} {.status.sync.status} {.status.health.status}{"\n"}{end}' \
  | awk '$2!="Synced"||$3!="Healthy"{bad=1; print "NOT READY: "$0} END{if(NR==0) print "NO APPLICATIONS"; else if(!bad) print "all Synced+Healthy"}'
HEAD=$(git rev-parse origin/anime/build)
for a in root platform anime-api anime-ui; do
  r=$(kubectl -n argocd get application $a -o jsonpath='{.status.sync.revision}')
  [ "$r" = "$HEAD" ] && echo "$a at $HEAD" || echo "$a AT '$r', NOT $HEAD"
done
kubectl get clustersecretstore aws-secrets-manager -o jsonpath='store ready: {.status.conditions[?(@.type=="Ready")].status}{"\n"}'
for es in anime/anime-llm monitoring/grafana-admin; do
  kubectl -n ${es%/*} get externalsecret ${es#*/} -o jsonpath="${es}: {.status.conditions[?(@.type==\"Ready\")].status}{\"\n\"}"
done
kubectl -n anime get secret anime-llm -o json 2>/dev/null \
  | jq -e '.data | (length == 2) and all(.[]; length > 0)' >/dev/null && echo "anime-llm has both keys" || echo "SECRET anime-llm MISSING OR INCOMPLETE"
```

Expected: `names OK (8)`, `all Synced+Healthy`, four `… at <hash>`, `store ready: True`, both ExternalSecrets `True`,
`anime-llm has both keys`. Why each: "all Healthy" is also true of none, so the names and count are asserted; `Synced`
means "synced to what Argo CD fetched", so the revision is compared with the branch; Argo CD cannot judge every kind, so
the store and the ExternalSecrets are read for their own `Ready` (GitOps A7.1). The four Helm-repo Applications have a
chart version as revision, so they are covered by the name and status lines, not the revision loop.

---

## 4. Five Ingresses, two load balancers, and the readiness gates — ops

```bash
cd ~/Anime-Recommender && export KUBECONFIG=$HOME/.kube/anime
kubectl get ingress -A -o custom-columns='NS:.metadata.namespace,NAME:.metadata.name,HOSTS:.spec.rules[*].host,ADDRESS:.status.loadBalancer.ingress[0].hostname'
aws resourcegroupstaggingapi get-resources --resource-type-filters elasticloadbalancing:loadbalancer \
  --tag-filters Key=elbv2.k8s.aws/cluster,Values=anime --query 'ResourceTagMappingList[].ResourceARN' --output text | tr '\t' '\n' \
  | while read arn; do aws elbv2 describe-load-balancers --load-balancer-arns "$arn" --query 'LoadBalancers[0].[Scheme,State.Code,DNSName]' --output text; done
```

Expected: five Ingresses — `anime-public` with two hosts, and `argocd-server`, grafana, prometheus, alertmanager, the four
internal ones sharing **one** address — and two load balancers: one `internet-facing`, one `internal`, both `active`.

The first api/ui pods may have started before the load balancer's target group existed, and then carry no readiness gate
(the comment in `deploy/platform/base/namespace.yaml`). Re-create them now that it exists, and check:

```bash
cd ~/Anime-Recommender && export KUBECONFIG=$HOME/.kube/anime
kubectl -n anime rollout restart deploy/anime-api deploy/anime-ui
kubectl -n anime rollout status deploy/anime-api --timeout=5m && kubectl -n anime rollout status deploy/anime-ui --timeout=5m
kubectl -n anime get pods -o custom-columns='NAME:.metadata.name,NODE:.spec.nodeName,READY:.status.containerStatuses[0].ready,GATES:.spec.readinessGates[*].conditionType'
```

Expected: four pods, `READY true`, each with a `target-health.elbv2.k8s.aws/…` gate, the two api pods preferably on
different nodes (a preference — after a Spot reclaim they can share one until the next restart).

---

## 5. Names — ops

Negative answers are cached for up to 15 minutes, so first wait on the zone's own name server, then ask a public
resolver.

```bash
cd ~/Anime-Recommender && export KUBECONFIG=$HOME/.kube/anime
NS=$(dig +short NS recruitai.io.vn | head -1)
for h in anime api.anime argocd.anime grafana.anime prometheus.anime alertmanager.anime; do
  for i in $(seq 40); do [ -n "$(dig +short @$NS $h.recruitai.io.vn A)" ] && break; sleep 15; done
  printf '%-40s %s\n' "$h.recruitai.io.vn" "$(dig +short @1.1.1.1 $h.recruitai.io.vn A | tr '\n' ' ')"
done
ZONE=$(aws route53 list-hosted-zones-by-name --dns-name recruitai.io.vn --query 'HostedZones[0].Id' --output text)
aws route53 list-resource-record-sets --hosted-zone-id "$ZONE" --output text \
  --query "ResourceRecordSets[?Type=='TXT' && contains(Name,'anime')].Name"
kubectl -n external-dns logs deploy/external-dns --since=30m | grep -iE 'denied|error|no zone' || echo "no errors in external-dns"
```

Expected: the first two names resolve to public addresses, the four admin names to `10.30.x.x`; a list of TXT ownership
names (**report it**: it settles whether the IAM name list in `pod-identity.tf` covers the real format); `no errors in
external-dns`.

---

## 6. Criterion #15 — HTTPS — ops (off the VPN)

```bash
cd ~/Anime-Recommender && export KUBECONFIG=$HOME/.kube/anime
CERT=$(terraform -chdir=infra/terraform/shared output -raw certificate_arn)
for u in https://anime.recruitai.io.vn/ https://api.anime.recruitai.io.vn/healthz; do
  host=$(echo "$u" | cut -d/ -f3)
  printf '%-45s http:%s  https:%s\n' "$u" \
    "$(curl -s -o /dev/null --max-time 15 -w '%{http_code}>%{redirect_url}' "http://$host/")" \
    "$(curl -s -o /dev/null --max-time 15 -w '%{http_code}' "$u")"
done
ACM=$(aws acm describe-certificate --certificate-arn "$CERT" --query Certificate.Serial --output text | tr -d ':' | tr a-f A-F)
for h in anime.recruitai.io.vn api.anime.recruitai.io.vn; do
  s=$(echo | timeout 15 openssl s_client -connect $h:443 -servername $h 2>/dev/null | openssl x509 -noout -serial | cut -d= -f2)
  [ -n "$s" ] && [ "$s" = "$ACM" ] && echo "$h serves the ACM certificate" || echo "$h SERIAL '$s' != ACM '$ACM'"
done
for arn in $(aws resourcegroupstaggingapi get-resources --resource-type-filters elasticloadbalancing:loadbalancer \
    --tag-filters Key=elbv2.k8s.aws/cluster,Values=anime --query 'ResourceTagMappingList[].ResourceARN' --output text); do
  l=$(aws elbv2 describe-listeners --load-balancer-arn "$arn" --query "Listeners[?Port==\`443\`].ListenerArn | [0]" --output text)
  d=$(aws elbv2 describe-listener-certificates --listener-arn "$l" --query 'Certificates[?IsDefault].CertificateArn | [0]' --output text)
  [ "$d" = "$CERT" ] && echo "$(basename $arn): listener carries the intended certificate" || echo "$(basename $arn): CERTIFICATE $d"
done
curl -s --max-time 60 -X POST https://api.anime.recruitai.io.vn/recommend -H 'content-type: application/json' \
  -d '{"query":"school romance with comedy"}' -o /tmp/rec.json -w 'recommend: %{http_code} in %{time_total}s\n'
```

Expected: both lines `http:301>https://<host>:443/…  https:200`; both hosts `serve the ACM certificate`; both load
balancers `carry the intended certificate`; `recommend: 200`. No `-k`: the chain must verify. The status code sits
beside the chain because TLS completes even in front of a 503, and the serial because an unnamed certificate could be
another project's (GitOps A7.2).

---

## 7. Criterion #16 — only through the VPN, from the laptop

**7.1 — laptop, VPN OFF** (`anime` deactivated). About 2–3 minutes: each refused connection takes a while.

```powershell
$names = 'argocd','grafana','prometheus','alertmanager' | ForEach-Object { "$_.anime.recruitai.io.vn" }
foreach ($n in $names) {
  $ip = (Resolve-DnsName $n -Type A -ErrorAction SilentlyContinue | Where-Object Type -eq 'A' | Select-Object -First 1).IPAddress
  if (-not $ip -or $ip -notlike '10.30.*') { "{0,-38} NO PRIVATE ADDRESS ({1})" -f $n, $ip; continue }
  $tcp = Test-NetConnection $n -Port 443 -WarningAction SilentlyContinue
  "{0,-38} {1,-15} reachable={2}" -f $n, $ip, $tcp.TcpTestSucceeded
}
```

Expected: four lines with a `10.30.x.x` address and `reachable=False`. The address is the real assertion: `False` alone is
also what a missing name gives. `NO PRIVATE ADDRESS` with nothing in brackets means your router discards public answers
holding private addresses (DNS-rebinding protection) — report it (GitOps A6.2); 7.2 cannot pass on this network.

**7.2 — laptop, VPN ON** (activate `anime`, wait for a handshake), in the same session:

```powershell
$names = 'argocd','grafana','prometheus','alertmanager' | ForEach-Object { "$_.anime.recruitai.io.vn" }
foreach ($n in $names) {
  try { $r = Invoke-WebRequest "https://$n/" -UseBasicParsing -TimeoutSec 15
        "{0,-38} {1} {2}" -f $n, $r.StatusCode, $r.BaseResponse.ResponseUri.Host }
  catch { "{0,-38} FAILED: {1}" -f $n, $_.Exception.Message }
}
```

Expected: four `200`, each ending on its **own** host. PowerShell rejects an unverified chain, so a `200` also means the
wildcard certificate verified; the host column catches a redirect to somewhere else.

**7.3 — ops: the configuration half.** Private addresses are unroutable from the internet whatever the rules say, so the
behavioural test cannot see the security groups (GitOps A8.3).

```bash
cd ~/Anime-Recommender && export KUBECONFIG=$HOME/.kube/anime
for arn in $(aws resourcegroupstaggingapi get-resources --resource-type-filters elasticloadbalancing:loadbalancer \
    --tag-filters Key=elbv2.k8s.aws/cluster,Values=anime --query 'ResourceTagMappingList[].ResourceARN' --output text); do
  aws elbv2 describe-load-balancers --load-balancer-arns "$arn" --query 'LoadBalancers[0].[Scheme]' --output text
  for sg in $(aws elbv2 describe-load-balancers --load-balancer-arns "$arn" --query 'LoadBalancers[0].SecurityGroups[]' --output text); do
    aws ec2 describe-security-groups --group-ids $sg --output text \
      --query "SecurityGroups[0].[GroupName, join(' ', IpPermissions[].join(':', [to_string(FromPort), join('+', IpRanges[].CidrIp)]))]"
  done
done
```

Expected: `internet-facing` with a group allowing `80:0.0.0.0/0 443:0.0.0.0/0`; `internal` with a group allowing
`443:10.30.0.0/16+10.98.0.0/24`. Each also lists the controller's shared backend group (`k8s-traffic-anime-…`) with no
CIDRs — that one only lets the ALBs into the nodes.

**7.4 — laptop, VPN ON: open the UIs.** Passwords, on ops:

```bash
cd ~/Anime-Recommender && export KUBECONFIG=$HOME/.kube/anime
echo "argocd  admin / $(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d)"
echo "grafana admin / $(kubectl -n monitoring get secret grafana-admin -o jsonpath='{.data.admin-password}' | base64 -d)"
```

Browse the four `https://…anime.recruitai.io.vn` names. Every link inside a UI must stay on its own `https://` name — a
jump to `localhost` or plain `http` means that app was not told its name. The `argocd` CLI, if used through this name,
needs `--grpc-web`.

---

## 8. Evidence — ops

Paste in the chat with the outputs of 3, 5, 6 and 7.1–7.3; it becomes `docs/evidence/gitops.md`.

```bash
cd ~/Anime-Recommender && export KUBECONFIG=$HOME/.kube/anime
make -s apps
kubectl get ingress -A --no-headers | wc -l
kubectl -n anime get pods -o custom-columns='NAME:.metadata.name,NODE:.spec.nodeName,GATES:.spec.readinessGates[*].conditionType'
```

---

## 9. Teardown and the next session

`make down` (stage 1, section 7) now does real work: stops self-heal on the root first and then every child, deletes the
five Ingresses, waits for both load balancers, their target groups and security groups, waits for external-dns to remove
the six records, deletes the Applications, then destroys the cluster. Expect 10–15 minutes.

Next session: stage 1's order, then `make bootstrap-plan && make bootstrap` with `enabled_stages` already containing
`gitops` — the root rebuilds this whole stage by itself; repeat from step 2.2.

---

## Troubleshooting

| Symptom | Likely cause | What to do |
|---|---|---|
| A child shows `ComparisonError` naming `PIN_ME` | A pin was not committed | 1.2 must print `no PIN_ME left` |
| Every wave starts within seconds, not in turn | The Application health check is missing from `argocd-cm` | `kubectl -n argocd get cm argocd-cm -o yaml \| grep -c argoproj.io_Application` must be 1; `make bootstrap-plan && make bootstrap` |
| A child stays `OutOfSync`/`Progressing` after retries | A webhook or CRD was not ready on the first try; retries exhausted | `kubectl -n argocd get application <a> -o jsonpath='{.status.operationState.message}'`; then `kubectl -n argocd patch application <a> --type merge -p '{"operation":{"sync":{}}}'` |
| `failed calling webhook … elbv2.k8s.aws` | The load balancer controller pods are not Ready yet | Wait; the retry policy re-syncs. Still failing: `kubectl -n kube-system get pods -l app.kubernetes.io/name=aws-load-balancer-controller` |
| `failed calling webhook "vingress.elbv2.k8s.aws"` … `x509: certificate signed by unknown authority` (pods Ready) | The webhooks' `caBundle` and the Secret `aws-load-balancer-tls` came from two renders of the chart (each render makes a new CA) | Compare the two CAs' fingerprints (`caBundle` of `validatingwebhookconfiguration aws-load-balancer-webhook`, `ca.crt` of the Secret). Different: sync the Application so all three are written from one render, then restart the pods: `kubectl -n argocd patch application aws-load-balancer-controller --type merge -p '{"operation":{"sync":{}}}'`, then `kubectl -n kube-system rollout restart deploy/aws-load-balancer-controller`. Requires the template without `RespectIgnoreDifferences` (the comment there says why) |
| `failed calling webhook … external-secrets.io` | External Secrets' webhook not serving yet | Same: wait for its pods, the retry re-syncs |
| `metadata.annotations: Too long` | A CRD applied client-side | `ServerSideApply=true` missing on that Application's template |
| `platform` stuck, store not Ready | External Secrets lacks credentials | `kubectl describe clustersecretstore aws-secrets-manager`; `AccessDenied` → the Pod Identity association or the three ARNs |
| `grafana-admin` ExternalSecret not Ready | The Password generator's API version differs in the pinned release | `kubectl api-resources \| grep -i password`; report the group/version shown |
| ExternalSecret `anime-llm` `… does not have a value` | anime/llm never set | Stage 1, 2.5; then `kubectl -n anime annotate externalsecret anime-llm force-sync=$(date +%s) --overwrite` |
| api pods `ImagePullBackOff` | Wrong registry or digest pinned | `kubectl -n anime describe pod …`; `aws ecr describe-images --repository-name anime-api --image-ids imageDigest=<d>` |
| api pods Running `0/1`, gate `False` | ALB health check failing | `aws elbv2 describe-target-health`; `/readyz` 503 → the index or HF token (`kubectl -n anime logs deploy/anime-api`) |
| Ingress has no ADDRESS, events `FailedDeployModel` | Controller cannot resolve the VPC or subnets | `kubectl -n kube-system logs deploy/aws-load-balancer-controller`; VPC → the `vpcTags` value; "no matching subnets" → stage 1 subnet tags |
| Only one of the two ALBs missing | That scheme's subnet tag | Stage 1 `network.tf`; each scheme fails on its own |
| No HTTPS listener | Certificate not ISSUED or wrong ARN pinned | `aws acm describe-certificate --certificate-arn <arn> --query Certificate.Status` |
| Names never appear; log says `no zones` or nothing | Zone not matched | The `--aws-zone-match-parent` flag in the external-dns template |
| external-dns `AccessDenied … ChangeResourceRecordSets` | A TXT ownership name outside the IAM list | Report the name from step 5; the list in `pod-identity.tf` changes |
| Names exist at the name server but `1.1.1.1` says nothing | Negative cache from an earlier lookup | Wait up to 15 minutes; step 5 waits on the name server first for this reason |
| Serial or listener certificate differs | Another certificate served | Both scheme's Ingresses carry `pins.certificateArn`; compare with `terraform output certificate_arn` |
| 7.1 `NO PRIVATE ADDRESS ()` | Router's DNS-rebinding protection | Report it; try another network or set a public resolver on the laptop |
| 7.2 timeout with VPN on | No handshake, or gateway forwarding | WireGuard app's handshake time; stage 1, 3.3 |
| 7.2 one UI `502`/`503` | That UI's targets unhealthy | `aws elbv2 describe-target-health` for its target group |
| A UI links to `localhost` or `http://` | The app was not told its name | `externalUrl` / `root_url` / `url`; Argo CD also needs `server.insecure` |
| Prometheus Pending after a Spot reclaim | Node replacement in progress | `kubectl get nodes`; it has no volume, so it starts on any node once one is back |
| `argocd-initial-admin-secret` NotFound | Deleted after first login | `kubectl -n argocd patch secret argocd-secret --type json -p '[{"op":"remove","path":"/data/admin.password"}]'` then restart `argocd-server` (to be verified) |
| `make down` waits on load-balancer resources | A child still self-heals | `make down` now refuses to continue if any does; `make -s apps` and report |

---

[README](README.md) · [Concepts](concepts.md) · [Design §4.7](../eks-sre-llmops-design.md#47-names-tls-and-the-two-ways-in) ·
Previous: [Terraform guide](../terraform/guide.md)
