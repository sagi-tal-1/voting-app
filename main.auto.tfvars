vpc = {
  vpc_eks = {
    cidr = "10.0.0.0/16"
  }
}

eks = {
  poc = {
    # Add EKS configuration here
  }
}

helm = {
  karpenter = {
    chart            = "karpenter"
    repository       = "oci://public.ecr.aws/karpenter"
    version          = "v0.33.1"
    namespace        = "kube-system"
    create_namespace = true
    values = [{
      rbac = {
        create = true
      }
      serviceAccount = {
        create = true
        name   = "karpenter"
      }
    }]
  }
}

eks_secret = {
  ssh-key-github-template = {
    namespace = "argocd"
    labels = {
      "argocd.argoproj.io/secret-type" = "repo-creds"
    }
    sshPrivateKey = ""
    data = {
      url  = "git@github.com:sagi-tal-1"
      type = "git"
    }
    type = "Opaque"
  }

  exam-app-repo-github = {
    namespace = "argocd"
    labels = {
      "argocd.argoproj.io/secret-type" = "repository"
    }
    data = {
      name = "exam-app-repo-github"
      url  = "git@github.com:eyalrainitz/exam-files.git"
      type = "git"
    }
    type = "Opaque"
  }

  mysql-db-secret = {
    namespace = "mysql"
    data      = {}
    type      = "Opaque"
  }
}

eks_secret_copy = {
  mysql-db-secret = {
    namespace = "exam-app"
  }
}

secret_manager = {
  github-ssh-keys-secret       = {}
  exam-db-secrets-deployment   = {}
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

eks_namespace = {
  mysql = {
    labels = {
      name = "mysql"
    }
  }

  argocd = {
    labels = {
      name = "argocd"
    }
  }

  exam-app = {
    labels = {
      name                                = "exam-app"
      "argocd.argoproj.io/instance"       = "exam-app"
    }
  }
}
