# Stage 1 — Guide: build the account, the cluster and a way in

Commands and checks only. **Why** each piece exists is in the comments of `infra/terraform/**`, `Makefile` and
`deploy/argocd/values/argocd.yaml`; the ideas are in [README](README.md) and [concepts](concepts.md).

Every block says where it runs:

- **laptop** — Windows. Only git, a browser and the WireGuard app. Never bash, grep or sed.
- **ops** — the ops workstation (Ubuntu, reached with Session Manager). Every ops block begins with
  `cd ~/Anime-Recommender && export KUBECONFIG=$HOME/.kube/anime` — without the export, a bare `kubectl` reads Medical's
  `~/.kube/config` and a check can pass against the wrong cluster.

Three rules for the whole guide:

- **Work inside tmux** on ops: `tmux new -A -s anime`. A Session Manager window that times out kills a running apply
  (and leaves a state lock) or the tunnel; tmux keeps both alive. `Ctrl-b c` opens a new tmux window, `Ctrl-b n`
  switches. Windows keep one role each: 1 commands, 2 the tunnel, 3 k6 (from stage 4), 4 the scaling recorder.
- **No block asks for input except where it says so.** Plans are saved to a file and applied from it, so the number you
  write down is the plan that is applied.
- **Outputs you are asked to report** — paste them in the chat.

Criterion closed by this stage: **#1** — apply from nothing, then plan again and see no changes, against resource
counts written down *before* applying ([design §6](../eks-sre-llmops-design.md#6-verification-and-evidence-definition-of-done)).

---

## 0. Before anything

**0.1 — laptop: push the branch.** Argo CD and the workstation both read the code from GitHub.

```powershell
git -C D:\DS-AI\LLMops\Anime-Recommender push -u origin anime/build
git -C D:\DS-AI\LLMops\Anime-Recommender ls-remote origin anime/build
```

Expected: the second line prints a commit hash.

**0.2 — ops: get the code and check the tools.**

```bash
tmux new -A -s anime
```

Then, inside tmux:

```bash
cd ~ && (test -d Anime-Recommender || git clone https://github.com/biabeogo147/Anime-Recommender.git)
cd ~/Anime-Recommender && git fetch origin && git checkout anime/build && git pull --ff-only
terraform version | head -1; kubectl version --client | head -1; helm version --short; aws --version
session-manager-plugin --version; which wg jq tmux
mkdir -p ~/anime-evidence
```

Expected: Terraform ≥ 1.11, a plugin version, and three paths.

**0.3 — ops: what the account allows.** Report the whole output.

```bash
cd ~/Anime-Recommender && export KUBECONFIG=$HOME/.kube/anime
aws freetier get-account-plan-state --query '[accountPlanType,accountPlanStatus,accountPlanRemainingCredits.amount]' \
  --output text || echo "PLAN-STATE CALL FAILED"
aws service-quotas get-service-quota --service-code ec2 --quota-code L-34B43A08 --query Quota.Value --output text
TYPES=$(sed -n '/variable "node_instance_types"/,/^}/s/.*default *= *\[\(.*\)\].*/\1/p' infra/terraform/cluster/variables.tf | tr ',' ' ' | tr -d '"')
aws ec2 describe-instance-types --instance-types $TYPES --query 'InstanceTypes[].[InstanceType,FreeTierEligible]' --output text
aws eks describe-cluster-versions --region ap-southeast-1 --version-status STANDARD_SUPPORT \
  --query 'sort_by(clusterVersions,&clusterVersion)[-1].clusterVersion' --output text
```

Expected, in order:
- the plan and what is left of its credit. `FREE ACTIVE <amount>` is fine: the Free plan runs EKS, and the credit is
  the budget for every session. Write the amount down;
- a Spot vCPU quota of at least `8`;
- `m7i-flex.large True`: the one node type, and eligible;
- `1.36`.

What stops the stage:
- **A type shows `False`, and the plan is `FREE`.** The Free plan launches only free-tier-eligible types. A dry run
  accepts the others anyway, so it is not a check here (docs/evidence/account.md). Report it: the type list changes
  in Git first.
- **The version is not `1.36`.** Report it; `kubernetes_version` changes in Git first.
- **The credit is low.** Each session costs an estimated 0.4–0.6 USD per cluster hour, shared with Medical, and the
  account closes when the credit is spent on the Free plan. Report it before applying.

**Only after changing the type list:** prove Spot really launches that type with one real instance, deleted a minute
later (well under a cent). Put the new type in `T=` first. This is how `m7i-flex.large` was checked on 2026-09-22.

```bash
cd ~/Anime-Recommender && export KUBECONFIG=$HOME/.kube/anime
T=m7i-flex.large
TOKEN=$(curl -s -X PUT http://169.254.169.254/latest/api/token -H "X-aws-ec2-metadata-token-ttl-seconds: 60")
MAC=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/mac)
SUBNET=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/network/interfaces/macs/$MAC/subnet-id)
AMI=$(aws ssm get-parameter --name /aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64 --query Parameter.Value --output text)
ID=$(aws ec2 run-instances --image-id "$AMI" --instance-type "$T" --subnet-id "$SUBNET" --no-associate-public-ip-address \
  --instance-market-options MarketType=spot --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=anime-spot-test},{Key=project,Value=anime}]' \
  --query 'Instances[0].InstanceId' --output text); echo "launched $ID"
aws ec2 wait instance-running --instance-ids "$ID" && aws ec2 describe-instances --instance-ids "$ID" \
  --query 'Reservations[0].Instances[0].[InstanceType,InstanceLifecycle,State.Name]' --output text
SIR=$(aws ec2 describe-instances --instance-ids "$ID" --query 'Reservations[0].Instances[0].SpotInstanceRequestId' --output text)
# Cancel the request first (the instance keeps running until terminated), then terminate it.
aws ec2 cancel-spot-instance-requests --spot-instance-request-ids "$SIR" --query 'CancelledSpotInstanceRequests[0].State' --output text
aws ec2 terminate-instances --instance-ids "$ID" >/dev/null && aws ec2 wait instance-terminated --instance-ids "$ID"
# Whatever happened above, nothing tagged for this test may be left running.
aws ec2 describe-instances --filters Name=tag:Name,Values=anime-spot-test Name=instance-state-name,Values=pending,running,stopping,stopped \
  --query 'Reservations[].Instances[].InstanceId' --output text | grep . && echo "LEFT RUNNING: terminate these" || echo "nothing left"
```

Expected: `launched i-…`, `<type> spot running`, `cancelled`, `nothing left`. An error at the launch names what the
plan refuses, and leaves nothing behind. Report it whole. If the session drops in the middle, run the last command
alone and terminate what it lists.

**0.4 — ops: Medical's pieces, and the values for the shared stack.** Replace the email on the `EMAIL=` line.

```bash
cd ~/Anime-Recommender && export KUBECONFIG=$HOME/.kube/anime
EMAIL='you@example.com'
ACC=$(aws sts get-caller-identity --query Account --output text)
aws s3 ls s3://medical-rag-tfstate-$ACC/ | head -3
aws route53 list-hosted-zones-by-name --dns-name recruitai.io.vn --max-items 1 --query 'HostedZones[0].Name' --output text
N=$(aws iam list-open-id-connect-providers --output text \
  --query "length(OpenIDConnectProviderList[?ends_with(Arn,'token.actions.githubusercontent.com')])")
echo "github oidc providers: $N"
printf 'budget_email                = "%s"\ncreate_github_oidc_provider = %s\n' "$EMAIL" "$([ "$N" = 1 ] && echo false || echo true)" \
  | tee infra/terraform/shared/terraform.tfvars
grep -q example.com infra/terraform/shared/terraform.tfvars && echo "EDIT THE EMAIL FIRST" || true
```

Expected: Medical's state prefixes, `recruitai.io.vn.`, a provider count of `0` or `1`, and a tfvars file with your
address. Nothing may say `EDIT THE EMAIL FIRST`.

---

## 1. Static checks — ops

Catches syntax and module-input mistakes before anything touches AWS.

```bash
cd ~/Anime-Recommender && export KUBECONFIG=$HOME/.kube/anime
terraform fmt -check -recursive infra/terraform && echo "fmt ok" || echo "fmt differs (cosmetic)"
for s in shared cluster bootstrap; do
  terraform -chdir=infra/terraform/$s init -backend=false -input=false -no-color >/dev/null \
    && terraform -chdir=infra/terraform/$s validate -no-color || echo "VALIDATE FAILED: $s"
done
bash -n infra/terraform/cluster/wireguard-init.sh && echo "script syntax ok"
```

Expected: three `Success! The configuration is valid.` and `script syntax ok`. **`VALIDATE FAILED` — stop and
report.** A `fmt differs` is cosmetic: report `terraform fmt -recursive -diff infra/terraform` and continue.

`init` leaves `.terraform.lock.hcl` files in the three folders; they are what pins the providers. Leave them; they get
committed from the laptop later.

---

## 2. The shared stack

**2.1 — ops: plan, write the count down, apply.**

```bash
cd ~/Anime-Recommender && export KUBECONFIG=$HOME/.kube/anime
make shared-plan
```

Expected: `Plan: N to add, 0 to change, 0 to destroy.` **Write N down.** Then:

```bash
cd ~/Anime-Recommender && export KUBECONFIG=$HOME/.kube/anime
time make shared
p=$(grep -oE 'Plan: [0-9]+' /tmp/anime-shared-plan.txt | grep -oE '[0-9]+')
a=$(grep -oE 'Resources: [0-9]+ added' /tmp/anime-shared-apply.txt | grep -oE '[0-9]+')
[ -n "$p" ] && [ "$p" = "$a" ] && echo "shared count OK: $p" || echo "COUNT MISMATCH plan=$p apply=$a"
```

Expected: `Apply complete! Resources: N added`, then `shared count OK: N`. The apply waits for ACM to issue the
certificate — usually under 10 minutes; past 20, see *ACM* in troubleshooting.

**2.2 — ops: plan again — criterion #1, part 1.**

```bash
cd ~/Anime-Recommender && export KUBECONFIG=$HOME/.kube/anime
terraform -chdir=infra/terraform/shared plan -no-color -detailed-exitcode > ~/anime-evidence/shared-replan.txt 2>&1; echo "exit=$?"
grep -E '^(No changes|Plan:|Error)' ~/anime-evidence/shared-replan.txt
aws acm list-certificates --region ap-southeast-1 \
  --query "CertificateSummaryList[?DomainName=='anime.recruitai.io.vn'].Status" --output text
```

Expected: `exit=0`, `No changes.`, `ISSUED`. `exit=2` means changes — the criterion fails; report the file. `exit=1` is
an error; the file says which. This plan refreshes (no `-refresh=false`), so real drift would show.

**2.3 — laptop: a WireGuard key for this project.** WireGuard app → *Add Tunnel ▾* → *Add empty tunnel…* (Ctrl+N), name
it `anime`. Copy the **public key** it shows. Do not activate it yet; its private key never leaves the laptop.

**2.4 — ops: the gateway's secret. Run once.** Paste the laptop's public key on the first line. Running this again after
`make infra` writes a *new* server key that the running gateway does not have — see troubleshooting.

```bash
cd ~/Anime-Recommender && export KUBECONFIG=$HOME/.kube/anime
OPERATOR_PUBLIC_KEY='paste-the-laptop-public-key-here'
( umask 077
  jq -n --arg s "$(wg genkey)" --arg o "$OPERATOR_PUBLIC_KEY" '{serverPrivateKey:$s, operatorPublicKey:$o}' > /tmp/wg.json
  aws secretsmanager put-secret-value --secret-id anime/wireguard --secret-string file:///tmp/wg.json >/dev/null
  shred -u /tmp/wg.json )
aws secretsmanager get-secret-value --secret-id anime/wireguard --query SecretString --output text | jq -c 'map_values(length)'
```

Expected: `{"serverPrivateKey":44,"operatorPublicKey":44}`. Any other length means a wrong paste.

**2.5 — ops: the app's secrets.** Needed from stage 2; set them now if you have them. Input is hidden and stays out of
the shell history.

```bash
cd ~/Anime-Recommender && export KUBECONFIG=$HOME/.kube/anime
read -rs -p "OPENAI_API_KEY: " O; echo; read -rs -p "GOOGLE_API_KEY (Enter to skip): " G; echo
read -rs -p "HF_TOKEN: " H; echo
# A skipped key is left out rather than stored empty; the api reads only the key of the provider it runs.
aws secretsmanager put-secret-value --secret-id anime/llm --secret-string "$(jq -n --arg o "$O" --arg g "$G" --arg h "$H" \
  '{OPENAI_API_KEY:$o, GOOGLE_API_KEY:$g, HF_TOKEN:$h} | with_entries(select(.value != ""))')" >/dev/null; unset O G H
read -rs -p "LANGFUSE_PUBLIC_KEY: " P; echo; read -rs -p "LANGFUSE_SECRET_KEY: " S; echo
aws secretsmanager put-secret-value --secret-id anime/langfuse \
  --secret-string "$(jq -n --arg p "$P" --arg s "$S" '{LANGFUSE_PUBLIC_KEY:$p, LANGFUSE_SECRET_KEY:$s}')" >/dev/null; unset P S
read -rs -p "DISCORD_WEBHOOK_URL: " D; echo
aws secretsmanager put-secret-value --secret-id anime/alerting \
  --secret-string "$(jq -n --arg d "$D" '{DISCORD_WEBHOOK_URL:$d}')" >/dev/null; unset D
for s in llm langfuse alerting; do printf '%-9s ' $s; aws secretsmanager get-secret-value --secret-id anime/$s \
  --query SecretString --output text | jq -c 'map_values(length)'; done
```

This block reads input, so paste it in two parts if your terminal struggles: up to the last `unset D`, then the `for`
loop. Pasted whole, a `read` can take the next pasted line as its answer. Expected: every length above `0`. A secret you
skipped prints `ResourceNotFoundException … AWSCURRENT` — expected until you set it. `anime/llm` needs `HF_TOKEN` and
the key of the provider the api runs: `OPENAI_API_KEY` by default, `GOOGLE_API_KEY` for Gemini.

**2.6 — ops: add one key to `anime/llm` without losing the others.** `put-secret-value` replaces the whole JSON, so a
key is added by reading the current value and merging into it. Used on 2026-09-22 to add `OPENAI_API_KEY` to a secret
that held only the Gemini and Hugging Face keys. Paste the first line alone and type the key:

```bash
read -rs -p "OPENAI_API_KEY: " O; echo; echo "length: ${#O}"
```

Then, with the length above `0`:

```bash
cd ~/Anime-Recommender && export KUBECONFIG=$HOME/.kube/anime
cur=$(aws secretsmanager get-secret-value --secret-id anime/llm --query SecretString --output text)
aws secretsmanager put-secret-value --secret-id anime/llm \
  --secret-string "$(jq -c --arg o "$O" '. + {OPENAI_API_KEY:$o}' <<<"$cur")" >/dev/null; unset O cur
aws secretsmanager get-secret-value --secret-id anime/llm --query SecretString --output text | jq -c 'map_values(length)'
```

Expected: the keys that were there before, with their lengths, plus `OPENAI_API_KEY` (about 164 for a project key).

A cluster built after this reads the new value when it starts. A cluster **already running** would pick it up only at
the ExternalSecret's next hourly refresh, and a pod switched to `openai` before that would never become ready
(`OPENAI_API_KEY is not set`). So, only if the cluster is up (tunnel open), copy it now and check:

```bash
cd ~/Anime-Recommender && export KUBECONFIG=$HOME/.kube/anime
kubectl -n anime annotate externalsecret anime-llm force-sync=$(date +%s) --overwrite
sleep 15
kubectl -n anime get secret anime-llm -o json | jq -e '.data | has("OPENAI_API_KEY")' >/dev/null \
  && echo "OPENAI_API_KEY in the cluster" || echo "NOT YET: wait and rerun the last command"
```

---

## 3. The cluster stack

**3.1 — ops: plan and write the count down.**

```bash
cd ~/Anime-Recommender && export KUBECONFIG=$HOME/.kube/anime
make plan
```

Expected: `Plan: N to add, 0 to change, 0 to destroy.` **Write N down.** Then apply — about 15–20 minutes:

```bash
cd ~/Anime-Recommender && export KUBECONFIG=$HOME/.kube/anime
time make infra
p=$(grep -oE 'Plan: [0-9]+' /tmp/anime-cluster-plan.txt | grep -oE '[0-9]+')
a=$(grep -oE 'Resources: [0-9]+ added' /tmp/anime-cluster-apply.txt | grep -oE '[0-9]+')
[ -n "$p" ] && [ "$p" = "$a" ] && echo "cluster count OK: $p" || echo "COUNT MISMATCH plan=$p apply=$a"
```

**3.2 — ops: plan again — criterion #1, part 2.**

```bash
cd ~/Anime-Recommender && export KUBECONFIG=$HOME/.kube/anime
terraform -chdir=infra/terraform/cluster plan -no-color -detailed-exitcode > ~/anime-evidence/cluster-replan.txt 2>&1; echo "exit=$?"
grep -E '^(No changes|Plan:|Error)' ~/anime-evidence/cluster-replan.txt
aws eks describe-cluster --name anime --output text \
  --query 'cluster.[version,status,resourcesVpcConfig.endpointPublicAccess,resourcesVpcConfig.endpointPrivateAccess]'
```

Expected: `exit=0`, `No changes.`, then `1.36  ACTIVE  False  True`.

**3.3 — ops: the gateway finished booting.** Retries for up to five minutes.

```bash
cd ~/Anime-Recommender && export KUBECONFIG=$HOME/.kube/anime
GW=$(terraform -chdir=infra/terraform/cluster output -raw wireguard_instance_id)
for i in $(seq 20); do
  CMD=$(aws ssm send-command --instance-ids "$GW" --document-name AWS-RunShellScript \
    --parameters 'commands=["test -f /var/log/wireguard-ready && echo READY || echo NOT-READY","wg show wg0 | head -3"]' \
    --query Command.CommandId --output text 2>/dev/null) \
  && aws ssm wait command-executed --command-id "$CMD" --instance-id "$GW" 2>/dev/null \
  && OUT=$(aws ssm get-command-invocation --command-id "$CMD" --instance-id "$GW" --query StandardOutputContent --output text) \
  && grep -qx READY <<<"$(head -1 <<<"$OUT")" && { echo "$OUT"; break; }
  echo "not ready yet ($i/20)"; sleep 15
done
```

Expected: `READY` and an `interface: wg0` block. Twenty `not ready yet` — see troubleshooting.

---

## 4. The way in

**4.1 — ops: kubeconfig.**

```bash
cd ~/Anime-Recommender && export KUBECONFIG=$HOME/.kube/anime
ss -ltn 'sport = :6443' | tail -n +2
make kubeconfig
kubectl config current-context
```

Expected: the `ss` line prints **nothing** (nothing holds 6443 — if something does, it is Medical's tunnel: close it, or
add `TUNNEL_PORT=6444` to `make kubeconfig` here and to `make tunnel` in 4.2, every session). Then
`https://127.0.0.1:6443 <id>.<xx>.ap-southeast-1.eks.amazonaws.com` — both parts must be there — and `anime`.

**4.2 — ops, second tmux window (`Ctrl-b c`): the tunnel.**

```bash
cd ~/Anime-Recommender && export KUBECONFIG=$HOME/.kube/anime
make tunnel
```

Expected: `Waiting for connections...`. Leave it; switch back with `Ctrl-b n`.

**4.3 — ops, first window: the API answers — and only through the tunnel.**

```bash
cd ~/Anime-Recommender && export KUBECONFIG=$HOME/.kube/anime
make ready
kubectl get nodes -L eks.amazonaws.com/capacityType,node.kubernetes.io/instance-type
EP=$(terraform -chdir=infra/terraform/cluster output -raw cluster_endpoint); H=${EP#https://}
getent hosts "$H"
curl -k -sS -o /dev/null --max-time 10 "$EP/readyz"; rc=$?
[ -n "$H" ] && [ $rc -eq 28 ] && echo "not reachable directly: correct (timeout)" || echo "UNEXPECTED rc=$rc"
```

Expected: `ok`; two nodes `Ready` with `SPOT` and `m7i-flex.large`; `getent` shows `10.30.250.x` (a private
address, in the control-plane subnets); last line `not reachable directly: correct (timeout)`. That last check is the
negative half: the API has an address, but nothing outside the VPC can connect to it. Anything but a timeout (`rc=28`)
is reported, not explained away.

**4.4 — ops → laptop: the VPN profile.**

```bash
cd ~/Anime-Recommender && export KUBECONFIG=$HOME/.kube/anime
make vpn-config
```

**laptop:** in the `anime` tunnel window, keep the `PrivateKey` line the app generated and replace everything else with
the lines between `copy from here` and `to here`. Save, *Activate*. Within ~10 s the app shows **Latest handshake: a few
seconds ago**. Nothing answers through it yet — the internal load balancer arrives in stage 2 — and the API server is
deliberately not reachable over it. Deactivate it again.

---

## 5. Argo CD

**5.1 — ops: pin the chart versions.** `target_revision` is the branch Argo CD follows; until `anime/build` is merged
into `main`, it is this branch. Report the two versions: they move into `bootstrap/main.tf`, so the pin lives in Git.

```bash
cd ~/Anime-Recommender && export KUBECONFIG=$HOME/.kube/anime
helm repo add argo https://argoproj.github.io/argo-helm --force-update >/dev/null && helm repo update argo >/dev/null
CD=$(helm search repo argo/argo-cd -o json | jq -r '.[0].version')
APPS=$(helm search repo argo/argocd-apps -o json | jq -r '.[0].version')
[ "$CD" != null ] && [ -n "$CD" ] && [ "$APPS" != null ] && [ -n "$APPS" ] || echo "CHART LOOKUP FAILED - do not continue"
printf 'argocd_chart_version      = "%s"\nargocd_apps_chart_version = "%s"\ntarget_revision           = "anime/build"\nenabled_stages            = []\n' "$CD" "$APPS" \
  | tee infra/terraform/bootstrap/terraform.tfvars
```

**5.2 — ops: plan, write the count down, apply.**

```bash
cd ~/Anime-Recommender && export KUBECONFIG=$HOME/.kube/anime
make bootstrap-plan
```

Expected: `Plan: 2 to add`. Then:

```bash
cd ~/Anime-Recommender && export KUBECONFIG=$HOME/.kube/anime
time make bootstrap
p=$(grep -oE 'Plan: [0-9]+' /tmp/anime-bootstrap-plan.txt | grep -oE '[0-9]+')
a=$(grep -oE 'Resources: [0-9]+ added' /tmp/anime-bootstrap-apply.txt | grep -oE '[0-9]+')
[ -n "$p" ] && [ "$p" = "$a" ] && echo "bootstrap count OK: $p" || echo "COUNT MISMATCH plan=$p apply=$a"
terraform -chdir=infra/terraform/bootstrap plan -no-color -detailed-exitcode -var kubeconfig_path=$HOME/.kube/anime \
  > ~/anime-evidence/bootstrap-replan.txt 2>&1; echo "exit=$?"
kubectl -n argocd wait application/root --for=jsonpath='{.status.sync.status}'=Synced --timeout=180s
kubectl -n argocd get pods
kubectl -n argocd get applications
[ "$(kubectl -n argocd get application root -o jsonpath='{.status.sync.revision}')" = "$(git rev-parse origin/anime/build)" ] \
  && echo "root at the pushed commit" || echo "ROOT IS AT ANOTHER REVISION"
```

Expected: `bootstrap count OK: 2`, `exit=0`, `condition met`, every pod `Running`, `root  Synced  Healthy`, and
`root at the pushed commit`. The root has no children yet — `enabled_stages = []`, so its chart (`deploy/argocd/root`)
renders nothing — which proves Argo CD reads the branch and renders the chart, nothing more. Each later stage's guide
adds its name to `enabled_stages` and re-applies the bootstrap.

---

## 6. Evidence — ops

Paste the output in the chat; it becomes `docs/evidence/terraform.md`. Run it in the same session: `/tmp` does not
survive a workstation reboot.

```bash
cd ~/Anime-Recommender && export KUBECONFIG=$HOME/.kube/anime
for s in shared cluster bootstrap; do
  printf '%-9s plan: %-4s apply: %-4s managed in state: %s\n' $s \
    "$(grep -oE 'Plan: [0-9]+' /tmp/anime-$s-plan.txt | grep -oE '[0-9]+')" \
    "$(grep -oE 'Resources: [0-9]+ added' /tmp/anime-$s-apply.txt | grep -oE '[0-9]+')" \
    "$(terraform -chdir=infra/terraform/$s state list | grep -Evc '(^|\.)data\.')"
done
for f in shared cluster bootstrap; do printf '%-9s re-plan: ' $f; grep -E '^(No changes|Plan:|Error)' ~/anime-evidence/$f-replan.txt; done
aws eks describe-cluster --name anime --query 'cluster.[version,platformVersion,resourcesVpcConfig.endpointPublicAccess]' --output text
kubectl get nodes -L eks.amazonaws.com/capacityType,node.kubernetes.io/instance-type --no-headers
kubectl get --raw /readyz; echo
```

Add by hand: the three `real` times from `time`, and the last line of 4.3.

---

## 7. End of session, and the next one

**Teardown — ops, first window, tunnel still open:**

```bash
cd ~/Anime-Recommender && export KUBECONFIG=$HOME/.kube/anime
make down
```

Type `yes` at the destroy prompt — the only prompt in this guide. Expected: `Destroy complete!`. The shared stack —
ECR, secrets, certificate — stays. If the cluster never became reachable (a failed `make infra`) and no Ingress or volume
was ever created, use `make infra-destroy` instead.

**Next session — ops:** `make plan` → `make infra` → `make kubeconfig` → `make tunnel` (window 2) → `make ready` →
`make bootstrap-plan` → `make bootstrap`. Step 2 does not repeat. A fresh clone needs `bootstrap/terraform.tfvars`
again (5.1) until the versions are pinned in Git. The VPN profile needs no change: `vpn.anime` follows the new Elastic IP.

---

## Troubleshooting

| Symptom | Likely cause | What to do |
|---|---|---|
| 0.3: a type shows `False` on the `FREE` plan | The Free plan launches only free-tier-eligible types | Report; the type list changes first (0.3, the real Spot launch, for a new type) |
| Node group fails: `AsgInstanceLaunchFailures`, `InsufficientInstanceCapacity` or `UnfulfillableCapacity` | No Spot capacity for the one type in these zones | `make plan && make infra` later. Last resort: `capacity_type = "ON_DEMAND"` in `eks.tf`, a change in Git that **replaces** the node group, done before apply, never mid-run. The On-Demand vCPU quota (16) is shared with Medical, which uses about 10: two Anime nodes fit, four do not |
| 1: `VALIDATE FAILED` | A module input name differs in the downloaded module version | Report the error; the code is fixed, not the guide |
| `make shared`: `EntityAlreadyExists` on the OIDC provider | 0.4 counted wrong | Set `create_github_oidc_provider = false` in `shared/terraform.tfvars`, `make shared-plan`, `make shared` |
| `make shared` waits long on `aws_acm_certificate_validation` | Validation record not answering, or a CAA record excludes Amazon | `aws acm describe-certificate --certificate-arn <arn> --query 'Certificate.[Status,FailureReason]'`; `CAA_ERROR` → a CAA record needs `0 issue "amazon.com"`; also `dig +short NS recruitai.io.vn` must match the zone |
| `make shared`: secret `scheduled for deletion` | The name was deleted in the last 7 days | `aws secretsmanager restore-secret --secret-id anime/<n>`, then `terraform -chdir=infra/terraform/shared import 'aws_secretsmanager_secret.this["<n>"]' <arn>` |
| `make plan`: `couldn't find resource` on a secret | The shared stack is not applied | `make shared` first |
| `make plan`: `alias/aws/secretsmanager` not found | No secret in the region uses the default key yet | Run 2.4 first (it stores a value with the default key), then plan again |
| Re-plan `exit=2` right after apply | Drift, or an API that normalises what was sent | Report the `*-replan.txt` — this *is* criterion #1 |
| `COUNT MISMATCH` | An apply partly failed, or the plan file is stale | Report both files in `/tmp/anime-*` |
| `make infra`: `unsupported Kubernetes version` | The pin is newer than EKS offers | Fix `kubernetes_version` in Git (0.3) |
| Node group fails: `MaxSpotInstanceCountExceeded` | Spot vCPU quota (0.3) below 8 | Request a quota increase |
| Node group fails: `NodeCreationFailure … failed to join` | CNI add-on or NAT not ready | Report `aws eks describe-nodegroup --cluster-name anime --nodegroup-name <name>` health issues |
| `Error acquiring the state lock` | A run was interrupted | Check no terraform runs (`pgrep -a terraform`), then `terraform -chdir=infra/terraform/<s> force-unlock <ID>` with the ID from the error |
| `Backend configuration changed` | `.terraform` was initialised against another bucket | `terraform -chdir=infra/terraform/<s> init -reconfigure -backend-config="bucket=medical-rag-tfstate-$ACC" -backend-config="region=ap-southeast-1"` |
| `make tunnel`: `SessionManagerPlugin is not found` | Plugin missing on the workstation | Install it there (0.2 would have shown it) |
| `make tunnel`: `TargetNotConnected` | The gateway's SSM agent is not registered yet | Wait until 3.3 prints READY |
| Tunnel open, `make ready` times out | The cluster SG does not allow the gateway, or VPC DNS is off | `aws eks describe-cluster --name anime --query cluster.resourcesVpcConfig`; the rule from `eks.tf` must be on the cluster SG |
| `make ready`: `x509 … not 127.0.0.1` | `tls-server-name` missing — update-kubeconfig run by hand | `make kubeconfig`; never run update-kubeconfig directly |
| `make ready`: `x509` naming Medical's hosts, or Medical's nodes appear | Medical's tunnel holds 6443, or `KUBECONFIG` not exported | `ss -ltnp 'sport = :6443'`; export `KUBECONFIG=$HOME/.kube/anime` |
| `make ready`: connection refused after working earlier | The SSM session of the tunnel ended | Restart `make tunnel` in window 2 |
| `kubectl`: `Unauthorized` | Shell identity is not the one that created the cluster | `aws sts get-caller-identity` must be the workstation's instance role |
| 3.3 never READY | cloud-init failed — usually the secret was missing a key at boot | Read `tail -40 /var/log/cloud-init-output.log` through `aws ssm send-command`; fix the secret; `terraform -chdir=infra/terraform/cluster apply -replace=aws_instance.wireguard` |
| 2.4 was re-run after `make infra` | The gateway still has the old server key | `terraform -chdir=infra/terraform/cluster apply -replace=aws_instance.wireguard`, then redo 4.4 |
| WireGuard app: no handshake | Wrong key pasted in 2.4, a cached old address, or UDP 51820 blocked | Check 2.4's lengths; `ipconfig /flushdns`; try another network |
| 5.1 prints `CHART LOOKUP FAILED` | Helm repo unreachable | Retry 5.1; never write `null` into the tfvars |
| `make bootstrap-plan`: API not reachable | Tunnel closed | Window 2: `make tunnel`; `make ready` must say `ok` |
| `root` is `Unknown` with `ComparisonError` | `target_revision` branch or `deploy/argocd/root` not pushed | Push; `kubectl -n argocd get application root -o jsonpath='{.status.conditions}'` |
| `make down` stops at "load-balancer resources remain" | An Application still self-heals, or the controller is gone | `kubectl -n argocd get applications -o jsonpath='{range .items[*]}{.metadata.name} {.spec.syncPolicy.automated}{"\n"}{end}'`; report before deleting anything by hand |
| `make down`: API not reachable | Tunnel closed, or the cluster never came up | Reopen the tunnel; for a cluster that never came up, `make infra-destroy` |
| `terraform destroy` hangs on the VPC | Something a controller created is still inside | `aws ec2 describe-network-interfaces --filters Name=vpc-id,Values=<vpc>`; report before deleting |

---

[README](README.md) · [Concepts](concepts.md) · [Design §3](../eks-sre-llmops-design.md#3-architecture) ·
[Design §8](../eks-sre-llmops-design.md#8-make-targets-and-teardown)
