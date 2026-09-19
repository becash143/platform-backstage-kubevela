# RBAC for Backstage's own ServiceAccount (kubernetes_service_account.backstage
# in backstage.tf) -- separate from the bridge plugin's RBAC in kubevela.tf,
# which is scoped only to reading Application resources for the entity
# provider. This file covers what Backstage's backend itself needs
# directly: applying KubeVela Applications (if you use the local
# kubevela:apply scaffolder action) and reading workload status (if you
# enable the Kubernetes plugin).

# ---- Permission to apply/manage KubeVela Applications directly ----
# Only needed if your Backstage backend uses a direct-apply scaffolder
# action instead of (or alongside) the GitOps publish:github flow this
# repo's default template uses. Safe to leave in place even if unused.
resource "kubernetes_role" "backstage_vela_apply" {
  metadata {
    name      = "backstage-vela-apply"
    namespace = var.workload_namespace
  }

  rule {
    api_groups = ["core.oam.dev"]
    resources  = ["applications"]
    verbs      = ["get", "list", "watch", "create", "update", "patch"]
  }
}

resource "kubernetes_role_binding" "backstage_vela_apply" {
  metadata {
    name      = "backstage-vela-apply"
    namespace = var.workload_namespace
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "Role"
    name      = kubernetes_role.backstage_vela_apply.metadata[0].name
  }

  subject {
    kind      = "ServiceAccount"
    name      = kubernetes_service_account.backstage.metadata[0].name
    namespace = kubernetes_namespace.backstage.metadata[0].name
  }
}

# ---- Read access for the Kubernetes plugin (live pod/deployment status) ----
resource "kubernetes_role" "backstage_k8s_view" {
  count = var.enable_kubernetes_plugin ? 1 : 0

  metadata {
    name      = "backstage-k8s-view"
    namespace = var.workload_namespace
  }

  rule {
    api_groups = [""]
    resources  = ["pods", "services", "configmaps", "replicationcontrollers"]
    verbs      = ["get", "list", "watch"]
  }
  rule {
    api_groups = ["apps"]
    resources  = ["deployments", "replicasets"]
    verbs      = ["get", "list", "watch"]
  }
  rule {
    api_groups = ["metrics.k8s.io"]
    resources  = ["pods"]
    verbs      = ["get", "list"]
  }
}

resource "kubernetes_role_binding" "backstage_k8s_view" {
  count = var.enable_kubernetes_plugin ? 1 : 0

  metadata {
    name      = "backstage-k8s-view"
    namespace = var.workload_namespace
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "Role"
    name      = kubernetes_role.backstage_k8s_view[0].metadata[0].name
  }

  subject {
    kind      = "ServiceAccount"
    name      = kubernetes_service_account.backstage.metadata[0].name
    namespace = kubernetes_namespace.backstage.metadata[0].name
  }
}
