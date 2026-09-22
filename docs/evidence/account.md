# Account check — 2026-09-22

What the AWS account allows, checked before stage 1. Account `242834061265` (shared with Medical), region
`ap-southeast-1`, as IAM user `devops-lab-user`, from the laptop's AWS CLI 2.36.23. Every figure below was read on
this date. Only one command created anything: the Spot launch, which was deleted a minute later.

## Plan and limits

| Check | Command | Result |
|---|---|---|
| Account plan | `aws freetier get-account-plan-state` | `FREE`, `ACTIVE`; **91.64 USD** credit left; plan expires 2027-02-13 |
| EKS reachable | `aws eks list-clusters` | `{"clusters": []}`: the API answers, no cluster yet |
| EKS on the Free plan | [AWS: supported services](https://docs.aws.amazon.com/accounts/latest/reference/supported-services-sign-up-new.html) | "Amazon Elastic Kubernetes Service" is listed among the Free plan's services, with Elastic Load Balancing, ECR, VPC, Secrets Manager, Route 53 and ACM |
| Kubernetes versions in standard support | `aws eks describe-cluster-versions --version-status STANDARD_SUPPORT` | `1.34`, `1.35`, `1.36`: the pin `1.36` is offered |
| Spot vCPU quota (L-34B43A08) | `aws service-quotas get-service-quota` | `32` |
| On-Demand standard vCPU quota (L-1216C47A) | `aws service-quotas get-service-quota` | `16` |

## Instance types

`aws ec2 describe-instance-types --filters Name=free-tier-eligible,Values=true` lists the only types the Free plan
launches here:

| Type | vCPU | Memory (MiB) |
|---|---|---|
| c7i-flex.large | 2 | 4096 |
| **m7i-flex.large** | 2 | **8192** |
| t3.micro | 2 | 1024 |
| t3.small | 2 | 2048 |
| t4g.micro | 2 | 1024 |
| t4g.small | 2 | 2048 |
| t8i.micro | 2 | 1024 |
| t8i.small | 2 | 2048 |

The four types first planned for the node group, by `FreeTierEligible`: `t3.large False`, `t3a.large False`,
`m5.large False`, `m6i.large False`. Medical's instances in the same account are `m7i-flex.large` (three nodes) and
`t3.small` (the workstation and the WireGuard gateway), all eligible.

**A dry run is not a check on this plan.** `aws ec2 run-instances --dry-run` returned `DryRunOperation` ("Request
would have succeeded") for all four ineligible types, On-Demand and Spot alike, and for the eligible ones. It proves
IAM permission, not what the plan will launch.

## A real Spot launch

| Step | Result |
|---|---|
| Launch | `run-instances` with `m7i-flex.large`, `--instance-market-options MarketType=spot`, AMI `ami-095f155a67469a548` (Amazon Linux 2023), a private subnet of Medical's VPC, no public address, tags `Name=anime-spot-test`, `Project=anime` (the guide's version of this test uses the lowercase cost tag `project`, and the ops workstation's own subnet) |
| Instance | `i-0180b4fe00747decd`, lifecycle `spot`, `running` at 04:01:52 UTC |
| Spot request | `sir-zcjqq9gg`: `active`, `fulfilled`, "Your Spot request is fulfilled." |
| Clean-up | instance `terminated`; request `cancelled`; no instance tagged `Project=anime` left |

## What changed because of this

- `node_instance_types` is `["m7i-flex.large"]` (`infra/terraform/cluster/variables.tf`). It is the only eligible
  2 vCPU / 8 GiB type. `c7i-flex.large` is left out, because one node group needs one size.
- Terraform guide step 0.3 checks eligibility instead of dry-running.
- The credit is a risk of its own (design §10): it is shared with Medical, and the Free plan closes the account when
  it is spent.
