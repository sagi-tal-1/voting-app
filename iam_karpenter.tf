# Local variables for IRSA policies
locals {
  irsa_policies = {
    additional = jsonencode({
      Version = "2012-10-17"
      Statement = [
        {
          Effect = "Allow"
          Action = [
            "iam:CreateInstanceProfile",
            "iam:DeleteInstanceProfile",
            "iam:GetInstanceProfile",
            "iam:ListInstanceProfiles",
            "iam:AddRoleToInstanceProfile",
            "iam:RemoveRoleFromInstanceProfile",
            "iam:ListInstanceProfilesForRole",
            "iam:TagInstanceProfile",
            "iam:PassRole"
          ]
          Resource = "*" # Changed to allow all resources temporarily for testing
        },
        {
          Effect = "Allow"
          Action = [
            "iam:CreateRole",
            "iam:DeleteRole",
            "iam:GetRole",
            "iam:ListRoles",
            "iam:TagRole",
            "iam:UpdateRole",
            "iam:UpdateAssumeRolePolicy"
          ]
          Resource = [
            "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/KarpenterNodeRole-*",
            "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/${module.eks["poc"].cluster_name}*"
          ]
        }
      ]
    })
  }
}

# Karpenter Controller IAM Role
resource "aws_iam_role" "karpenter_controller" {
  name = "KarpenterController-${module.eks["poc"].cluster_name}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Federated = module.eks["poc"].oidc_provider_arn
        }
        Action = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringEquals = {
            "${module.eks["poc"].oidc_provider}:aud" : "sts.amazonaws.com",
            "${module.eks["poc"].oidc_provider}:sub" : "system:serviceaccount:kube-system:karpenter"
          }
        }
      }
    ]
  })

  tags = local.tags
}

# Create separate policy resource
resource "aws_iam_policy" "karpenter_controller" {
  name        = "KarpenterController-${module.eks["poc"].cluster_name}"
  description = "Policy for Karpenter Controller"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ec2:CreateLaunchTemplate",
          "ec2:CreateFleet",
          "ec2:RunInstances",
          "ec2:CreateTags",
          "ec2:TerminateInstances",
          "ec2:DescribeLaunchTemplates",
          "ec2:DescribeInstances",
          "ec2:DescribeSecurityGroups",
          "ec2:DescribeSubnets",
          "ec2:DescribeInstanceTypes",
          "ec2:DescribeInstanceTypeOfferings",
          "ec2:DescribeAvailabilityZones",
          "ec2:DescribeSpotPriceHistory",
          "ec2:DescribeImages",
          "iam:PassRole",
          "iam:GetInstanceProfile",
          "iam:AddRoleToInstanceProfile",
          "ssm:GetParameter",
          "pricing:GetProducts"
        ]
        Resource = "*"
      },
      {
        Effect   = "Allow"
        Action   = "eks:DescribeCluster"
        Resource = "arn:aws:eks:${var.region.region}:${data.aws_caller_identity.current.account_id}:cluster/${module.eks["poc"].cluster_name}"
      }
    ]
  })

  tags = local.tags
}

# Attach the policy to the role
resource "aws_iam_role_policy_attachment" "karpenter_controller_policy" {
  role       = aws_iam_role.karpenter_controller.name
  policy_arn = aws_iam_policy.karpenter_controller.arn
}

# Karpenter Node IAM Role
resource "aws_iam_role" "karpenter_node" {
  name = "KarpenterNodeRole-${module.eks["poc"].cluster_name}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = local.tags
}

# Update Karpenter Node IAM Role policy attachments
resource "aws_iam_role_policy_attachment" "karpenter_node_policies" {
  for_each = {
    AmazonSSMManagedInstanceCore       = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
    AmazonEBSCSIDriverPolicy           = "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
    AmazonEC2ContainerRegistryReadOnly = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
    AmazonEKSWorkerNodePolicy          = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
  }

  role       = aws_iam_role.karpenter_node.name
  policy_arn = each.value
}

# Karpenter Node Instance Profile
resource "aws_iam_instance_profile" "karpenter" {
  name = "KarpenterNodeInstanceProfile-${module.eks["poc"].cluster_name}"
  role = aws_iam_role.karpenter_node.name

  tags = local.tags
}