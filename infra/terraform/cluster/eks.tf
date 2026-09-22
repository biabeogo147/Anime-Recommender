# The EKS cluster and its Spot node group, through the community module (v21 input names).
module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 21.0"

  name               = local.name
  kubernetes_version = var.kubernetes_version

  # STANDARD support only. EXTENDED would silently cost several times more per hour once the version ages out;
  # on STANDARD, AWS upgrades the control plane when support ends instead (AWS A2.2).
  upgrade_policy = {
    support_type = "STANDARD"
  }

  # The API server has NO public address. Not "public with an allowlist": an allowlist must be right every day,
  # and when it is wrong kubectl just times out like a dead cluster (Terraform A3.1). The private endpoint is
  # reached only through `make tunnel`.
  endpoint_public_access  = false
  endpoint_private_access = true

  # Access entries, not the aws-auth ConfigMap. The identity that runs `terraform apply` — the ops workstation's
  # instance role — becomes cluster admin; nothing else does.
  authentication_mode                      = "API"
  enable_cluster_creator_admin_permissions = true

  vpc_id                   = module.vpc.vpc_id
  subnet_ids               = module.vpc.private_subnets
  control_plane_subnet_ids = module.vpc.intra_subnets # the endpoint's ENIs, apart from nodes and ALBs

  # Nightly rebuilds: a control-plane log group that EKS re-creates after destroy makes the next apply fail with
  # ResourceAlreadyExists, and audit logs are billed daily; a customer KMS key would be created again every night.
  # Secrets in etcd are still encrypted with an AWS-owned key by EKS (AWS A6.4, to be verified).
  create_cloudwatch_log_group = false
  enabled_log_types           = []
  create_kms_key              = false
  encryption_config           = null

  # Provider default_tags do not reach the node group's launch template, so without these the Spot instances and their
  # volumes would carry no project tag and the budget would miss the largest cost line.
  tags = {
    project = var.project
    owner   = var.owner
    env     = "lab"
  }

  # The tunnel is opened by the SSM agent ON THE GATEWAY, not by the workstation, so it is the gateway that must be
  # allowed into the control plane on 443 (design §4.7, Terraform A3.5).
  security_group_additional_rules = {
    ingress_from_wireguard_gateway = {
      description              = "SSM port-forward from the WireGuard gateway to the private API endpoint"
      type                     = "ingress"
      protocol                 = "tcp"
      from_port                = 443
      to_port                  = 443
      source_security_group_id = aws_security_group.wireguard.id
    }
  }

  addons = {
    # These two must exist before the nodes join: without the CNI no pod gets an address, and without the Pod
    # Identity agent no controller gets AWS credentials.
    vpc-cni                = { before_compute = true }
    eks-pod-identity-agent = { before_compute = true }
    coredns                = {}
    kube-proxy             = {}
    # PersistentVolumes for Prometheus and friends. The Pod Identity association is created WITH the add-on, so its
    # controller never starts without credentials (a separate association could land after the pods, which then need a
    # restart). Every volume it creates is tagged project=anime: Terraform never sees these volumes, and `make down` finds the
    # leftovers by this tag before destroying the cluster (design §8) — Medical's volumes carry its own tag.
    aws-ebs-csi-driver = {
      pod_identity_association = [{
        role_arn        = module.ebs_csi_identity.iam_role_arn
        service_account = "ebs-csi-controller-sa"
      }]
      configuration_values = jsonencode({
        controller = { extraVolumeTags = { project = var.project } }
      })
    }
  }

  eks_managed_node_groups = {
    spot = {
      ami_type       = "AL2023_x86_64_STANDARD"
      capacity_type  = "SPOT"
      instance_types = var.node_instance_types

      # 2 to 4 (design §3). desired_size is only the starting point: the Cluster Autoscaler (stage 7) moves it, and
      # the module ignores later drift on it so Terraform does not fight the autoscaler.
      min_size     = 2
      max_size     = 4
      desired_size = 2

      # IMDSv2 with hop limit 1: the metadata service answers the node, not a container behind it, so ordinary pods
      # cannot borrow the node role. Pods on the host network (the VPC CNI itself) still can (Terraform A5.6).
      metadata_options = {
        http_endpoint               = "enabled"
        http_tokens                 = "required"
        http_put_response_hop_limit = 1
      }

      block_device_mappings = {
        root = {
          device_name = "/dev/xvda"
          ebs = {
            volume_size           = 30
            volume_type           = "gp3"
            encrypted             = true
            delete_on_termination = true
          }
        }
      }
    }
  }
}

output "cluster_name" {
  value = module.eks.cluster_name
}

# https://<id>.<gr>.<region>.eks.amazonaws.com — the name `make tunnel` forwards to and the name `tls-server-name`
# must carry, because the certificate is AWS's and cannot be reissued to include 127.0.0.1 (Terraform A3.4).
output "cluster_endpoint" {
  value = module.eks.cluster_endpoint
}

# The load balancer controller cannot discover VPC and region through IMDS with hop limit 1; stage 2 passes these.
output "region" {
  value = var.region
}

output "node_group_asg_names" {
  value = module.eks.eks_managed_node_groups_autoscaling_group_names
}
