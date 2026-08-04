provider "kubernetes" {
  host                   = azurerm_kubernetes_cluster.main.kube_config[0].host
  client_certificate     = base64decode(azurerm_kubernetes_cluster.main.kube_config[0].client_certificate)
  client_key             = base64decode(azurerm_kubernetes_cluster.main.kube_config[0].client_key)
  cluster_ca_certificate = base64decode(azurerm_kubernetes_cluster.main.kube_config[0].cluster_ca_certificate)
}

provider "helm" {
  kubernetes {
    host                   = azurerm_kubernetes_cluster.main.kube_config[0].host
    client_certificate     = base64decode(azurerm_kubernetes_cluster.main.kube_config[0].client_certificate)
    client_key             = base64decode(azurerm_kubernetes_cluster.main.kube_config[0].client_key)
    cluster_ca_certificate = base64decode(azurerm_kubernetes_cluster.main.kube_config[0].cluster_ca_certificate)
  }
}

resource "helm_release" "istio_base" {
  name             = "istio-base"
  repository       = "https://istio-release.storage.googleapis.com/charts"
  chart            = "base"
  namespace        = "istio-system"
  create_namespace = false
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
        trustDomain        = "azure.bridgethegap.local"
        trustDomainAliases = ["aws.bridgethegap.local"]
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
                    driver: "csi.spiffe.io"
                    readOnly: true
          YAMLEOT
        }
      }
    })
  ]

  depends_on = [helm_release.istio_base]
}

resource "helm_release" "istio_ingressgateway" {
  name       = "istio-ingressgateway"
  repository = "https://istio-release.storage.googleapis.com/charts"
  chart      = "gateway"
  namespace  = "istio-system"
  version    = "1.30.3"

  values = [
    yamlencode({
      # The mesh ingress gateway ships with a standard Istio install, but
      # nothing in this project routes through it: the cross-cloud call goes
      # from Service A straight to service-b's own LoadBalancer, and Kiali is
      # reached via kubectl port-forward. At the chart default it provisions a
      # public Azure LoadBalancer with a public IP and no source restriction.
      #
      # Found during a post-delivery audit: an internet-facing endpoint with
      # zero legitimate internet consumers. Rather than bolt source ranges onto
      # something unused, the exposure is removed entirely by keeping the
      # gateway internal. The gateway pod, its sidecar and its SPIFFE identity
      # (istio-ingressgateway-reg) all stay in place, so mesh identity issuance
      # and Kiali's view of the mesh remain intact - only the public entry
      # point is gone.
      service = {
        type = "ClusterIP"
      }
      volumeMounts = [
        {
          mountPath = "/run/secrets/workload-spiffe-uds"
          name      = "workload-socket"
          readOnly  = true
        }
      ]
      volumes = [
        {
          csi = {
            driver   = "csi.spiffe.io"
            readOnly = true
          }
          name = "workload-socket"
        }
      ]
    })
  ]

  depends_on = [helm_release.istiod]
}
