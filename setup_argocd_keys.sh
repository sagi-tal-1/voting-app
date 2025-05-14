#!/bin/bash

# Set variables
CLUSTER_NAME="poc-us-east-1-eks"
SECRET_NAME="github-ssh-keys-argocd-$(date +%Y%m%d-%H%M%S)"
GITHUB_REPO="git@github.com:emc19802/poc_app.git"

# Check if SSH key exists
if [ ! -f ~/.ssh/id_ed25519 ]; then
    echo "SSH key not found. Creating new key..."
    ssh-keygen -t ed25519 -C "argocd_key" -f ~/.ssh/id_ed25519 -N ""
fi

# Get the keys
PRIVATE_KEY=$(cat ~/.ssh/id_ed25519)
PUBLIC_KEY=$(cat ~/.ssh/id_ed25519.pub)

# Get known_hosts entry for GitHub
ssh-keyscan github.com > /tmp/known_hosts

# Create JSON for AWS Secrets Manager
cat << EOF > /tmp/secret.json
{
  "sshPrivateKey": "$(echo "$PRIVATE_KEY" | awk '{printf "%s\\n", $0}')",
  "sshPublicKey": "$(echo "$PUBLIC_KEY")",
  "knownHosts": "$(cat /tmp/known_hosts | awk '{printf "%s\\n", $0}')"
}
EOF

# Store in AWS Secrets Manager
aws secretsmanager create-secret \
    --name "$SECRET_NAME" \
    --description "ArgoCD GitHub SSH keys" \
    --secret-string "$(cat /tmp/secret.json)"

# Get the secret ARN
SECRET_ARN=$(aws secretsmanager describe-secret --secret-id "$SECRET_NAME" --query 'ARN' --output text)

echo "Created secret with ARN: $SECRET_ARN"

# Create ArgoCD repository secret
cat << EOF > repo-secret.yaml
apiVersion: v1
kind: Secret
metadata:
  name: repo-poc-app
  namespace: argocd
  labels:
    argocd.argoproj.io/secret-type: repository
stringData:
  type: git
  url: $GITHUB_REPO
  sshPrivateKey: |
$(echo "$PRIVATE_KEY" | sed 's/^/    /')
  knownHosts: |
$(cat /tmp/known_hosts | sed 's/^/    /')
EOF

# Apply the secret to Kubernetes
kubectl apply -f repo-secret.yaml

# Clean up temporary files
rm -f /tmp/secret.json /tmp/known_hosts repo-secret.yaml

echo "Setup complete!"
echo "Please add this public key to your GitHub repository deploy keys:"
echo "$PUBLIC_KEY"
echo "Visit: https://github.com/emc19802/poc_app/settings/keys/new to add the key" 