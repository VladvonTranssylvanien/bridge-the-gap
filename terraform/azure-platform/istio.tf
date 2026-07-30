resource "kubernetes_namespace" "istio_system" {
  metadata {
    name = "istio-system"
  }
}

resource "helm_release" "istio_base" {
  name       = "istio-base"
  repository = "https://istio-release.storage.googleapis.com/charts"
  chart      = "base"
  version    = var.istio_version
  namespace  = kubernetes_namespace.istio_system.metadata[0].name
}

resource "helm_release" "istiod" {
  name       = "istiod"
  repository = "https://istio-release.storage.googleapis.com/charts"
  chart      = "istiod"
  version    = var.istio_version
  namespace  = kubernetes_namespace.istio_system.metadata[0].name

  values = [yamlencode({
    meshConfig = {
      trustDomain = var.spire_trust_domain
    }
    sidecarInjectorWebhook = {
      templates = {
        spire = <<-EOT
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
        EOT
      }
    }
  })]

  depends_on = [helm_release.istio_base]
}

resource "helm_release" "istio_ingressgateway" {
  name       = "istio-ingressgateway"
  repository = "https://istio-release.storage.googleapis.com/charts"
  chart      = "gateway"
  version    = var.istio_version
  namespace  = kubernetes_namespace.istio_system.metadata[0].name

  values = [yamlencode({
    volumes = [
      {
        name = "workload-socket"
        csi = {
          driver   = "csi.spiffe.io"
          readOnly = true
        }
      }
    ]
    volumeMounts = [
      {
        name      = "workload-socket"
        mountPath = "/run/secrets/workload-spiffe-uds"
        readOnly  = true
      }
    ]
  })]

  depends_on = [helm_release.istiod]
}
