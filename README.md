# AWS EKS Infrastructure with Karpenter & KEDA

This repository contains Terraform infrastructure code for deploying a production-ready Amazon EKS cluster with advanced autoscaling capabilities using Karpenter and KEDA, integrated with ArgoCD for GitOps-based application deployment.

## 🏗️ Architecture Overview

This infrastructure deploys:
- **Amazon EKS Cluster** (v1.31) with managed node groups
- **Karpenter** for intelligent node provisioning and scaling
- **KEDA** for event-driven horizontal pod autoscaling
- **ArgoCD** for GitOps continuous deployment
- **VPC** with public/private subnets across multiple AZs
- **ECR Repository** for container image storage
- **IAM Roles & Policies** with least privilege access
- **EBS CSI Driver** for persistent storage

## 🚀 Key Features

### Karpenter Integration
- **Spot Instance Support**: Cost-optimized node provisioning using EC2 Spot instances
- **Multi-AZ Deployment**: Automatic node distribution across availability zones
- **Custom EC2NodeClass**: Optimized Amazon Linux 2 AMI configuration
- **Smart Scheduling**: Automatic node scaling based on pod requirements

### KEDA Integration
- **Event-Driven Autoscaling**: Scale workloads based on external metrics
- **Multiple Trigger Sources**: Support for various scaling triggers
- **Custom Resource Definitions**: ScaledObjects and ScaledJobs for fine-grained control

### GitOps with ArgoCD
- **Automated Deployment**: Continuous deployment from Git repository
- **Self-Healing**: Automatic drift detection and correction
- **Secure Git Access**: SSH key-based repository authentication

## 📋 Prerequisites

- AWS CLI configured with appropriate permissions
- Terraform >= 1.0
- kubectl
- Helm 3.x
- SSH key for Git repository access (placed as `terraform-deploy-key.txt`)

## 🛠️ Deployment

### 1. Clone Repository
```bash
git clone <repository-url>
cd <repository-name>
```

### 2. Configure Variables
Create a `terraform.tfvars` file with your configuration:

```hcl
region = {
  region = "us-east-1"
}

vpc = {
  vpc_eks = {
    cidr = "10.0.0.0/16"
    enable_nat_gateway = true
    single_nat_gateway = true
  }
}

eks = {
  poc = {
    cluster_endpoint_public_access = true
  }
}

eks_namespace = {
  "argocd" = {}
  "exam-app" = {}
  "keda" = {}
}

helm = {
  helm = {
    karpenter = {
      repository = "oci://public.ecr.aws/karpenter"
      chart = "karpenter"
      version = "1.0.0"
      namespace = "kube-system"
    }
    argocd = {
      repository = "https://argoproj.github.io/argo-helm"
      chart = "argo-cd"
      namespace = "argocd"
    }
    keda = {
      repository = "https://kedacore.github.io/charts"
      chart = "keda"
      namespace = "keda"
    }
  }
}

secret_manager = {
  mysql-credentials = {
    secret_string = jsonencode({
      username = "admin"
      password = "your-secure-password"
    })
  }
}
```

### 3. Deploy Infrastructure
```bash
# Initialize Terraform
terraform init

# Plan deployment
terraform plan

# Apply configuration
terraform apply
```

### 4. Configure kubectl
```bash
aws eks update-kubeconfig --region us-east-1 --name poc-us-east-1-eks
```

## 🔧 Components

### Karpenter Configuration
- **Node Pool**: Configured for spot instances with t3.medium, t3.large, t3.xlarge
- **Disruption Policy**: Optimized for cost with empty node consolidation
- **Security**: Dedicated IAM roles with minimal required permissions
- **Storage**: Automatic EBS volume provisioning

### KEDA Setup
- **Namespace**: Dedicated `keda` namespace
- **Operators**: KEDA operator and metrics server
- **Scalers**: Ready for various event sources (SQS, CloudWatch, etc.)

### ArgoCD Integration
- **Repository**: Connected to `poc_app` repository via SSH
- **Auto-sync**: Enabled with pruning and self-healing
- **Target**: Deploys applications to `exam-app` namespace

## 📊 Monitoring & Observability

- **CloudWatch Integration**: EKS cluster logging enabled
- **Metrics Server**: Installed for HPA functionality
- **Resource Tagging**: Comprehensive tagging strategy for cost allocation

## 🔒 Security Features

- **IAM Roles**: Service-specific roles with minimal permissions
- **Network Security**: Private subnets for worker nodes
- **Encryption**: EBS volumes encrypted at rest
- **Pod Security**: SecurityContext configurations
- **Secret Management**: AWS Secrets Manager integration

## 🧹 Cleanup

The infrastructure includes automated cleanup procedures:

```bash
terraform destroy
```

**Note**: The cleanup process includes scripts to handle Kubernetes finalizers and stuck resources.

## 📁 Repository Structure

```
.
├── main.tf                 # Main Terraform configuration
├── variables.tf           # Variable definitions
├── terraform.tfvars      # Variable values (create this)
├── helm/                 # Helm chart configurations
├── terraform-deploy-key.txt  # SSH key for Git access
└── README.md
```

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Test thoroughly
5. Submit a pull request

## 📝 License

This project is licensed under the MIT License - see the LICENSE file for details.

## ⚠️ Important Notes

- **Cost Optimization**: Uses spot instances for significant cost savings
- **High Availability**: Multi-AZ deployment for resilience
- **Scalability**: Karpenter and KEDA provide automatic scaling
- **GitOps Ready**: Integrated ArgoCD for continuous deployment
- **Production Ready**: Includes security best practices and monitoring

For questions or support, please open an issue in this repository.
