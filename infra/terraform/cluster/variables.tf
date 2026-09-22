# Inputs of the cluster stack. All have defaults; override one for a run with `-var`, or in terraform.tfvars.

variable "region" {
  type    = string
  default = "ap-southeast-1"
}

variable "project" {
  type    = string
  default = "anime"
}

variable "owner" {
  type    = string
  default = "devops-lab-user"
}

variable "parent_domain" {
  description = "Medical's Route 53 zone. Only the vpn.anime record is written into it by this stack."
  type        = string
  default     = "recruitai.io.vn"
}

variable "vpc_cidr" {
  # Must not overlap Medical's VPC (10.10.0.0/16), the ops VPC (10.20.0.0/24) or either WireGuard range, or a
  # laptop with both VPN profiles on — or a future peering — would route to the wrong place.
  type    = string
  default = "10.30.0.0/16"
}

variable "wireguard_cidr" {
  # Medical's VPN uses 10.99.0.0/24; a different range lets one laptop keep both profiles.
  description = "Address range of VPN clients. Must not overlap the VPC."
  type        = string
  default     = "10.98.0.0/24"
}

variable "kubernetes_version" {
  # The newest version in STANDARD support at build time, pinned exactly (design §3). Step 0 of the guide lists
  # what EKS offers today; change this default in Git if the list says otherwise, so the pin stays visible.
  description = "EKS minor version, e.g. 1.36."
  type        = string
  default     = "1.36"
}

variable "node_instance_types" {
  # The account is on the AWS Free plan, which launches only free-tier-eligible types; m7i-flex.large is the only
  # eligible 2 vCPU / 8 GiB one, and it runs as Spot (checked 2026-09-22, docs/evidence/account.md). c7i-flex.large is
  # eligible too but left out: it has 4 GiB, and the Cluster Autoscaler simulates a new node from one template, so
  # the types of a group must be the same size. The cost is one Spot pool per zone instead of four: a shortage is
  # likelier to leave the group short (Terraform concepts §6); the fallback is the same type On-Demand, also eligible.
  # Guide step 0.3 checks eligibility; replace the list only with types it reports eligible.
  description = "Spot instance types for the managed node group."
  type        = list(string)
  default     = ["m7i-flex.large"]
}

variable "wireguard_instance_type" {
  description = "The gateway only relays packets and one SSM session; the smallest general type is enough."
  type        = string
  default     = "t3.small"
}
