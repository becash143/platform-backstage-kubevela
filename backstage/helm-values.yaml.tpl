backstage:
  image:
    registry: ""
    repository: "${backstage_image}"
    tag: ""

  extraEnvVarsSecrets:
    - ${backend_secret_name}

  appConfig:
    app:
      title: Platform Portal
      baseUrl: http://localhost:7007

    backend:
      # NOTE: baseUrl/cors.origin below are set for the `kubectl
      # port-forward` demo flow in the README. If you front this with
      # an ingress/real domain, update both or service-to-service auth
      # and the frontend will break.
      baseUrl: http://localhost:7007
      listen:
        port: 7007
      cors:
        origin: http://localhost:3000
      # Recent Backstage backends require a signing key for
      # service-to-service auth or the backend will refuse to start.
      # BACKEND_SECRET is injected from a generated Kubernetes Secret
      # (see terraform/backstage.tf) via extraEnvVarsSecrets.
      auth:
        keys:
          - secret: $${BACKEND_SECRET}
      reading:
        allow:
          - host: "*.vela-system.svc.cluster.local:8080"

    # This is what actually bridges the two tools: KubeVela Applications
    # get polled and mirrored into the Backstage catalog as entities.
    #
    # IMPORTANT: catalog-plugin-wiring.ts uses the "older backend" pattern
    # (`new VelaProvider('production', env.reader, env.config)` from
    # @oamdev/plugin-kubevela-backend). For that pattern the plugin reads
    # these keys at the ROOT of app-config, NOT nested under
    # catalog.providers.vela.<id> — that nesting is only used by the
    # newer velaProviderModule (backend.add()) integration, which this
    # repo does not use. Keep this as a flat `vela:` block.
    vela:
      host: "${kubevela_plugin_host}"
      frequency: 30
      timeout: 60

    catalog:
      locations:
        - type: file
          target: /app/examples/sample-app/catalog-info.yaml

postgresql:
  enabled: true
  auth:
    database: backstage

ingress:
  enabled: false
