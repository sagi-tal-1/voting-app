# Karpenter ClusterRole
resource "kubectl_manifest" "karpenter_cluster_role" {
  yaml_body = <<-YAML
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: karpenter-provisioner-access
rules:
  - apiGroups: [""]
    resources: ["nodes"]
    verbs: ["create", "delete", "get", "list", "patch"]
  - apiGroups: [""]
    resources: ["pods"]
    verbs: ["get", "list", "watch"]
  - apiGroups: ["karpenter.sh"]
    resources: ["provisioners", "provisioners/status"]
    verbs: ["get", "list", "watch", "create", "delete", "update", "patch"]
YAML

  depends_on = [
    helm_release.this["karpenter"],
    null_resource.update_kubeconfig
  ]
}

# Karpenter ClusterRoleBinding
resource "kubectl_manifest" "karpenter_cluster_role_binding" {
  yaml_body = <<-YAML
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: karpenter-provisioner-binding
subjects:
  - kind: ServiceAccount
    name: karpenter
    namespace: kube-system
roleRef:
  kind: ClusterRole
  name: karpenter-provisioner-access
  apiGroup: rbac.authorization.k8s.io
YAML

  depends_on = [
    kubectl_manifest.karpenter_cluster_role,
    helm_release.this["karpenter"],
    null_resource.update_kubeconfig
  ]
}