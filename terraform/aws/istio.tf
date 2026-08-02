provider "kubernetes" {
  host                   = aws_eks_cluster.main.endpoint
  cluster_ca_certificate = base64decode(aws_eks_cluster.main.certificate_authority[0].data)

  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args        = ["eks", "get-token", "--cluster-name", aws_eks_cluster.main.name, "--region", "eu-central-1"]
  }
}

provider "helm" {
  kubernetes {
    host                   = aws_eks_cluster.main.endpoint
    cluster_ca_certificate = base64decode(aws_eks_cluster.main.certificate_authority[0].data)

    exec {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      args        = ["eks", "get-token", "--cluster-name", aws_eks_cluster.main.name, "--region", "eu-central-1"]
    }
  }
}

resource "helm_release" "istio_base" {
  name             = "istio-base"
  repository       = "https://istio-release.storage.googleapis.com/charts"
  chart            = "base"
  namespace        = "istio-system"
  create_namespace = true
  version          = "1.30.3"
}

resource "helm_release" "istiod" {
  name       = "istiod"
  repository = "https://istio-release.storage.googleapis.com/charts"
  chart      = "istiod"
  namespace  = "istio-system"
  version    = "1.30.3"

  values = [
    yamlencode({
      meshConfig = {
        trustDomain = "aws.bridgethegap.local"
      }
      sidecarInjectorWebhook = {
        templates = {
          spire = <<-YAMLEOT
            labels:
              spiffe.io/spire-managed-identity: "true"
            spec:
              initContainers:
                - name: istio-proxy
                  volumeMounts:
                    - name: workload-socket
                      mountPath: /run/secrets/workload-spiffe-uds
                      readOnly: true
              volumes:
                - name: workload-socket
                  csi:
                    driver: csi.spiffe.io
                    readOnly: true
          YAMLEOT
        }
      }
    })
  ]

  depends_on = [helm_release.istio_base]
}
