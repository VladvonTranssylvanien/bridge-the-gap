resource "helm_release" "spire_crds" {
  name             = "spire-crds"
  repository       = "https://spiffe.github.io/helm-charts-hardened/"
  chart            = "spire-crds"
  namespace        = "spire-server"
  create_namespace = true
  version          = "0.5.0"
}

resource "helm_release" "spire" {
  name             = "spire"
  repository       = "https://spiffe.github.io/helm-charts-hardened/"
  chart            = "spire"
  namespace        = "spire-server"
  create_namespace = false
  version          = "0.29.0"

  values = [
    yamlencode({
      global = {
        spire = {
          caSubject = {
            commonName   = "aws.bridgethegap.local"
            country      = "RO"
            organization = "BridgeTheGap"
          }
          clusterName = "bridge-the-gap-aws"
          namespaces = {
            server = {
              create = false
            }
            system = {
              create = true
            }
          }
          persistence = {
            storageClass = "ebs-gp3"
          }
          recommendations = {
            enabled = true
          }
          trustDomain = "aws.bridgethegap.local"
        }
      }
      "spiffe-oidc-discovery-provider" = {
        enabled = false
      }
    })
  ]

  depends_on = [helm_release.spire_crds, kubernetes_storage_class.ebs_gp3]
}
