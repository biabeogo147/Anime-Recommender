# Inputs of the shared stack. Only budget_email has no default; it goes in terraform.tfvars on the workstation.

variable "region" {
  description = "AWS region for every resource of this project."
  type        = string
  default     = "ap-southeast-1"
}

variable "project" {
  description = "Name prefix and value of the `project` tag, which the budget filters on."
  type        = string
  default     = "anime"
}

variable "owner" {
  description = "Value of the owner tag."
  type        = string
  default     = "devops-lab-user"
}

variable "parent_domain" {
  description = "The Route 53 zone Medical's shared stack owns. Anime only reads it and writes records under its own label."
  type        = string
  default     = "recruitai.io.vn"
}

variable "github_repository" {
  description = "owner/name of the repository whose main-branch workflow may push images."
  type        = string
  default     = "biabeogo147/Anime-Recommender"
}

variable "budget_email" {
  description = "Address that receives the budget alerts."
  type        = string
}

variable "monthly_budget_usd" {
  description = "Monthly budget; alerts fire at 50% and 100% of it (design §3: 50 and 100 USD)."
  type        = number
  default     = 100
}
