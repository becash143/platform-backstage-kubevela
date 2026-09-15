# Backstage + KubeVela Platform, IaC

Cloud-agnostic Terraform that installs and wires together:

- **KubeVela** (`vela-core`) — OAM-based delivery engine, the backend
- **backstage-plugin-kubevela** — the community bridge that mirrors
  Vela Applications into the Backstage catalog
- **Backstage** — the developer-facing frontend/catalog

Targets any existing Kubernetes cluster via kubeconfig (EKS, GKE, AKS,
kind, k3s, etc.) — no cloud-specific provisioning included, bring your
own cluster.

## Layout

```
terraform/                  Cluster-side infra (Helm releases, RBAC, plugin Deployment)
backstage/
  helm-values.yaml.tpl       Templated Helm values incl. the catalog provider config
  catalog-plugin-wiring.ts   Code that MUST be added to your Backstage app source
scaffolder-templates/
  oam-service/               Golden-path template: generates a service + Vela Application
examples/sample-app/         A working reference: catalog-info.yaml + Application
```

## Prerequisites (things this repo does NOT automate)

1. **A built Backstage app image** with `@oamdev/plugin-kubevela-backend`
   installed and wired in (`backstage/catalog-plugin-wiring.ts` shows the
   exact code — this can't be expressed as Helm values, it has to be
   compiled into the app). Push it and set `var.backstage_image`.
2. **A built plugin backend image** from
   [`kubevela-contrib/backstage-plugin-kubevela`](https://github.com/kubevela-contrib/backstage-plugin-kubevela).
   Push it and set `var.kubevela_plugin_image`.
3. `kubectl` context pointing at your target cluster, referenced by
   `var.kubeconfig_path` / `var.kube_context`.

These are the two "missing parts" from the earlier discussion: the
integration is real, but it needs custom images, not just YAML.

## Apply

```bash
cd terraform
terraform init
terraform apply \
  -var="kubevela_plugin_image=ghcr.io/your-org/backstage-kubevela-plugin:latest" \
  -var="backstage_image=ghcr.io/your-org/backstage-app:latest"
```

This creates:
- `vela-system` namespace: KubeVela core + the bridge plugin (Deployment,
  Service, RBAC scoped to read-only on `Application` resources)
- `backstage` namespace: Backstage, with `catalog.providers.vela`
  pointed at the in-cluster plugin service

## Verify the bridge is working

```bash
kubectl apply -f examples/sample-app/application.yaml
kubectl port-forward -n backstage svc/backstage 7007:7007
```

Open Backstage and check the catalog for `hello-service` — it should
appear as a Component within one refresh interval (default 30s here),
sourced from the live Application, not from the static
`catalog-info.yaml` alone.

## Golden path for new services

Load `scaffolder-templates/oam-service/template.yaml` into Backstage's
software templates. It scaffolds a new repo containing:
- `catalog-info.yaml` with the annotations the provider actually reads
  (`kubevela.io/application`, `kubevela.io/namespace`)
- `vela-application.yaml` with a minimal `webservice` component + traits

That annotation step is the part most integrations skip and then wonder
why the entity shows up once and never updates.

## Config note

`backstage/catalog-plugin-wiring.ts` uses the "older backend" integration
pattern for `@oamdev/plugin-kubevela-backend` (`new VelaProvider(...)`
wired manually into `catalog.ts`). That pattern reads its config from a
flat `vela:` block at the root of app-config — NOT from
`catalog.providers.vela.<id>`, which is a different, newer integration
path (`velaProviderModule` via `backend.add()`) this repo doesn't use.
`helm-values.yaml.tpl` and the wiring code are kept in sync on this —
if you switch to the newer backend module, both need to change together
(and the newer path expects `schedule: { initialDelay, frequency,
timeout }` as nested Duration objects, not flat `.seconds` values).

Backend auth: recent Backstage backends require a signing key under
`backend.auth.keys` to start. Terraform generates one
(`random_password.backstage_backend_secret`) and injects it via a
Kubernetes Secret + `extraEnvVarsSecrets`; double-check your chart
version supports `extraEnvVarsSecrets` the same way, since Helm chart
values shapes do change across releases.

## Known gaps this doesn't solve

- **RBAC is still two systems.** Backstage permissions and
  Kubernetes/KubeVela RBAC are configured independently here — there's
  no single source of truth for "who can do what."
- **Polling, not push.** Status is only as fresh as the refresh
  interval; there's no webhook/event-driven sync in the community
  plugin as of this writing.
- **Multi-cluster** isn't handled — this wiring assumes one cluster.
  KubeVela supports multi-cluster delivery; extending the provider to
  multiple `host` entries under `catalog.providers.vela` is the natural
  next step.
