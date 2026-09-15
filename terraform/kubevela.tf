# ---- KubeVela core (the delivery/OAM controller) ----
resource "helm_release" "kubevela" {
  name             = "kubevela"
  repository       = "https://charts.kubevela.net/core"
  chart            = "vela-core"
  version          = var.kubevela_chart_version
  namespace        = kubernetes_namespace.vela_system.metadata[0].name
  create_namespace = false

  set {
    name  = "applicationRevisionLimit"
    value = "5"
  }
}

# ---- RBAC for the Backstage<->KubeVela bridge plugin ----
# The plugin needs cluster-wide read access to Application resources
# so it can mirror them into the Backstage catalog.
resource "kubernetes_service_account" "kubevela_plugin" {
  metadata {
    name      = "backstage-kubevela-plugin"
    namespace = kubernetes_namespace.vela_system.metadata[0].name
  }
}

resource "kubernetes_cluster_role" "kubevela_plugin" {
  metadata {
    name = "backstage-kubevela-plugin-reader"
  }

  rule {
    api_groups = ["core.oam.dev"]
    resources  = ["applications", "applicationrevisions"]
    verbs      = ["get", "list", "watch"]
  }

  rule {
    api_groups = [""]
    resources  = ["events"]
    verbs      = ["get", "list", "watch"]
  }
}

resource "kubernetes_cluster_role_binding" "kubevela_plugin" {
  metadata {
    name = "backstage-kubevela-plugin-reader-binding"
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = kubernetes_cluster_role.kubevela_plugin.metadata[0].name
  }

  subject {
    kind      = "ServiceAccount"
    name      = kubernetes_service_account.kubevela_plugin.metadata[0].name
    namespace = kubernetes_namespace.vela_system.metadata[0].name
  }
}

# ---- The bridge plugin itself (backstage-plugin-kubevela backend) ----
# This is the piece that turns Vela Applications into Backstage
# Custom Entity Provider payloads. Build the image from:
# https://github.com/kubevela-contrib/backstage-plugin-kubevela
resource "kubernetes_deployment" "kubevela_plugin" {
  metadata {
    name      = "backstage-kubevela-plugin"
    namespace = kubernetes_namespace.vela_system.metadata[0].name
    labels    = { app = "backstage-kubevela-plugin" }
  }

  spec {
    replicas = 1

    selector {
      match_labels = { app = "backstage-kubevela-plugin" }
    }

    template {
      metadata {
        labels = { app = "backstage-kubevela-plugin" }
      }

      spec {
        service_account_name = kubernetes_service_account.kubevela_plugin.metadata[0].name

        container {
          name  = "plugin"
          image = var.kubevela_plugin_image

          port {
            container_port = 8080
          }

          # Refresh cadence is controlled from the Backstage side
          # (vela.frequency in helm-values.yaml.tpl); the connector
          # itself doesn't read a refresh-frequency env var, so no
          # env block is needed here.

          resources {
            requests = { cpu = "50m", memory = "64Mi" }
            limits   = { cpu = "250m", memory = "256Mi" }
          }
        }
      }
    }
  }

  depends_on = [helm_release.kubevela]
}

resource "kubernetes_service" "kubevela_plugin" {
  metadata {
    name      = "backstage-kubevela-plugin"
    namespace = kubernetes_namespace.vela_system.metadata[0].name
  }

  spec {
    selector = { app = "backstage-kubevela-plugin" }

    port {
      port        = 8080
      target_port = 8080
    }
  }
}
