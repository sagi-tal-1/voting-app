# VPC configuration variable
variable "vpc" {
  description = "VPC configuration map"
  type        = map(any)
}

# EKS configuration variable
variable "eks" {
  description = "EKS cluster configuration map"
  type        = map(any)
}

# EKS Namespace configuration
variable "eks_namespace" {
  description = "Kubernetes namespaces to create"
  type        = map(any)
}

# EKS Secret configuration
variable "eks_secret" {
  description = "Kubernetes secrets to create"
  type        = map(any)
}

# EKS Secret Copy configuration
variable "eks_secret_copy" {
  description = "Configuration for copying secrets"
  type        = map(any)
}

# AWS Secrets Manager configuration
variable "secret_manager" {
  description = "AWS Secrets Manager configuration"
  type        = map(any)
}

# EKS Service Account configuration
variable "eks_service_account" {
  description = "Kubernetes service account configuration"
  type        = map(any)
}

# EKS Storage Class configuration
variable "eks_storage_class" {
  description = "Kubernetes storage class configuration"
  type        = map(any)
}

# Region configuration
variable "region" {
  description = "AWS region configuration"
  type        = map(any)
}

# Helm release configuration
variable "helm" {
  description = "Helm release configuration"
  type        = map(any)
}
