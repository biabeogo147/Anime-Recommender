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

variable "enabled_stages" {
  # Which build stages the root renders, e.g. ["gitops"], then ["gitops", "cicd", ...]. Switching a stage on is a change
  # to terraform.tfvars and `make bootstrap-plan && make bootstrap` — not a commit — so the whole repository can sit in
  # Git while the cluster is built one stage at a time. Empty: the root renders nothing.
  type    = list(string)
  default = []
}

# The api's mode, an OPERATOR switch like enabled_stages: `fake` for the capacity run and every drill, `gemini` for the
# baseline and normal traffic. Changing either changes the pod template, which is a new version: a rolling update until
# stage 5, a canary after it — which is exactly how the drills are started (docs/delivery/guide.md).
variable "api_llm_provider" {
  type    = string
  default = "gemini"
  validation {
    condition     = contains(["gemini", "fake"], var.api_llm_provider)
    error_message = "api_llm_provider is gemini or fake."
  }
}

variable "api_fault_rate" {
  # Read ONLY by the fake provider: on a gemini version it injects nothing (Delivery A8.2). The root refuses the
  # combination instead of letting a drill "pass" on zero faults.
  type    = string
  default = "0"
  # A value the api cannot parse would crash every pod at import (config.py reads it with float()), so it is refused here.
  validation {
    condition     = can(tonumber(var.api_fault_rate)) && try(tonumber(var.api_fault_rate) >= 0 && tonumber(var.api_fault_rate) <= 1, false)
    error_message = "api_fault_rate is a number from 0 to 1, as a string, e.g. \"0.2\"."
  }
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
          path           = "deploy/argocd/root" # a small chart: one Application per component of each live stage
          helm = {
            valuesObject = {
              stages         = var.enabled_stages
              targetRevision = var.target_revision # every in-repo child follows the same branch as the root
              repoURL        = var.repo_url        # and the same repository
              api = {
                provider  = var.api_llm_provider
                faultRate = var.api_fault_rate
              }
            }
          }
        }
        destination = {
          server    = "https://kubernetes.default.svc"
          namespace = "argocd"
        }
        syncPolicy = {
          automated = {
            prune    = true # a stage switched off, or a template removed, removes its Applications
            selfHeal = true # a hand edit is put back to what Git says
            # Automated sync otherwise refuses to prune EVERYTHING, so switching the last stage off would leave its
            # Applications in place.
            allowEmpty = true
          }
          retry = { limit = 10, backoff = { duration = "10s", factor = 2, maxDuration = "3m" } }
        }
      }
    }
  })]

  depends_on = [helm_release.argocd]
}
