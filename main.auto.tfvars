region = {
  region = "us-east-1"
}

vpc = {
  vpc_eks = {
    cidr = "10.0.0.0/16"
    enable_nat_gateway   = true
    single_nat_gateway   = true
    enable_dns_hostnames = true
    
    # Load Balancer settings
    create_lb = true
    internal_lb = false  # Set to true if you want an internal load balancer
    lb_type    = "application"  # Options: "application" or "network"
    
    # Load Balancer Subnets
    public_subnets = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
    private_subnets = ["10.0.4.0/24", "10.0.5.0/24", "10.0.6.0/24"]
    
    # Enable cross-zone load balancing
    enable_cross_zone_load_balancing = true
  }
}

eks = {
  poc = {
    # Add EKS configuration here
  }
}

helm = {
  helm = {
    karpenter = {
      chart            = "karpenter"
      repository       = "oci://public.ecr.aws/karpenter"
      version          = "1.3.3"
      namespace        = "kube-system"
      create_namespace = true
      timeout          = 900
    }
    argocd = {
      chart            = "argo-cd"
      repository       = "https://argoproj.github.io/argo-helm"
      version          = "7.8.8"
      namespace        = "argocd"
      create_namespace = true
      timeout          = 900
      values = <<EOF
server:
  extraArgs:
    - --insecure
  rbacConfig:
    policy.default: role:readonly
    policy.csv: |
      p, role:org-admin, applications, *, */*, allow
      p, role:org-admin, clusters, get, *, allow
      p, role:org-admin, repositories, *, *, allow
      g, admin, role:org-admin
  config:
    repositories: |
      - type: git
        url: git@github.com:emc19802/poc_app.git
        sshPrivateKeySecret:
          name: repo-poc-app
          key: sshPrivateKey
EOF
    }
    cert-manager = {
      chart            = "cert-manager"
      repository       = "https://charts.jetstack.io"
      namespace        = "cert-manager"
      create_namespace = true
    }
    ingress-nginx = {
      chart      = "ingress-nginx"
      repository = "https://kubernetes.github.io/ingress-nginx"
      namespace = "ingress-nginx"
      create_namespace = true

    }
  }
}

eks_secret = {
  repo-poc-app = {
    namespace = "argocd"
    labels = {
      "argocd.argoproj.io/secret-type" = "repository"
    }
    data = {
      type = "git"
      url  = "git@github.com:emc19802/poc_app.git"
      name = "poc-app"
      sshPrivateKey = ""  # This will be set in main.tf
    }
    type = "Opaque"
  }
}

eks_namespace = {
  argocd = {
    labels = {
      name = "argocd"
    }
  }
  cert-manager = {
    labels = {
      name = "cert-manager"
    }
  }
  kube-system = {
    labels = {
      name = "kube-system"
    }
  }
  exam-app = {
    labels = {
      name                          = "exam-app"
      "argocd.argoproj.io/instance" = "exam-app"
    }
  }
}

eks_secret_copy = {
  mysql-db-secret = {
    namespace = "exam-app"
  }
}

secret_manager = {
  github-ssh-keys-secret = {
    description = "ArgoCD GitHub SSH keys"
  }
  exam-db-secrets-deployment = {}
  mysql-credentials = {
    secret_string = "{\"username\":\"mysqluser\",\"password\":\"MySQLPass123!\",\"mysql-root-password\":\"MySQLRoot123!\"}"
  }
}

eks_service_account = {
  exam-app-secret-sa = {
    namespace = "exam-app"
  }
}

eks_storage_class = {
  auto-ebs-sc = {
    annotations = {
      "storageclass.kubernetes.io/is-default-class" = "true"
    }
    parameters = {
      type      = "gp3"
      encrypted = "true"
    }
  }
}

