output "cluster_endpoint" {
  description = "Endpoint for EKS control plane"
  value       = module.eks["poc"].cluster_endpoint
}

output "cluster_security_group_id" {
  description = "Security group ID attached to the EKS cluster"
  value       = module.eks["poc"].cluster_security_group_id
}

output "cluster_name" {
  description = "Kubernetes Cluster Name"
  value       = module.eks["poc"].cluster_name
}

output "cluster_certificate_authority_data" {
  description = "Base64 encoded certificate data required to communicate with the cluster"
  value       = module.eks["poc"].cluster_certificate_authority_data
}

output "karpenter_controller_role_arn" {
  description = "ARN of the Karpenter controller role"
  value       = aws_iam_role.karpenter_controller.arn
}

output "karpenter_node_role_arn" {
  description = "ARN of the Karpenter node role"
  value       = aws_iam_role.karpenter_node.arn
}

output "karpenter_instance_profile_name" {
  description = "Name of the Karpenter instance profile"
  value       = aws_iam_instance_profile.karpenter.name
}

output "secret_manager_mysql_arn" {
  description = "ARN of the MySQL credentials secret"
  value       = aws_secretsmanager_secret.mysql.arn
  sensitive   = true
}

output "secret_manager_mysql_name" {
  description = "Name of the MySQL credentials secret"
  value       = aws_secretsmanager_secret.mysql.name
}

output "nlb_hostname" {
  description = "The hostname of the Network Load Balancer"
  value       = data.kubernetes_service.ingress_nginx.status.0.load_balancer.0.ingress.0.hostname
}

output "nlb_dns_name" {
  description = "The DNS name of the Network Load Balancer"
  value       = data.kubernetes_service.ingress_nginx.status.0.load_balancer.0.ingress.0.hostname
}

# Data source to get the NLB service information
data "kubernetes_service" "ingress_nginx" {
  metadata {
    name      = "ingress-nginx-controller"
    namespace = "ingress-nginx"
  }
  depends_on = [helm_release.this["ingress-nginx"]]
}
