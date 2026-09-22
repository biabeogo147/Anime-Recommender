# GitHub Actions reaches AWS with a short-lived OIDC token instead of a stored access key.

# One OIDC provider per issuer URL per account. If Medical (or anything else) already created GitHub's, a second
# create fails with EntityAlreadyExists; set create_github_oidc_provider = false and this stack reads it instead.
variable "create_github_oidc_provider" {
  description = "false when the account already has token.actions.githubusercontent.com as an OIDC provider."
  type        = bool
  default     = true
}

resource "aws_iam_openid_connect_provider" "github" {
  count          = var.create_github_oidc_provider ? 1 : 0
  url            = "https://token.actions.githubusercontent.com"
  client_id_list = ["sts.amazonaws.com"] # the audience GitHub's aws-actions/configure-aws-credentials asks for
}

data "aws_iam_openid_connect_provider" "github" {
  count = var.create_github_oidc_provider ? 0 : 1
  url   = "https://token.actions.githubusercontent.com"
}

locals {
  github_oidc_arn = var.create_github_oidc_provider ? aws_iam_openid_connect_provider.github[0].arn : data.aws_iam_openid_connect_provider.github[0].arn
}

data "aws_iam_policy_document" "ci_trust" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [local.github_oidc_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    # Repository AND branch, matched exactly. A condition naming only the repository would accept a workflow on any
    # branch — including one a contributor pushed — which is the difference between "our release pipeline" and
    # "anything that runs in our repository" (concepts §8). Pull requests get a different `sub`, so they cannot
    # assume this role either.
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["repo:${var.github_repository}:ref:refs/heads/main"]
    }
  }
}

resource "aws_iam_role" "ci" {
  name               = "${var.project}-ci"
  assume_role_policy = data.aws_iam_policy_document.ci_trust.json
}

# What CI may do once trusted: push to the two repositories and nothing else. It never talks to the cluster.
data "aws_iam_policy_document" "ci_push" {
  statement {
    sid       = "EcrLogin"
    actions   = ["ecr:GetAuthorizationToken"] # this action has no resource-level scoping in IAM
    resources = ["*"]
  }

  statement {
    sid = "PushAndSignTwoRepositories"
    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:InitiateLayerUpload",
      "ecr:UploadLayerPart",
      "ecr:CompleteLayerUpload",
      "ecr:PutImage",
      # cosign reads the manifest it signs and attaches signature/attestation artefacts next to it.
      "ecr:BatchGetImage",
      "ecr:GetDownloadUrlForLayer",
      "ecr:DescribeImages",
    ]
    resources = [for r in aws_ecr_repository.app : r.arn]
  }
}

resource "aws_iam_role_policy" "ci_push" {
  name   = "push-two-repositories"
  role   = aws_iam_role.ci.id
  policy = data.aws_iam_policy_document.ci_push.json
}

output "ci_role_arn" {
  value = aws_iam_role.ci.arn
}
