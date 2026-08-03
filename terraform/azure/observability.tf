resource "helm_release" "kube_prometheus_stack" {
  name             = "kube-prometheus-stack"
  repository       = "https://prometheus-community.github.io/helm-charts"
  chart            = "kube-prometheus-stack"
  version          = "88.1.3"
  namespace        = "monitoring"
  create_namespace = true

  # Only the Prometheus server is needed here - Kiali is the graph/UI layer,
  # so Grafana and Alertmanager would just be unused weight for this PoC's
  # bonus observability challenge (see README bonus #3).
  values = [
    yamlencode({
      grafana      = { enabled = false }
      alertmanager = { enabled = false }
      prometheus = {
        prometheusSpec = {
          # kube-prometheus-stack's Prometheus Operator does NOT scrape pods
          # based on prometheus.io/* annotations by default (unlike Istio's
          # own demo addon manifest, which we deliberately did not use).
          # This scrape config replicates that annotation-based discovery so
          # istiod and the Envoy sidecars' metrics endpoints get picked up
          # without a ServiceMonitor/PodMonitor per component.
          additionalScrapeConfigs = [
            {
              job_name = "istio-mesh"
              kubernetes_sd_configs = [
                { role = "pod" }
              ]
              relabel_configs = [
                {
                  source_labels = ["__meta_kubernetes_pod_annotation_prometheus_io_scrape"]
                  action        = "keep"
                  regex         = "true"
                },
                {
                  source_labels = ["__meta_kubernetes_pod_annotation_prometheus_io_path"]
                  action        = "replace"
                  target_label  = "__metrics_path__"
                  regex         = "(.+)"
                },
                {
                  source_labels = ["__address__", "__meta_kubernetes_pod_annotation_prometheus_io_port"]
                  action        = "replace"
                  regex         = "([^:]+)(?::\\d+)?;(\\d+)"
                  replacement   = "$1:$2"
                  target_label  = "__address__"
                },
                {
                  source_labels = ["__meta_kubernetes_namespace"]
                  action        = "replace"
                  target_label  = "namespace"
                },
                {
                  source_labels = ["__meta_kubernetes_pod_name"]
                  action        = "replace"
                  target_label  = "pod"
                },
              ]
            }
          ]
        }
      }
    })
  ]
}

resource "helm_release" "kiali" {
  name       = "kiali-server"
  repository = "https://kiali.org/helm-charts"
  chart      = "kiali-server"
  version    = "2.30.0"
  namespace  = "istio-system"

  # Anonymous auth is only safe because Kiali is reached exclusively via
  # `kubectl port-forward` (see README). Never expose this Service via a
  # LoadBalancer/Ingress with this setting - anonymous mode grants full
  # read access to the mesh graph (namespaces, workloads, traffic) to
  # anyone who can reach it.
  #
  # Prometheus URL points at the Service confirmed live via
  # `kubectl get svc -n monitoring` after the kube-prometheus-stack apply
  # (kube-prometheus-stack-prometheus.monitoring:9090), not guessed.
  values = [
    yamlencode({
      auth = {
        strategy = "anonymous"
      }
      external_services = {
        prometheus = {
          url = "http://kube-prometheus-stack-prometheus.monitoring:9090"
        }
      }
      deployment = {
        accessible_namespaces = ["**"]
      }
    })
  ]

  depends_on = [helm_release.kube_prometheus_stack]
}
