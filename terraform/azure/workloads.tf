resource "kubernetes_service" "service_b_external" {
  metadata {
    name      = "service-b-external"
    namespace = "workloads"
  }
  spec {
    selector = {
      app = "service-b"
    }
    port {
      port        = 8080
      target_port = 8080
    }
    type                        = "LoadBalancer"
    load_balancer_source_ranges = ["35.158.254.123/32"]
  }
}
