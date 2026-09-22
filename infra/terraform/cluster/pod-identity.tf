# One IAM role per controller, bound to exactly one ServiceAccount through an EKS Pod Identity association. No
# access key anywhere, and no controller borrows the node's role (Terraform A5.1, A5.2).
#
# The namespace/ServiceAccount pairs below are a contract with the charts in deploy/argocd/ (stages 2, 5 and 7): a
# chart that names its ServiceAccount differently gets no credentials, and fails with an explicit "no credentials"
# error rather than silently using something else.

module "lb_controller_identity" {
  source  = "terraform-aws-modules/eks-pod-identity/aws"
  version = "~> 2.0"

  name                            = "${local.name}-aws-lb-controller"
  attach_aws_lb_controller_policy = true # the controller's published policy: ALBs, target groups, listeners

  associations = {
    this = {
      cluster_name    = module.eks.cluster_name
      namespace       = "kube-system"
      service_account = "aws-load-balancer-controller"
    }
  }
}

data "aws_kms_alias" "secretsmanager" {
  name = "alias/aws/secretsmanager" # exists once any secret in the region uses the default key — Medical's do
}

module "external_secrets_identity" {
  source  = "terraform-aws-modules/eks-pod-identity/aws"
  version = "~> 2.0"

  name                                  = "${local.name}-external-secrets"
  attach_external_secrets_policy        = true
  external_secrets_secrets_manager_arns = local.external_secret_arns # three named ARNs, NOT anime/*
  external_secrets_create_permission    = false                      # it reads; it never creates secrets
  external_secrets_ssm_parameter_arns   = []                         # no SSM parameters are read
  # Decrypt only with the AWS-managed Secrets Manager key; left empty, the module would allow kms:Decrypt on every key.
  external_secrets_kms_key_arns = [data.aws_kms_alias.secretsmanager.target_key_arn]
  # Inherent to the module and to External Secrets: ListSecrets/BatchGetSecretValue on "*" reveal secret NAMES and
  # metadata account-wide (Medical's included) — never values, which stay limited to the three ARNs above.

  associations = {
    this = {
      cluster_name    = module.eks.cluster_name
      namespace       = "external-secrets"
      service_account = "external-secrets"
    }
  }
}

module "ebs_csi_identity" {
  source  = "terraform-aws-modules/eks-pod-identity/aws"
  version = "~> 2.0"

  name                      = "${local.name}-ebs-csi"
  attach_aws_ebs_csi_policy = true
  # No `associations` here: the add-on in eks.tf creates the association itself, in the same step as the pods.
}

# Stage 7 installs the Cluster Autoscaler; its identity is created now so the node group and its permissions are
# defined in one place. Its writes (set desired capacity, terminate) are limited to groups tagged for THIS cluster;
# its describe calls cannot be scoped and read every group (design §3).
module "cluster_autoscaler_identity" {
  source  = "terraform-aws-modules/eks-pod-identity/aws"
  version = "~> 2.0"

  name                             = "${local.name}-cluster-autoscaler"
  attach_cluster_autoscaler_policy = true
  cluster_autoscaler_cluster_names = [module.eks.cluster_name]

  associations = {
    this = {
      cluster_name    = module.eks.cluster_name
      namespace       = "kube-system"
      service_account = "cluster-autoscaler"
    }
  }
}

# --- external-dns, written by hand: the module's policy cannot restrict record NAMES ----------------------------
# The zone belongs to Medical. external-dns may change records only if EVERY name in the change batch is under
# anime.recruitai.io.vn — a second, independent limit behind its own --domain-filter (Terraform A5.5).
data "aws_iam_policy_document" "external_dns" {
  statement {
    sid       = "ChangeOnlyAnimeNames"
    actions   = ["route53:ChangeResourceRecordSets"]
    resources = [data.aws_route53_zone.parent.arn]

    condition {
      # ForAllValues: every record name in the request must match one of these, or the whole call is denied.
      test     = "ForAllValues:StringLike"
      variable = "route53:ChangeResourceRecordSetsNormalizedRecordNames"
      values = [
        local.domain,        # anime.recruitai.io.vn itself (the UI)
        "*.${local.domain}", # api.anime, argocd.anime, ... and their ownership TXT records
        # The ownership TXT records of the bare `anime` name, in external-dns's newer format "<type>-<name>", fall
        # outside "*.anime"; named one by one so nothing else ending in "-anime" under Medical's zone matches
        # (design §3, to be verified in stage 2 against the real record names).
        "a-${local.domain}",
        "aaaa-${local.domain}",
        "cname-${local.domain}",
      ]
    }
  }

  statement {
    sid       = "ReadTheZone"
    actions   = ["route53:ListResourceRecordSets", "route53:ListTagsForResources"]
    resources = [data.aws_route53_zone.parent.arn]
  }

  statement {
    sid       = "FindZones"
    actions   = ["route53:ListHostedZones", "route53:ListHostedZonesByName"] # no resource-level scoping exists
    resources = ["*"]
  }
}

data "aws_iam_policy_document" "pod_identity_trust" {
  statement {
    actions = ["sts:AssumeRole", "sts:TagSession"] # Pod Identity needs both
    principals {
      type        = "Service"
      identifiers = ["pods.eks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "external_dns" {
  name               = "${local.name}-external-dns"
  assume_role_policy = data.aws_iam_policy_document.pod_identity_trust.json
}

resource "aws_iam_role_policy" "external_dns" {
  name   = "anime-names-only"
  role   = aws_iam_role.external_dns.id
  policy = data.aws_iam_policy_document.external_dns.json
}

resource "aws_eks_pod_identity_association" "external_dns" {
  cluster_name    = module.eks.cluster_name
  namespace       = "external-dns"
  service_account = "external-dns"
  role_arn        = aws_iam_role.external_dns.arn
}

# --- Argo Rollouts (stage 5): read-only, to VERIFY what the load balancer controller did ------------------------
# With --aws-verify-target-group the controller checks, before each step proceeds and before the old stable is
# scaled down, that the ALB really has the weights it asked for and that the stable target group holds the new
# stable pods. Without it, the old pods are scaled away 30 s after promotion whether or not the target group has
# caught up — if the load balancer controller is slow or down, the api host then forwards to deleted pods
# (design §4.4). Describe calls cannot be scoped to resources; nothing here can change a load balancer.
data "aws_iam_policy_document" "argo_rollouts" {
  statement {
    sid = "VerifyTargetGroups"
    actions = [
      "elasticloadbalancing:DescribeLoadBalancers",
      "elasticloadbalancing:DescribeListeners",
      "elasticloadbalancing:DescribeRules",
      "elasticloadbalancing:DescribeTargetGroups",
      "elasticloadbalancing:DescribeTargetHealth",
      "elasticloadbalancing:DescribeTags",
    ]
    resources = ["*"]
  }
}

resource "aws_iam_role" "argo_rollouts" {
  name               = "${local.name}-argo-rollouts"
  assume_role_policy = data.aws_iam_policy_document.pod_identity_trust.json
}

resource "aws_iam_role_policy" "argo_rollouts" {
  name   = "verify-target-groups"
  role   = aws_iam_role.argo_rollouts.id
  policy = data.aws_iam_policy_document.argo_rollouts.json
}

resource "aws_eks_pod_identity_association" "argo_rollouts" {
  cluster_name    = module.eks.cluster_name
  namespace       = "argo-rollouts"
  service_account = "argo-rollouts" # the chart's default ServiceAccount name (delivery-controllers.yaml)
  role_arn        = aws_iam_role.argo_rollouts.arn
}
