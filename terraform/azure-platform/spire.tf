resource "helm_release" "spire_crds" {
  name             = "spire-crds"
  repository       = "https://spiffe.github.io/helm-charts-hardened/"
  chart            = "spire-crds"
  namespace        = "spire-server"
  create_namespace = true
}

resource "helm_release" "spire" {
  name       = "spire"
  repository = "https://spiffe.github.io/helm-charts-hardened/"
  chart      = "spire"
  version    = "0.29.0"
  namespace  = "spire-server"

  values = [yamlencode({
    global = {
      spire = {
        clusterName = var.cluster_name
        trustDomain = var.spire_trust_domain
        namespaces = {
          server = {
            create = false
          }
          system = {
            create = true
          }
        }
        recommendations = {
          enabled = true
        }
        caSubject = {
          country      = "RO"
          organization = "BridgeTheGap"
          commonName   = var.spire_trust_domain
        }
      }
    }
    "spiffe-oidc-discovery-provider" = {
      enabled = false
    }
  })]

  depends_on = [helm_release.spire_crds]
}
