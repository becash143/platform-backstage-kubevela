# Signing key for Backstage's service-to-service backend auth.
# Recent Backstage backends require at least one key under
# backend.auth.keys or the backend refuses to start.
resource "random_password" "backstage_backend_secret" {
  length  = 32
  special = false
}

resource "kubernetes_secret" "backstage_backend" {
  metadata {
    name      = "backstage-backend-secret"
    namespace = kubernetes_namespace.backstage.metadata[0].name
  }

  data = {
    BACKEND_SECRET = random_password.backstage_backend_secret.result
  }
}

resource "helm_release" "backstage" {
  name             = "backstage"
  repository       = "https://backstage.github.io/charts"
  chart            = "backstage"
  version          = var.backstage_chart_version
  namespace        = kubernetes_namespace.backstage.metadata[0].name
  create_namespace = false

  values = [
    templatefile("${path.module}/../backstage/helm-values.yaml.tpl", {
      backstage_image      = var.backstage_image
      kubevela_plugin_host = "http://${kubernetes_service.kubevela_plugin.metadata[0].name}.${kubernetes_namespace.vela_system.metadata[0].name}.svc.cluster.local:8080"
      backend_secret_name  = kubernetes_secret.backstage_backend.metadata[0].name
    })
  ]

  depends_on = [
    kubernetes_service.kubevela_plugin,
    helm_release.kubevela,
    kubernetes_secret.backstage_backend,
  ]
}
