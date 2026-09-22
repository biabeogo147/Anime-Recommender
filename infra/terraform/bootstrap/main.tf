# Argo CD and the root app-of-apps — the last Terraform apply, and the only one that talks to Kubernetes.
#
# It is a separate stack because it CANNOT run in the same apply as the cluster: its providers connect to the API
# server, which has no address the workstation can reach until `make tunnel` is open, and the tunnel needs the gateway
# that the cluster apply is still creating (Terraform A6.1). So: make infra → make tunnel → make bootstrap.
#
# Its objects die with the cluster; its STATE does not. `make down` deletes this state, or the next bootstrap would
# plan against a cluster that no longer exists (Terraform A2.5).

terraform {
  required_version = ">= 1.11"

  required_providers {
    helm = {
      source  = "hashicorp/helm"
      version = "~> 3.0" # 3.x takes `kubernetes = { ... }` as an attribute, not a block
    }
  }

  backend "s3" {
    key          = "anime/bootstrap/terraform.tfstate"
    use_lockfile = true
    encrypt      = true
  }
}

variable "kubeconfig_path" {
  # Written by `make kubeconfig`: server https://127.0.0.1:6443 plus tls-server-name. Passed by make as an absolute path.
  type = string
}

variable "argocd_chart_version" {
  # Pinned. The guide looks up the current release once and writes it to terraform.tfvars; report it back so the pin
  # moves into this file.
  type = string
}

variable "argocd_apps_chart_version" {
  type = string
}

variable "repo_url" {
  type    = string
  default = "https://github.com/biabeogo147/Anime-Recommender.git" # public: Argo CD needs no credential
}

variable "target_revision" {
  # The branch Argo CD follows. `main` is what CI commits digests to; while building on another branch, set this to
  # that branch in terraform.tfvars and switch back after merging.
  type    = string
  default = "main"
}

provider "helm" {
  kubernetes = {
    config_path = var.kubeconfig_path
  }
}

resource "helm_release" "argocd" {
  name             = "argocd"
  namespace        = "argocd"
  create_namespace = true
  repository       = "https://argoproj.github.io/argo-helm"
  chart            = "argo-cd"
  version          = var.argocd_chart_version

  # The values live next to the Applications in Git, so what the UI's Ingress and the Application health check look
  # like is reviewable in one place.
  values = [file("${path.module}/../../../deploy/argocd/values/argocd.yaml")]

  wait    = true
  timeout = 600
}

# The root Application, created through the argocd-apps chart rather than a kubernetes_manifest: a manifest of kind
# Application cannot even be PLANNED before Argo CD's CRDs exist, and here they are created in the same apply.
resource "helm_release" "root" {
  name       = "root"
  namespace  = "argocd"
  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argocd-apps"
  version    = var.argocd_apps_chart_version

  values = [yamlencode({
    applications = {
      root = {
        namespace = "argocd"
        project   = "default"
        # No resources-finalizer: deleting root deletes only root, not every child and what they own.
        source = {
          repoURL        = var.repo_url
          targetRevision = var.target_revision
          path           = "deploy/argocd/apps" # one file per component; waves order them (stage 2)
        }
        destination = {
          server    = "https://kubernetes.default.svc"
          namespace = "argocd"
        }
        syncPolicy = {
          automated = {
            prune    = true # a file removed from apps/ removes its Application
            selfHeal = true # a hand edit is put back to what Git says
          }
        }
      }
    }
  })]

  depends_on = [helm_release.argocd]
}
