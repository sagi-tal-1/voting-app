#!/bin/bash

echo "Starting Kubernetes cleanup process..."

# Function to remove finalizers from a resource
remove_finalizers() {
    local namespace=$1
    local resource_type=$2
    local resource_name=$3
    
    echo "Removing finalizers from $resource_type/$resource_name in namespace $namespace"
    kubectl patch $resource_type $resource_name -n $namespace --type=json -p='[{"op": "remove", "path": "/metadata/finalizers"}]' 2>/dev/null || true
}

# Function to force delete namespace
force_delete_namespace() {
    local namespace=$1
    echo "Force deleting namespace: $namespace"
    
    # Remove finalizers from namespace
    kubectl get namespace $namespace -o json | jq '.spec.finalizers = []' | kubectl replace --raw "/api/v1/namespaces/$namespace/finalize" -f - 2>/dev/null || true
    
    # Delete namespace
    kubectl delete namespace $namespace --timeout=5s 2>/dev/null || true
}

echo "Removing Karpenter resources..."
# Remove Karpenter resources
kubectl delete nodepool --all --all-namespaces --timeout=5s 2>/dev/null || true
kubectl delete nodeclaim --all --all-namespaces --timeout=5s 2>/dev/null || true
kubectl delete ec2nodeclass --all --timeout=5s 2>/dev/null || true

echo "Removing KEDA resources..."
# Remove KEDA resources
kubectl delete scaledobjects.keda.sh --all --all-namespaces --timeout=5s 2>/dev/null || true
kubectl delete scaledjobs.keda.sh --all --all-namespaces --timeout=5s 2>/dev/null || true
kubectl delete triggerauthentications.keda.sh --all --all-namespaces --timeout=5s 2>/dev/null || true

echo "Removing ArgoCD resources..."
# Remove ArgoCD resources
kubectl delete application --all --all-namespaces --timeout=5s 2>/dev/null || true
kubectl delete appproject --all --all-namespaces --timeout=5s 2>/dev/null || true

echo "Cleaning up stuck resources..."
# Get all namespaces in Terminating state
TERMINATING_NS=$(kubectl get ns --field-selector status.phase=Terminating -o jsonpath='{.items[*].metadata.name}' 2>/dev/null)

for ns in $TERMINATING_NS; do
    echo "Processing stuck namespace: $ns"
    
    # Remove finalizers from all resources in the namespace
    for resource_type in $(kubectl api-resources --namespaced=true --verbs=delete -o name); do
        echo "Checking $resource_type in namespace $ns"
        for resource in $(kubectl get $resource_type -n $ns -o jsonpath='{.items[*].metadata.name}' 2>/dev/null); do
            remove_finalizers $ns $resource_type $resource
        done
    done
    
    # Force delete the namespace
    force_delete_namespace $ns
done

echo "Removing CRDs..."
# Remove specific CRDs
kubectl delete crd nodepools.karpenter.sh --timeout=5s 2>/dev/null || true
kubectl delete crd nodeclaims.karpenter.sh --timeout=5s 2>/dev/null || true
kubectl delete crd ec2nodeclasses.karpenter.k8s.aws --timeout=5s 2>/dev/null || true
kubectl delete crd applications.argoproj.io --timeout=5s 2>/dev/null || true
kubectl delete crd appprojects.argoproj.io --timeout=5s 2>/dev/null || true
kubectl delete crd scaledobjects.keda.sh --timeout=5s 2>/dev/null || true
kubectl delete crd scaledjobs.keda.sh --timeout=5s 2>/dev/null || true
kubectl delete crd triggerauthentications.keda.sh --timeout=5s 2>/dev/null || true

echo "Cleanup completed. You can now run terraform destroy." 