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
  # Several types across two zones, so one Spot shortage does not empty the group (Terraform A4.1). All four are
  # 2 vCPU / 8 GiB: the Cluster Autoscaler simulates a new node from one template, so similar sizes matter.
  # Step 0 checks the account's plan accepts them; if not, replace the list here.
  description = "Spot instance types for the managed node group."
  type        = list(string)
  default     = ["t3.large", "t3a.large", "m5.large", "m6i.large"]
}

variable "wireguard_instance_type" {
  description = "The gateway only relays packets and one SSM session; the smallest general type is enough."
  type        = string
  default     = "t3.small"
}
