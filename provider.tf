terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "2.12.1"  # Use stable version instead of pre-release
    }
    kubernetes = {
      source = "hashicorp/kubernetes"
      version = "2.36.0"
    }
    kubectl = {
      source  = "gavinbunney/kubectl"
      version = ">= 1.14.0"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.4.0"
    }
  }
}
# Configure the AWS Provider
provider "aws" {
  region = var.region
}
data "aws_eks_cluster_auth" "this" {
  name = module.eks["poc"].cluster_name
}
# aws eks update-kubeconfig --region eu-north-1 --name exam-en1-eks
provider "kubernetes" {
  host                   = module.eks["poc"].cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks["poc"].cluster_certificate_authority_data)
  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args        = ["eks", "get-token", "--cluster-name", module.eks["poc"].cluster_name]
  }
}

# Configure Helm provider
provider "helm" {
  kubernetes {
    host                   = module.eks["poc"].cluster_endpoint
    cluster_ca_certificate = base64decode(module.eks["poc"].cluster_certificate_authority_data)
    exec {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      args = [
        "eks",
        "get-token",
        "--cluster-name",
        module.eks["poc"].cluster_name,
        "--region",
        var.region
      ]
    }
  }
}

provider "kubectl" {
  host                   = module.eks["poc"].cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks["poc"].cluster_certificate_authority_data)
  load_config_file       = false
  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args        = ["eks", "get-token", "--cluster-name", module.eks["poc"].cluster_name]
  }
}

