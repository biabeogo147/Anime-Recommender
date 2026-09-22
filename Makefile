# Every operation on AWS and on the cluster. Runs on the ops workstation only (it has terraform, kubectl, helm,
# aws, jq, wg, the Session Manager plugin); the Windows laptop never runs this file.
#
# Fresh environment (docs/terraform/guide.md):
#   make shared-plan  → make shared      once; only again when the shared stack changes
#   make plan         → make infra       VPC, EKS, nodes, gateway
#   make kubeconfig                      after every `make infra`
#   make tunnel                          in a SECOND window (tmux), left open
#   make bootstrap-plan → make bootstrap Argo CD and the root Application, through the tunnel
#   make down                            end of session, tunnel still open
#
# Each *-plan writes a plan file and prints its count; the apply target applies THAT file, with no prompt. So the
# number written down before applying is, by construction, the plan that is applied — criterion #1 (Terraform A7.2).

SHELL := /bin/bash
.ONESHELL:
.SHELLFLAGS := -euo pipefail -c

REGION     ?= ap-southeast-1
PROJECT    ?= anime
# The slo-* targets need no AWS at all — CI runs `make slo-check` with no credentials — so only they skip the check.
ifeq ($(filter-out slo-%,$(or $(MAKECMDGOALS),default)),)
ACCOUNT_ID := none
else
ACCOUNT_ID := $(shell aws sts get-caller-identity --query Account --output text 2>/dev/null)
endif
ifeq ($(ACCOUNT_ID),)
$(error cannot read the AWS account id: run this on the ops workstation, with its instance role)
endif
# State lives in Medical's bucket, under the anime/ prefix (each stack's key is in its versions.tf).
STATE_BUCKET := medical-rag-tfstate-$(ACCOUNT_ID)
BACKEND      := -backend-config="bucket=$(STATE_BUCKET)" -backend-config="region=$(REGION)"

TF_SHARED    := terraform -chdir=infra/terraform/shared
TF_CLUSTER   := terraform -chdir=infra/terraform/cluster
TF_BOOTSTRAP := terraform -chdir=infra/terraform/bootstrap
# -no-color: plan output goes through pipes and files, where ANSI codes would break every grep on "Plan:".
TF_PLAN      := plan -no-color -input=false

# A kubeconfig of its own, so Medical's ~/.kube/config is never rewritten by an Anime command. Exported, so every
# kubectl/helm run by make uses it; in your own shell, `export KUBECONFIG=$HOME/.kube/anime` (the guide does).
KUBECONFIG_FILE := $(HOME)/.kube/anime
export KUBECONFIG := $(KUBECONFIG_FILE)
# Medical's tunnel also uses 6443: run one at a time, or pass TUNNEL_PORT=6444 to BOTH `make kubeconfig` and
# `make tunnel`, every session (the port is written into the kubeconfig).
TUNNEL_PORT ?= 6443

# Terraform outputs are read inside recipes, never with $(shell): a failed $(shell) expands to an empty string
# silently, and the tunnel would start with `host=`. Inside a recipe `set -e` stops at the failure.
cluster_output = $(TF_CLUSTER) output -raw $(1)

.PHONY: shared-init shared-plan shared init plan infra kubeconfig tunnel ready bootstrap-init bootstrap-plan \
        bootstrap up vpn-config pins image apps loadtest-baseline loadtest-ramp loadtest-steady prom prom-range \
        rollout-status rollout promote-full slo-generate slo-check langfuse-obs down infra-destroy

# --- shared: survives every teardown -----------------------------------------------------------------------------
shared-init:
	$(TF_SHARED) init -input=false $(BACKEND)

shared-plan: shared-init
	$(TF_SHARED) $(TF_PLAN) -out=shared.tfplan | tee /tmp/anime-shared-plan.txt | grep -E '^(Plan:|No changes|Error)'

shared: shared-init
	$(TF_SHARED) apply -no-color -input=false shared.tfplan | tee /tmp/anime-shared-apply.txt | grep -E '^(Apply complete|Error)'

# --- cluster: destroyed by `make down` ---------------------------------------------------------------------------
init:
	$(TF_CLUSTER) init -input=false $(BACKEND)

plan: init
	$(TF_CLUSTER) $(TF_PLAN) -out=cluster.tfplan | tee /tmp/anime-cluster-plan.txt | grep -E '^(Plan:|No changes|Error)'

infra: init
	$(TF_CLUSTER) apply -no-color -input=false cluster.tfplan | tee /tmp/anime-cluster-apply.txt | grep -E '^(Apply complete|Error)'

# Write ~/.kube/anime for the TUNNEL. update-kubeconfig rewrites the whole cluster entry — server back to the private
# hostname, tls-server-name gone — so both are set again right after, every time (Terraform A3.4). Without the server
# line kubectl dials an address the workstation cannot reach and times out; without tls-server-name every command
# fails on a certificate-name mismatch, because 127.0.0.1 is not on AWS's certificate.
kubeconfig: init
	endpoint=$$($(call cluster_output,cluster_endpoint)); host=$${endpoint#https://}
	[ -n "$$host" ] || { echo "no cluster_endpoint output: has 'make infra' run?"; exit 1; }
	mkdir -p $(HOME)/.kube
	aws eks update-kubeconfig --region $(REGION) --name $(PROJECT) --kubeconfig $(KUBECONFIG_FILE) --alias $(PROJECT)
	arn=$$(aws eks describe-cluster --region $(REGION) --name $(PROJECT) --query cluster.arn --output text)
	kubectl config set-cluster "$$arn" --server=https://127.0.0.1:$(TUNNEL_PORT) --tls-server-name="$$host"
	chmod 600 $(KUBECONFIG_FILE)
	kubectl config view --minify --output jsonpath='{.clusters[0].cluster.server} {.clusters[0].cluster.tls-server-name}{"\n"}'

# The SSM agent on the GATEWAY opens the connection to the private endpoint; this window holds the local end. Leave it
# open; Ctrl-C closes the tunnel.
tunnel: init
	endpoint=$$($(call cluster_output,cluster_endpoint)); host=$${endpoint#https://}
	gateway=$$($(call cluster_output,wireguard_instance_id))
	[ -n "$$host" ] && [ -n "$$gateway" ] || { echo "missing outputs: has 'make infra' run?"; exit 1; }
	aws ssm start-session --region $(REGION) --target "$$gateway" \
	  --document-name AWS-StartPortForwardingSessionToRemoteHost \
	  --parameters host="$$host",portNumber=443,localPortNumber=$(TUNNEL_PORT)

# The first check of every session: the API answers through the tunnel. Stage 1 is not usable until this prints ok,
# whatever criterion #1 says (Terraform A7.3).
ready:
	kubectl get --raw /readyz; echo

# --- bootstrap: Argo CD, through the tunnel ----------------------------------------------------------------------
bootstrap-init:
	$(TF_BOOTSTRAP) init -input=false $(BACKEND)

bootstrap-plan: bootstrap-init
	kubectl get --raw /readyz >/dev/null || { echo "API not reachable: is 'make tunnel' open?"; exit 1; }
	$(TF_BOOTSTRAP) $(TF_PLAN) -var kubeconfig_path=$(KUBECONFIG_FILE) -out=bootstrap.tfplan \
	  | tee /tmp/anime-bootstrap-plan.txt | grep -E '^(Plan:|No changes|Error)'

bootstrap: bootstrap-init
	$(TF_BOOTSTRAP) apply -no-color -input=false bootstrap.tfplan | tee /tmp/anime-bootstrap-apply.txt | grep -E '^(Apply complete|Error)'

# There is no one-shot `up`: the tunnel has to stay open in its own window. This prints the order instead.
up:
	@echo "make plan && make infra && make kubeconfig; then 'make tunnel' in window 2; then make bootstrap-plan && make bootstrap"

# --- VPN profile ------------------------------------------------------------------------------------------------
# Prints the laptop profile. The gateway's PUBLIC key is read from the running gateway over SSM (`wg show`), so the
# workstation never fetches the gateway's private key. One operator: the secret holds a single operatorPublicKey,
# and the profile always uses the first client address. The endpoint is a name, so a rebuild needs no profile change.
vpn-config: init
	gateway=$$($(call cluster_output,wireguard_instance_id))
	cmd=$$(aws ssm send-command --region $(REGION) --instance-ids "$$gateway" --document-name AWS-RunShellScript \
	  --parameters 'commands=["wg show wg0 public-key"]' --query Command.CommandId --output text)
	aws ssm wait command-executed --region $(REGION) --command-id "$$cmd" --instance-id "$$gateway"
	server_pub=$$(aws ssm get-command-invocation --region $(REGION) --command-id "$$cmd" --instance-id "$$gateway" \
	  --query StandardOutputContent --output text | tr -d '[:space:]')
	[ $${#server_pub} -eq 44 ] || { echo "could not read the gateway's public key: has it finished booting?"; exit 1; }
	address=$$($(call cluster_output,wireguard_client_address)); endpoint=$$($(call cluster_output,vpn_endpoint))
	vpc=$$($(call cluster_output,vpc_cidr))
	printf '%s\n' '---- copy from here ----' '[Interface]' 'PrivateKey = <keep the key your WireGuard app generated>' \
	  "Address = $$address" '' '[Peer]' "PublicKey = $$server_pub" "Endpoint = $$endpoint" "AllowedIPs = $$vpc" \
	  'PersistentKeepalive = 25' '---- to here ----'

# --- stage 2: values Git needs but only this account knows -------------------------------------------------------
# Every PIN_ME in deploy/argocd/root/values.yaml is one of these (the image digests come from `make image`). They are not
# secrets; they are reported once and committed from the laptop, so that what runs is always what Git says.
pins: shared-init
	@helm repo add eks https://aws.github.io/eks-charts --force-update >/dev/null
	helm repo add external-secrets https://charts.external-secrets.io --force-update >/dev/null
	helm repo add external-dns https://kubernetes-sigs.github.io/external-dns/ --force-update >/dev/null
	helm repo add prometheus-community https://prometheus-community.github.io/helm-charts --force-update >/dev/null
	helm repo add argo https://argoproj.github.io/argo-helm --force-update >/dev/null
	helm repo add kedacore https://kedacore.github.io/charts --force-update >/dev/null
	helm repo add autoscaler https://kubernetes.github.io/autoscaler --force-update >/dev/null
	helm repo add grafana https://grafana.github.io/helm-charts --force-update >/dev/null
	helm repo add open-telemetry https://open-telemetry.github.io/opentelemetry-helm-charts --force-update >/dev/null
	helm repo update >/dev/null
	echo "account_id          $(ACCOUNT_ID)"
	echo "registry            $(ACCOUNT_ID).dkr.ecr.$(REGION).amazonaws.com"
	echo "certificate_arn     $$($(TF_SHARED) output -raw certificate_arn)"
	for c in eks/aws-load-balancer-controller external-secrets/external-secrets external-dns/external-dns \
	         prometheus-community/kube-prometheus-stack argo/argo-rollouts kedacore/keda autoscaler/cluster-autoscaler \
	         grafana/tempo open-telemetry/opentelemetry-collector; do
	  printf '%-45s %s\n' "$$c" "$$(helm search repo $$c -o json | jq -r '.[0].version')"
	done
	# The Cluster Autoscaler's image must be the cluster's own minor version: the newest patch of it.
	minor=$$(sed -n '/variable "kubernetes_version"/,/^}/s/.*default *= *"\([0-9.]*\)".*/\1/p' infra/terraform/cluster/variables.tf)
	printf '%-45s %s\n' "cluster-autoscaler image (k8s $$minor)" \
	  "$$(curl -fsS 'https://api.github.com/repos/kubernetes/autoscaler/releases?per_page=100' \
	      | jq -r --arg p "cluster-autoscaler-$$minor." '[.[].tag_name | select(startswith($$p))][0] // "LOOKUP-FAILED" | sub("cluster-autoscaler-"; "v")' \
	      || echo LOOKUP-FAILED)"
	# The Sloth image for make slo-generate / slo-check (SLOTH_IMAGE in this file): its latest release tag.
	printf '%-45s %s\n' "ghcr.io/slok/sloth" \
	  "$$(curl -fsS https://api.github.com/repos/slok/sloth/releases/latest | jq -r .tag_name || echo LOOKUP-FAILED)"
	# GitHub Actions used by .github/workflows, resolved from tag to COMMIT SHA once (unauthenticated API: 60 calls/h).
	for a in actions/checkout@v4 docker/setup-buildx-action@v3 docker/build-push-action@v6 aquasecurity/trivy-action@v0.35.0 \
	         github/codeql-action@v4 aws-actions/configure-aws-credentials@v4 aws-actions/amazon-ecr-login@v2 \
	         sigstore/cosign-installer@v3 anchore/sbom-action@v0 actions/upload-artifact@v4; do
	  printf '%-45s %s\n' "$$a" "$$(curl -fsS https://api.github.com/repos/$${a%@*}/commits/$${a#*@} | jq -r .sha || echo LOOKUP-FAILED)"
	done

# Build both images on the workstation and push them by digest — the stand-in for CI until stage 3. The Hugging Face
# token reaches the index build as a BuildKit secret, so it never becomes a layer (docs/evidence/local.md). Prints the two
# digests to report; they go into deploy/charts/anime-{api,ui}/values.yaml.
REGISTRY = $(ACCOUNT_ID).dkr.ecr.$(REGION).amazonaws.com
image:
	tag=$$(git rev-parse --short=12 HEAD)
	aws ecr get-login-password --region $(REGION) | docker login --username AWS --password-stdin $(REGISTRY) >/dev/null
	export HF_TOKEN=$$(aws secretsmanager get-secret-value --region $(REGION) --secret-id $(PROJECT)/llm \
	  --query SecretString --output text | jq -r .HF_TOKEN)
	[ -n "$$HF_TOKEN" ] && [ "$$HF_TOKEN" != null ] || { echo "anime/llm has no HF_TOKEN (guide step 2.5)"; exit 1; }
	for svc in api ui; do
	  docker buildx build --progress=plain -f services/$$svc/Dockerfile --target runtime \
	    --secret id=hf_token,env=HF_TOKEN --provenance=false --sbom=false \
	    --tag $(REGISTRY)/$(PROJECT)-$$svc:$$tag --metadata-file /tmp/anime-$$svc-meta.json --push .
	done
	# The digest ECR itself reports for the pushed tag — the one a pull by digest matches — not the build tool's.
	for svc in api ui; do
	  d=$$(aws ecr describe-images --region $(REGION) --repository-name $(PROJECT)-$$svc --image-ids imageTag=$$tag \
	    --query 'imageDetails[0].imageDigest' --output text)
	  printf '%-4s digest: %s\n' $$svc "$$d"
	done

# --- stage 4: load tests and the queries that read them -----------------------------------------------------------
# k6 runs in a container on the workstation (docker is there; nothing is installed). Its end-of-test summary is saved in
# ~/anime-evidence, because metrics die with the cluster and evidence is captured at the time (Load A7.2). Each run
# records the digest of the k6 image it used next to its own summary (<name>-k6-image.txt). A rerun of the same
# target overwrites that run's files, so copy them aside first if the earlier run is still wanted.
K6_IMAGE ?= grafana/k6:latest
# --user: the image runs as its own uid (12345), which could not write into a directory the workstation user owns — k6
# would print "failed to handle the end-of-test summary" and still exit 0, leaving no summary file.
K6 = docker run --rm -i --network host --user "$$(id -u):$$(id -g)" \
  -v $(CURDIR)/loadtest/k6:/scripts:ro -v $(HOME)/anime-evidence:/out \
  -e BASE_URL -e TARGET_REQUESTS -e RATE_PER_MINUTE -e MAX_RPS -e MAX_VUS -e HOLD -e RPS -e DURATION \
  $(K6_IMAGE)

loadtest-baseline loadtest-ramp loadtest-steady:
	mkdir -p $(HOME)/anime-evidence
	name=$(patsubst loadtest-%,%,$@)
	docker pull -q $(K6_IMAGE) >/dev/null && docker image inspect $(K6_IMAGE) --format '{{index .RepoDigests 0}}' \
	  > $(HOME)/anime-evidence/$$name-k6-image.txt
	date -u +%Y-%m-%dT%H:%M:%SZ > $(HOME)/anime-evidence/$$name.start
	# The end of the window is written however k6 stops — a failed threshold, an error, or Ctrl-C on a long steady run
	# — because every range query in the guides reads START and END from these two files.
	trap 'date -u +%Y-%m-%dT%H:%M:%SZ > $(HOME)/anime-evidence/$$name.end
	  echo "window: $$(cat $(HOME)/anime-evidence/$$name.start) → $$(cat $(HOME)/anime-evidence/$$name.end)"' EXIT
	# The ramp also writes every data point with its timestamp: the summary has only the run's TOTAL of dropped
	# iterations, and capacity needs to know whether the first one came before the knee or after it.
	$(K6) run --summary-export /out/$$name-summary.json $(if $(filter loadtest-ramp,$@),--out csv=/out/ramp-points.csv) \
	  /scripts/$$name.js

# One PromQL expression, evaluated inside the Prometheus pod with promtool — no port-forward, no extra tool.
#   make -s prom Q='sum(up{pod=~"anime-api.*"})'            instant, now
#   make -s prom Q='…' AT=2026-09-22T10:00:00Z               instant, at a time
#   make -s prom-range Q='…' START=… END=… STEP=30s           a range, for the knee
PROM_POD := prometheus-kube-prometheus-stack-prometheus-0
PROM = kubectl -n monitoring exec $(PROM_POD) -c prometheus -- promtool query
prom:
	$(PROM) instant $(if $(AT),--time=$(AT)) http://localhost:9090 '$(Q)'
prom-range:
	$(PROM) range --start=$(START) --end=$(END) --step=$(or $(STEP),30s) http://localhost:9090 '$(Q)'

# Sync and health of every Application, by name.
apps:
	@kubectl -n argocd get applications -o custom-columns='NAME:.metadata.name,WAVE:.metadata.annotations.argocd\.argoproj\.io/sync-wave,SYNC:.status.sync.status,HEALTH:.status.health.status,REVISION:.status.sync.revision'

# --- stage 5: the api's Rollout, read without the kubectl plugin ----------------------------------------------------
# One line for the Rollout — phase, step, the canary's weight on the ALB, both hashes — then every measurement of the
# newest AnalysisRun with the hashes it was given. The evidence is the measured values, not the outcome (design §6, #8).
rollout-status:
	@kubectl -n anime get rollout anime-api -o json | jq -r '"\(now | todate) phase=\(.status.phase) step=\(.status.currentStepIndex // "-")/\(.spec.strategy.canary.steps | length) canary-weight=\(.status.canary.weights.canary.weight // 0)% stable=\(.status.stableRS) latest=\(.status.currentPodHash) abort=\(.status.abort // false) \(.status.message // "")"'
rollout: rollout-status
	@run=$$(kubectl -n anime get analysisrun --sort-by=.metadata.creationTimestamp -o name | tail -1)
	[ -n "$$run" ] || { echo "no AnalysisRun yet"; exit 0; }
	kubectl -n anime get "$$run" -o json | jq -r '"\(.metadata.name) \(.status.phase // "Running") args: \([.spec.args[] | "\(.name)=\(.value)"] | join(" "))",
	  (.status.metricResults[]? | "  \(.name) \(.phase): " + ([.measurements[]? | "\(.phase)=\(.value // "-")"] | join(" ")))'

# Promote to 100% with NO further steps and NO analysis — what `kubectl argo rollouts promote --full` does. Used only for
# the api's MODE switches (gemini ↔ fake), which are not releases under test and have no traffic to be judged on, and
# for the SLO alert drill, whose fault must reach ALL traffic at once (design §4.3). Never to push a release past an
# analysis that stopped it (Delivery A7.2).
promote-full:
	kubectl -n anime patch rollout anime-api --subresource=status --type merge -p '{"status":{"promoteFull":true}}'

# --- stage 8: what Langfuse holds for one trace id ----------------------------------------------------------------
# Through Langfuse's public API, with the project's own keys read from Secrets Manager on this workstation only. Prints
# the HTTP status first: 200 with no observations is "not there"; 401 is keys or region, never "absent". The v2
# observations endpoint replaces the v1 traces one, which Langfuse stops serving on 2026-11-16 (to be verified against
# the Langfuse version in use).   make -s langfuse-obs ID=<trace id>
langfuse-obs:
	lf=$$(sed -n 's/^  otlpEndpoint: *"\{0,1\}\(https:\/\/[^/"]*\).*/\1/p' deploy/argocd/root/values.yaml)
	[ -n "$$lf" ] || { echo "no Langfuse host in deploy/argocd/root/values.yaml"; exit 1; }
	[ -n "$(ID)" ] || { echo "usage: make -s langfuse-obs ID=<trace id>"; exit 1; }
	auth=$$(aws secretsmanager get-secret-value --region $(REGION) --secret-id anime/langfuse --query SecretString \
	  --output text | jq -r '"\(.LANGFUSE_PUBLIC_KEY):\(.LANGFUSE_SECRET_KEY)"')
	code=$$(curl -s -o /tmp/langfuse-obs.json -w '%{http_code}' -u "$$auth" \
	  "$$lf/api/public/v2/observations?traceId=$(ID)&fromStartTime=$$(date -u -d '-1 day' +%FT%TZ)")
	echo "langfuse http $$code"
	if [ "$$code" = 200 ]; then
	  jq -r '"observations: \(.data | length)",
	    (.data[] | "  \(.name)  type=\(.type)  model=\(.providedModelName // .model // "-")  usage=\(.usageDetails // .usage // {} | tostring)")' \
	    /tmp/langfuse-obs.json
	else cat /tmp/langfuse-obs.json; echo; fi

# --- stage 6: the SLO rules, generated from the Sloth spec -------------------------------------------------------
# Sloth runs in a container (nothing installed), pinned by version: a different Sloth may write different rules, and
# the committed file would stop matching for no reason anyone changed. `make pins` prints the current release.
#   slo-generate  writes deploy/slo/generated/anime-api.yaml from deploy/slo/anime-api.sloth.yaml
#   slo-check     regenerates into a temporary file and fails on any difference — what CI runs (SLO A4.1)
# --default-slo-period=28d: without it Sloth uses 30 days and the rules carry the 30-day multipliers (design §4.3).
SLOTH_IMAGE ?= ghcr.io/slok/sloth:PIN_ME
SLOTH = docker run --rm -i --user "$$(id -u):$$(id -g)" -v $(CURDIR)/deploy/slo:/slo $(SLOTH_IMAGE) \
  generate --default-slo-period=28d -i /slo/anime-api.sloth.yaml
slo-generate:
	mkdir -p deploy/slo/generated
	$(SLOTH) -o /slo/generated/anime-api.yaml
	grep -c 'record:' deploy/slo/generated/anime-api.yaml | sed 's/$$/ recording rules/'
	grep -c 'alert:' deploy/slo/generated/anime-api.yaml | sed 's/$$/ alert rules/'
slo-check:
	# Until stage 4 has measured T there is nothing to generate, and CI must stay green for stages 3 to 5.
	if grep -q 'PIN_ME_T' deploy/slo/anime-api.sloth.yaml; then echo "T not pinned yet: SLO check skipped"; exit 0; fi
	tmp=$$(mktemp -d); trap 'rm -rf "$$tmp"' EXIT
	cp deploy/slo/anime-api.sloth.yaml "$$tmp/"
	docker run --rm -i --user "$$(id -u):$$(id -g)" -v "$$tmp":/slo $(SLOTH_IMAGE) \
	  generate --default-slo-period=28d -i /slo/anime-api.sloth.yaml -o /slo/anime-api.yaml
	# Kept outside the temporary directory: CI uploads it when this check fails, so the regenerated file can be
	# committed without running Sloth anywhere else (docs/slo/guide.md, section 0).
	mkdir -p slo-regenerated && cp "$$tmp/anime-api.yaml" slo-regenerated/
	[ -f deploy/slo/generated/anime-api.yaml ] || { echo "deploy/slo/generated/anime-api.yaml is missing"; exit 1; }
	diff -u deploy/slo/generated/anime-api.yaml "$$tmp/anime-api.yaml" && echo "SLO rules match the spec"

# --- teardown: tunnel must be open -------------------------------------------------------------------------------
# Load balancers, their target groups and security groups, and EBS volumes are created by controllers inside the
# cluster; Terraform does not know them, and the VPC cannot be destroyed while they exist. In this order (design §8):
#   1. turn off automated sync on EVERY Application — otherwise Argo CD re-creates what is deleted next, within seconds;
#   2. delete every Ingress (five from stage 2) and wait until nothing tagged for this cluster by the controller is left;
#   3. delete the Applications (children carry the resources-finalizer from stage 2, so their workloads go too), then
#      every PVC, and wait until no CSI volume tagged project=anime is left;
#   4. destroy the cluster stack; only once that succeeded, delete the bootstrap state — its objects died with the
#      cluster, its state would not. The shared stack is never touched.
LB_LEFT = aws resourcegroupstaggingapi get-resources --region $(REGION) \
  --resource-type-filters elasticloadbalancing:loadbalancer elasticloadbalancing:targetgroup ec2:security-group \
  --tag-filters Key=elbv2.k8s.aws/cluster,Values=$(PROJECT) --query 'length(ResourceTagMappingList)' --output json
# Alias (A) records under anime.* other than vpn.anime, which Terraform owns and destroys itself. `--output json` in all
# three: the text formatter applies --query page by page, and a multi-page answer would print several numbers.
DNS_LEFT = aws route53 list-resource-record-sets --output json --hosted-zone-id \
  $$(aws route53 list-hosted-zones-by-name --dns-name recruitai.io.vn --output text \
      --query "HostedZones[?Name=='recruitai.io.vn.' && !Config.PrivateZone].Id | [0]") \
  --query "length(ResourceRecordSets[?Type=='A' && AliasTarget && ends_with(Name,'$(PROJECT).recruitai.io.vn.')])"
VOL_LEFT = aws ec2 describe-volumes --region $(REGION) --query 'length(Volumes)' --output json \
  --filters Name=tag:project,Values=$(PROJECT) Name=tag-key,Values=ebs.csi.aws.com/cluster
# Cancel an Application's running sync: turning `automated` off does not stop an operation already in progress or in
# retry backoff, which could re-create an Ingress after it was deleted.
STOP_OPS = for a in $$(kubectl -n argocd get applications -o name); do \
    ph=$$(kubectl -n argocd get "$$a" -o jsonpath='{.status.operationState.phase}'); \
    [ "$$ph" = Running ] && kubectl -n argocd patch "$$a" --type merge -p '{"status":{"operationState":{"phase":"Terminating"}}}' || true; \
    kubectl -n argocd get "$$a" -o jsonpath='{.operation}' | grep -q . && kubectl -n argocd patch "$$a" --type json -p '[{"op":"remove","path":"/operation"}]' || true; \
  done

down: init
	kubectl get --raw /readyz >/dev/null || { echo "API not reachable: open 'make tunnel' first (or see the guide: make infra-destroy)"; exit 1; }
	if kubectl get crd applications.argoproj.io >/dev/null 2>&1; then
	  # The root FIRST: while it self-heals, it would put `automated` back on every child it renders within seconds.
	  kubectl -n argocd patch application root --type merge -p '{"spec":{"syncPolicy":{"automated":null}}}' || true
	  for a in $$(kubectl -n argocd get applications -o name); do
	    kubectl -n argocd patch "$$a" --type merge -p '{"spec":{"syncPolicy":{"automated":null}}}'
	  done
	  $(STOP_OPS)
	  for i in $$(seq 30); do
	    run=$$(kubectl -n argocd get applications -o json | jq '[.items[] | select(.status.operationState.phase == "Running" or .status.operationState.phase == "Terminating")] | length')
	    [ "$$run" = 0 ] && break; echo "$$run sync operation(s) still running, waiting"; sleep 5
	  done
	  # A root that was mid-walk may have created later-wave children, with `automated` on, after the loop above.
	  for a in $$(kubectl -n argocd get applications -o name); do
	    kubectl -n argocd patch "$$a" --type merge -p '{"spec":{"syncPolicy":{"automated":null}}}'
	  done
	  left=$$(kubectl -n argocd get applications -o json | jq '[.items[] | select(.spec.syncPolicy.automated != null)] | length')
	  [ "$$left" = 0 ] || { echo "$$left Application(s) still self-heal; not deleting anything"; exit 1; }
	fi
	kubectl delete ingress --all --all-namespaces --wait=true --timeout=10m
	for i in $$(seq 60); do n=$$($(LB_LEFT)); [ "$$n" = 0 ] && break; echo "$$n load-balancer resource(s) left, waiting"; sleep 10; done
	[ "$$($(LB_LEFT))" = 0 ] || { echo "load-balancer resources remain; not destroying the VPC"; exit 1; }
	# external-dns (still running) removes the records of the deleted Ingresses at its next loop. Wait for that before
	# deleting it, or alias records in Medical's zone would keep pointing at load balancers that no longer exist.
	for i in $$(seq 30); do n=$$($(DNS_LEFT)); [ "$$n" = 0 ] && break; echo "$$n alias record(s) left, waiting"; sleep 10; done
	[ "$$($(DNS_LEFT))" = 0 ] || echo "WARNING: alias records under $(PROJECT).* remain; check Route 53 after the teardown"
	if kubectl get crd applications.argoproj.io >/dev/null 2>&1; then
	  kubectl -n argocd delete applications --all --timeout=10m
	fi
	kubectl delete pvc --all --all-namespaces --timeout=15m
	for i in $$(seq 60); do n=$$($(VOL_LEFT)); [ "$$n" = 0 ] && break; echo "$$n EBS volume(s) left, waiting"; sleep 10; done
	[ "$$($(VOL_LEFT))" = 0 ] || { echo "EBS volumes remain; not destroying the cluster"; exit 1; }
	$(MAKE) infra-destroy
	aws s3 rm s3://$(STATE_BUCKET)/anime/bootstrap/terraform.tfstate

infra-destroy: init
	$(TF_CLUSTER) destroy
