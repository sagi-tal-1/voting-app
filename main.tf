data "aws_availability_zones" "available" {}
data "aws_caller_identity" "current" {}
data "aws_ecrpublic_authorization_token" "token" {

  
  provider = aws.use1
}
resource "null_resource" "create_karpenter_dir" {
  provisioner "local-exec" {
    command = "mkdir -p ${path.module}/helm/karpenter"
  }
}

locals {
  name               = "sagi.s"
  azs                = slice(data.aws_availability_zones.available.names, 0, 2)
  region_prefix      = "us-east-1"
  cluster_name       = "poc-${local.region_prefix}-eks"
  private_subnet_ids = module.vpc["vpc_eks"].private_subnets

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
      # Using camelCase format as required by Karpenter
      "clusterName"           = module.eks["poc"].cluster_name
      "clusterEndpoint"       = module.eks["poc"].cluster_endpoint
      "defaultInstanceProfile" = aws_iam_instance_profile.karpenter.name
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

  tags = {
    Name      = "sagi.s"
    Objective = "Candidate"
    Owner     = "sagi s"
  }
}

data "aws_iam_policy" "ebs_csi_policy" {
  arn = "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
}

# Create AWS Secrets Manager secret
resource "aws_secretsmanager_secret" "mysql" {
  name        = "mysql-credentials-${local.cluster_name}-${formatdate("YYYYMMDD-HHmmss", timestamp())}"
  description = "MySQL database credentials"
  tags        = local.tags
}

resource "aws_secretsmanager_secret_version" "mysql" {
  secret_id     = aws_secretsmanager_secret.mysql.id
  secret_string = lookup(var.secret_manager["mysql-credentials"], "secret_string", "{}")
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

  # NAT Gateways - Outbound Communication
  enable_nat_gateway = lookup(each.value, "enable_nat_gateway", true)
  single_nat_gateway = lookup(each.value, "single_nat_gateway", true)

  # DNS Parameters in VPC
  enable_dns_hostnames = lookup(each.value, "enable_dns_hostnames", true)
  enable_dns_support   = lookup(each.value, "enable_dns_support", true)

  # Additional tags for the VPC
  tags     = lookup(each.value, "tags", local.tags)
  vpc_tags = lookup(each.value, "vpc_tags", {})

  # Additional tags for the public subnets
  public_subnet_tags = {
    "kubernetes.io/role/elb" = 1
    Name = "Public Subnet"
  }

  # Additional tags for the private subnets
  private_subnet_tags = {
    "kubernetes.io/role/internal-elb"             = 1
    "kubernetes.io/role"                          = "private"
    "karpenter.sh/discovery"                      = local.cluster_name
    "kubernetes.io/cluster/${local.cluster_name}" = "owned"
    Name = "Private Subnet"
  }

  # Enable public IP on launch for public subnets
  map_public_ip_on_launch = true
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
  for_each                                 = var.eks
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
  for_each = {
    for k, v in var.eks_namespace : k => v
    if k != "kube-system" # Skip kube-system as it's created by default
  }
  
  metadata {
    annotations = lookup(each.value, "annotations", {})
    labels      = lookup(each.value, "labels", {})
    name        = each.key
  }

  lifecycle {
    ignore_changes = [
      metadata[0].annotations,
      metadata[0].labels
    ]
  }

  depends_on = [
    module.eks,
    null_resource.update_kubeconfig
  ]
}

# Explicitly wait for namespace deletion
resource "null_resource" "wait_for_namespace_deletion" {
  for_each = kubernetes_namespace.this

  triggers = {
    namespace_name = each.key
  }

  provisioner "local-exec" {
    when    = destroy
    command = <<-EOT
      kubectl wait --for=delete namespace/${each.key} --timeout=300s || true
    EOT
  }
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

  # Use existing IAM role
  create_iam_role = false
  # Instead of irsa_role_arn, rely on service account annotations or module defaults
  # The module should use aws_iam_role.karpenter_controller.arn via serviceAccount annotations

  # Instance profile settings
  create_instance_profile = true
  # The module will use aws_iam_instance_profile.karpenter.name internally

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

################################################################################
# helm_release Module
################################################################################
resource "helm_release" "this" {
  for_each = var.helm.helm

  name             = each.key
  namespace        = lookup(each.value, "namespace", "kube-system")
  create_namespace = lookup(each.value, "create_namespace", true)
  repository       = lookup(each.value, "repository", null)
  repository_username = lookup(each.value, "repository", "") == "oci://public.ecr.aws/karpenter" ? data.aws_ecrpublic_authorization_token.token.user_name : null
  repository_password = lookup(each.value, "repository", "") == "oci://public.ecr.aws/karpenter" ? data.aws_ecrpublic_authorization_token.token.password : null
  
  chart            = each.value.chart
  version          = lookup(each.value, "version", null)
  timeout          = lookup(each.value, "timeout", 300)

  values = concat(
    length(fileset("${path.module}/helm/${each.key}", "*.yaml")) > 0 ? [
      for file in fileset("${path.module}/helm/${each.key}", "*.yaml") :
      file("${path.module}/helm/${each.key}/${file}")
    ] : []
  )

  force_update    = true
  wait            = true
  wait_for_jobs   = true
  cleanup_on_fail = true
  atomic          = true
  replace         = true

  depends_on = [
    module.eks,
    module.karpenter,
    kubernetes_namespace.this,
    null_resource.update_kubeconfig
  ]

  lifecycle {
    ignore_changes = [
      values,
    ]
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





# Create ArgoCD repository secret
resource "kubernetes_secret" "argocd_repo" {
  metadata {
    name      = "repo-poc-app"
    namespace = "argocd"
    labels = {
      "argocd.argoproj.io/secret-type" = "repository"
    }
  }

  data = {
    type          = "git"
    url           = "git@github.com:emc19802/poc_app.git"
    name          = "poc-app"
    sshPrivateKey = file("${path.module}/terraform-deploy-key.txt")
  }

  type = "Opaque"

  depends_on = [
    kubernetes_namespace.this["argocd"]
  ]
}

# Update ArgoCD application to use the repository secret
resource "kubectl_manifest" "poc_app" {
  yaml_body = <<-YAML
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: poc-app
  namespace: argocd
spec:
  project: default
  source:
    repoURL: git@github.com:emc19802/poc_app.git
    targetRevision: HEAD
    path: voting-app-chart
  destination:
    server: https://kubernetes.default.svc
    namespace: exam-app
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
YAML

  depends_on = [
    module.eks,
    null_resource.update_kubeconfig,
    helm_release.this["argocd"],
    kubernetes_secret.argocd_repo
  ]
}


########################################################
resource "kubernetes_storage_class" "ebs" {
  metadata {
    name = "auto-ebs-sc"
    annotations = {
      "storageclass.kubernetes.io/is-default-class" = "true"
    }
  }
  storage_provisioner = "ebs.csi.aws.com"
  volume_binding_mode = "WaitForFirstConsumer"
  allow_volume_expansion = true
  reclaim_policy = "Delete"
  parameters = {
    type = "gp2"
    encrypted = "true"
  }
}


