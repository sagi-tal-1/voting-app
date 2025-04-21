data "aws_availability_zones" "available" {}
data "aws_caller_identity" "current" {}
data "aws_ecrpublic_authorization_token" "token" {
  provider = aws.use1
}
locals {

  name          = "sagi.stambolsky"
  azs           = slice(data.aws_availability_zones.available.names, 0, 2)
  region_prefix = "us-east-1"
  cluster_name  = "poc-${local.region_prefix}-eks"
  private_subnet_ids = module.vpc["vpc_eks"].private_subnets

  tags = {
    Name      = "sagi.stambolsky"
    Objective = "Candidate"
    Owner     = "sagi stambolsky"
  }

  karpenter_values = yamlencode({
    rbac = {
      create = true
    }
    serviceAccount = {
      create = true
      name   = "karpenter"
      annotations = {
        "eks.amazonaws.com/role-arn" = aws_iam_role.karpenter_controller.arn
      }
    }
    logLevel = "debug"
    settings = {
      aws = {
        clusterName     = module.eks["poc"].cluster_name
        clusterEndpoint = module.eks["poc"].cluster_endpoint
        defaultInstanceProfile = aws_iam_instance_profile.karpenter.name
      }
    }
    controller = {
      resources = {
        requests = {
          cpu    = "500m"
          memory = "512Mi"
        }
        limits = {
          cpu    = "500m"
          memory = "512Mi"
        }
      }
    }
  })
}
data "aws_iam_policy" "ebs_csi_policy" {
  arn = "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
}

module "irsa-ebs-csi" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-assumable-role-with-oidc"
  version = "5.39.0"

  create_role                   = true
  role_name                     = "AmazonEKSTFEBSCSIRole-${module.eks["poc"].cluster_name}"
  provider_url                  = module.eks["poc"].oidc_provider
  role_policy_arns              = [data.aws_iam_policy.ebs_csi_policy.arn]
  oidc_fully_qualified_subjects = ["system:serviceaccount:kube-system:ebs-csi-controller-sa"]
}
resource "aws_iam_role" "vpc_cni" {
  name               = "${local.name}-vpc-cni"
  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "${module.eks["poc"].oidc_provider_arn}"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "${module.eks["poc"].oidc_provider}:sub": "system:serviceaccount:kube-system:aws-node"
        }
      }
    }
  ]
}
EOF
}



resource "aws_iam_role_policy_attachment" "vpc_cni" {
  role       = aws_iam_role.vpc_cni.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"

}

module "vpc" {
  for_each = var.vpc
  source   = "terraform-aws-modules/vpc/aws"
  version  = "5.19.0"

  # Details
  name            = "${each.key}-${local.region_prefix}-vpc"
  cidr            = lookup(each.value, "cidr", "10.0.0.0/16")
  azs             = lookup(each.value, "azs", local.azs)
  private_subnets = [for k, v in local.azs : cidrsubnet(each.value.cidr, 8, k)]
  public_subnets  = [for k, v in local.azs : cidrsubnet(each.value.cidr, 8, k + 4)]
  # database_subnets                   = lookup(each.value,"database_subnets",null)
  # create_database_subnet_group       = lookup(each.value,"create_database_subnet_group",null)
  # create_database_subnet_route_table = lookup(each.value,"create_database_subnet_route_table",null)
  # create_database_internet_gateway_route = true
  # create_database_nat_gateway_route = true
  # NAT Gateways - Outbound Communication
  enable_nat_gateway = lookup(each.value, "enable_nat_gateway", true)
  single_nat_gateway = lookup(each.value, "single_nat_gateway", true)


  # DNS Parameters in VPC
  enable_dns_hostnames = lookup(each.value, "enable_dns_hostnames", true)
  enable_dns_support   = lookup(each.value, "enable_dns_support", true)
  # Additional tags for the VPC
  tags     = lookup(each.value, "tags", local.tags)
  vpc_tags = lookup(each.value, "vpc_tags", {})

  # Additional tags
  # Additional tags for the public subnets
  public_subnet_tags = {
    "kubernetes.io/role/elb" = 1
  }
  # Additional tags for the private subnets
  private_subnet_tags = {
    "kubernetes.io/role/internal-elb" = 1
    "kubernetes.io/role"              = "private"
    "karpenter.sh/discovery"          = local.cluster_name
    "kubernetes.io/cluster/${local.cluster_name}" = "owned"
  }
  # Additional tags for the database subnets
  #   database_subnet_tags = {
  #     Name = local.name
  #   }
  # Instances launched into the Public subnet should be assigned a public IP address. Specify true to indicate that instances launched into the subnet should be assigned a public IP address
  #   map_public_ip_on_launch = true
}
module "ecr" {
  source                            = "terraform-aws-modules/ecr/aws"
  version                           = "2.3.1"
  repository_name                   = local.name
  repository_read_write_access_arns = [data.aws_caller_identity.current.arn]
  create_lifecycle_policy           = true
  repository_lifecycle_policy = jsonencode({
    rules = [
      {
        rulePriority = 1,
        description  = "Keep last 30 images",
        selection = {
          tagStatus     = "tagged",
          tagPrefixList = ["v"],
          countType     = "imageCountMoreThan",
          countNumber   = 30
        },
        action = {
          type = "expire"
        }
      }
    ]
  })
}
module "eks" {
  for_each = var.eks
  source                                   = "terraform-aws-modules/eks/aws"
  version                                  = "20.33.1"
  cluster_name                             = local.cluster_name
  cluster_version                          = "1.31"
  cluster_endpoint_public_access           = lookup(each.value, "cluster_endpoint_public_access", true)
  enable_cluster_creator_admin_permissions = lookup(each.value, "enable_cluster_creator_admin_permissions ", true)

  cluster_security_group_tags = {
    "karpenter.sh/discovery" = local.cluster_name
  }

  node_security_group_tags = {
    "karpenter.sh/discovery" = local.cluster_name
  }

  # EKS Addons
  cluster_addons = {
    coredns = {
      most_recent                 = true
      resolve_conflicts_on_update = "OVERWRITE"
    }
    eks-pod-identity-agent = {
      most_recent                 = true
      resolve_conflicts_on_update = "OVERWRITE"
    }
    kube-proxy = {
      most_recent                 = true
      resolve_conflicts_on_update = "OVERWRITE"
    }
    vpc-cni = {
      service_account_role_arn    = aws_iam_role.vpc_cni.arn
      most_recent                 = true
      resolve_conflicts_on_update = "OVERWRITE"
    }

    # metric-server = {
    #   service_account_role_arn    = aws_iam_role.vpc_cni.arn
    #   most_recent                 = true
    #   resolve_conflicts_on_update = "OVERWRITE"
    # }
    aws-ebs-csi-driver = {
      service_account_role_arn    = module.irsa-ebs-csi.iam_role_arn
      resolve_conflicts_on_update = "OVERWRITE"
      most_recent                 = true
    }
  }

  vpc_id     = module.vpc["vpc_eks"].vpc_id
  subnet_ids = module.vpc["vpc_eks"].private_subnets

  eks_managed_node_groups = {
    karpenter = {
      # Starting on 1.30, AL2023 is the default AMI type for EKS managed node groups
      instance_types = ["t3.medium"]

      min_size = 1
      max_size = 4
      # This value is ignored after the initial creation
      # https://github.com/bryantbiggs/eks-desired-size-hack
      desired_size = 2
      # Add taints to ensure only system pods land here

      taints = [
        {
          key    = "CriticalAddonsOnly"
          value  = "true"
          effect = "NO_SCHEDULE"
        }
      ]

      # This is not required - demonstrates how to pass additional configuration to nodeadm
      # Ref https://awslabs.github.io/amazon-eks-ami/nodeadm/doc/api/
      cloudinit_pre_nodeadm = [
        {
          content_type = "application/node.eks.aws"
          content      = <<-EOT
            ---
            apiVersion: node.eks.aws/v1alpha1
            kind: NodeConfig
            spec:
              kubelet:
                config:
                  shutdownGracePeriod: 30s
                  featureGates:
                    DisableKubeletCloudCredentialProviders: true
          EOT
        }
      ]
    }
  }

  tags = local.tags
}

resource "kubernetes_namespace" "this" {
  for_each = var.eks_namespace
  metadata {
    annotations = lookup(each.value, "annotations", {})
    labels      = lookup(each.value, "labels", {})
    name        = each.key
  }
  depends_on = [
    module.eks,
    null_resource.update_kubeconfig
  ]

}

resource "kubernetes_secret_v1" "this" {
  for_each = var.eks_secret
  metadata {
    name      = each.key
    namespace = lookup(each.value, "namespace", "default")
    labels    = lookup(each.value, "labels", {})
  }
  depends_on = [
    kubernetes_namespace.this,
    null_resource.update_kubeconfig
  ]


}
################################################################################
# Karpenter Module
################################################################################
module "karpenter" {
  source  = "terraform-aws-modules/eks/aws//modules/karpenter"
  version = "~> 20.35.0"

  cluster_name           = module.eks["poc"].cluster_name
  irsa_oidc_provider_arn = module.eks["poc"].oidc_provider_arn

  # Enable required features
  enable_v1_permissions           = true
  enable_pod_identity             = true
  create_pod_identity_association = true

  # Use existing IAM role from iam_karpenter.tf
  create_iam_role = false # Don't create new role

  # Instance profile settings
  create_instance_profile = false

  # Set the namespace
  namespace = "kube-system"

  # Tags
  tags = local.tags
}

resource "null_resource" "update_kubeconfig" {
  provisioner "local-exec" {
    command = "aws eks update-kubeconfig --region ${lookup(var.region, "region", "us-east-1")} --name ${module.eks["poc"].cluster_name} && kubectl get nodes"
  }

  depends_on = [module.eks]
}

resource "aws_iam_policy" "karpenter_node_subnet_discovery" {
  name        = "KarpenterNodeSubnetDiscovery-${module.eks["poc"].cluster_name}"
  description = "Allow Karpenter nodes to discover and query subnet information"
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ec2:DescribeSubnets",
          "ec2:DescribeVpcs",
          "ec2:DescribeAvailabilityZones"
        ]
        Resource = "*"
      }
    ]
  })

  tags = local.tags
}

resource "aws_iam_role_policy_attachment" "karpenter_node_subnet_discovery_attachment" {
  policy_arn = aws_iam_policy.karpenter_node_subnet_discovery.arn
  role       = aws_iam_role.karpenter_node.name
}



# And update your helm_release resource to use the existing values.yaml:
resource "helm_release" "this" {
  for_each = var.helm

  name                = each.key
  namespace           = "kube-system"  # Explicitly set to kube-system
  create_namespace    = true
  repository          = each.value.repository
  repository_username = data.aws_ecrpublic_authorization_token.token.user_name
  repository_password = data.aws_ecrpublic_authorization_token.token.password
  chart               = each.value.chart
  version             = each.value.version
  values              = try(each.value.values, [])

  force_update    = true
  wait           = true
  wait_for_jobs  = true
  cleanup_on_fail = true
  atomic         = true

  dynamic "set" {
    for_each = each.key == "karpenter" ? [1] : []
    content {
      name  = "controller.env[0].name"
      value = "CLUSTER_NAME"
    }
  }

  dynamic "set" {
    for_each = each.key == "karpenter" ? [1] : []
    content {
      name  = "controller.env[0].value"
      value = module.eks["poc"].cluster_name
    }
  }

  dynamic "set" {
    for_each = each.key == "karpenter" ? [1] : []
    content {
      name  = "settings.aws.defaultInstanceProfile"
      value = aws_iam_instance_profile.karpenter.name
    }
  }

  dynamic "set" {
    for_each = each.key == "karpenter" ? [1] : []
    content {
      name  = "settings.aws.interruptionQueueName"
      value = module.eks["poc"].cluster_name
    }
  }

  dynamic "set" {
    for_each = each.key == "karpenter" ? [1] : []
    content {
      name  = "serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
      value = aws_iam_role.karpenter_controller.arn
    }
  }

  dynamic "set" {
    for_each = each.key == "karpenter" ? [1] : []
    content {
      name  = "crds.enabled"
      value = "true"
    }
  }

  dynamic "set" {
    for_each = each.key == "karpenter" ? [1] : []
    content {
      name  = "crds.skipUpdate"
      value = "false"
    }
  }

  depends_on = [module.eks, module.karpenter, kubernetes_namespace.this, null_resource.update_kubeconfig]

  lifecycle {
    replace_triggered_by = [null_resource.update_kubeconfig]
  }
}

# EC2NodeClass
resource "kubectl_manifest" "karpenter_ec2nodeclass" {
  yaml_body = <<-YAML
  apiVersion: karpenter.k8s.aws/v1
  kind: EC2NodeClass
  metadata:
    name: default
  spec:
    amiFamily: AL2
    role: ${aws_iam_role.karpenter_node.name}
    subnetSelectorTerms:
      - id: ${local.private_subnet_ids[0]}
      - id: ${local.private_subnet_ids[1]}
    securityGroupSelectorTerms:
      - tags:
          karpenter.sh/discovery: ${local.cluster_name}
    amiSelectorTerms:
      - tags:
          "aws-marketplace/amazon-eks-optimized-ami": "true"
          "kubernetes.io/cluster/${module.eks["poc"].cluster_name}": "owned"
    tags:
      karpenter.sh/discovery: ${module.eks["poc"].cluster_name}
      Name: karpenter-node-${local.cluster_name}
      Owner: ${local.tags["Owner"]}
    metadataOptions:
      httpEndpoint: enabled
      httpProtocolIPv6: disabled
      httpPutResponseHopLimit: 2
      httpTokens: required
  YAML

  depends_on = [
    helm_release.this["karpenter"],
    aws_iam_role.karpenter_node,
    aws_iam_instance_profile.karpenter,
    null_resource.update_kubeconfig
  ]
}

# NodePool
resource "kubectl_manifest" "karpenter_nodepool" {
  yaml_body = <<-YAML
  apiVersion: karpenter.sh/v1
  kind: NodePool
  metadata:
    name: default
  spec:
    template:
      spec:
        requirements:
          - key: karpenter.sh/capacity-type
            operator: In
            values: ["spot"]
          - key: kubernetes.io/arch
            operator: In
            values: ["amd64"]
          - key: node.kubernetes.io/instance-type
            operator: In
            values: ["t3.medium", "t3.large", "t3.xlarge"]
          - key: topology.kubernetes.io/zone
            operator: In
            values: ${jsonencode(local.azs)}
        nodeClassRef:
          apiVersion: karpenter.k8s.aws/v1
          kind: EC2NodeClass
          name: default
          group: karpenter.k8s.aws
    limits:
      cpu: "20"
      memory: "100Gi"
    disruption:
      consolidationPolicy: WhenEmpty
      consolidateAfter: 30s
      expireAfter: "720h"
  YAML

  depends_on = [
    kubectl_manifest.karpenter_ec2nodeclass,
    helm_release.this["karpenter"],
    null_resource.update_kubeconfig
  ]
}

resource "null_resource" "verify_karpenter" {
  provisioner "local-exec" {
    command = <<-EOT
      echo "Waiting for Karpenter pod to be ready..."
      kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=karpenter -n kube-system --timeout=300s
      
      echo "Checking Karpenter service account..."
      kubectl get serviceaccount karpenter -n kube-system -o yaml
      
      echo "Verifying IAM role configuration..."
      aws iam get-role --role-name ${aws_iam_role.karpenter_controller.name}
      
      echo "Checking Karpenter logs..."
      kubectl logs -n kube-system -l app.kubernetes.io/name=karpenter -c controller --tail=50
      
      echo "Verifying subnet discovery..."
      aws ec2 describe-subnets \
        --filters "Name=tag:karpenter.sh/discovery,Values=${module.eks["poc"].cluster_name}" \
        --query 'Subnets[*].{ID:SubnetId,Tags:Tags}'

      echo "Checking Karpenter events..."
      kubectl get events -n kube-system --field-selector involvedObject.name=karpenter
    EOT
  }

  depends_on = [
    helm_release.this["karpenter"],
    aws_iam_role.karpenter_controller,
    aws_iam_role_policy_attachment.karpenter_controller_policy
  ]
}
