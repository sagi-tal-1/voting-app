variable "vpc" {
  type = any
}
variable "eks" {
  type = any
}

variable "secret_manager" {
  type = any
}
variable "eks_storage_class" {
  type = any
}
variable "eks_secret_copy" {
  type = any
}
variable "eks_namespace" {
  type = any
}
variable "eks_secret" {
  type = any
}
variable "helm" {
  type = any
}
variable "eks_service_account" {
  type = any
}
variable "region" {
  type = string
  default = "us-east-1"
}

variable "cluster_name" {
  type    = string
  default = "poc-us-east-1-eks"
}

# variable "db_password" {
#   type        = string
#   sensitive   = true
# }
variable "control_plane_subnet_ids" {
  type = list(string)
  default = []
}

# variable "repository_username" {

#   type        = any
# }

# variable "repository_password" {

#   type        = any
# }
