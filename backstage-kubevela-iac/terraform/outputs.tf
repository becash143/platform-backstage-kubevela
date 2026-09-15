output "kubevela_plugin_endpoint" {
  description = "In-cluster DNS endpoint the Backstage backend uses to reach the KubeVela bridge plugin"
  value       = "http://${kubernetes_service.kubevela_plugin.metadata[0].name}.${kubernetes_namespace.vela_system.metadata[0].name}.svc.cluster.local:8080"
}

output "backstage_namespace" {
  value = kubernetes_namespace.backstage.metadata[0].name
}

output "vela_system_namespace" {
  value = kubernetes_namespace.vela_system.metadata[0].name
}
