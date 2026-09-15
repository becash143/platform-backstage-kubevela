# Backstage + KubeVela Platform (IaC)

Terraform that installs and wires together **KubeVela** (application delivery on Kubernetes) and **Backstage** (the developer-facing catalog/portal), so KubeVela Applications automatically sync into the Backstage software catalog.

Cloud agnostic: targets any existing cluster via kubeconfig (EKS, GKE, AKS, kind, k3s, etc.). No cloud-specific provisioning is included; bring your own cluster.

---

## Table of contents

- [What this deploys](#what-this-deploys)
- [Repository layout](#repository-layout)
- [Everything you need to do first](#everything-you-need-to-do-first)
  - [1. Build your Backstage app image](#1-build-your-backstage-app-image)
  - [2. Build the KubeVela bridge plugin image](#2-build-the-kubevela-bridge-plugin-image)
  - [3. Point kubectl at your target cluster](#3-point-kubectl-at-your-target-cluster)
- [Deploy with Terraform](#deploy-with-terraform)
- [Terraform variables](#terraform-variables)
- [Verify the bridge is working](#verify-the-bridge-is-working)
- [Golden path for new services](#golden-path-for-new-services)
- [Configuration notes](#configuration-notes)
- [Known gaps this doesn't solve](#known-gaps-this-doesnt-solve)
- [Troubleshooting](#troubleshooting)

---

## What this deploys

| Component | What it is | Where it runs |
|---|---|---|
| KubeVela (`vela-core`) | OAM-based application delivery engine | `vela-system` namespace |
| Bridge plugin (`backstage-plugin-kubevela`) | Community connector that reads KubeVela `Application` resources and serves them to Backstage | `vela-system` namespace |
| Backstage | Developer-facing catalog and portal | `backstage` namespace |

The bridge plugin polls the Kubernetes API for `Application` resources (read-only, scoped RBAC) and exposes them over HTTP. Backstage's catalog provider polls that endpoint on a schedule and mirrors what it finds into the software catalog as entities.

---

## Repository layout

```
terraform/                    Cluster-side infra: Helm releases, namespaces, RBAC, plugin Deployment
backstage/
  helm-values.yaml.tpl         Templated Helm values, including the vela provider + backend auth config
  catalog-plugin-wiring.ts     Code you must add to your own Backstage app source (see below)
scaffolder-templates/
  oam-service/                 Golden-path template: scaffolds a new service + matching Vela Application
examples/sample-app/           Working reference: catalog-info.yaml + Application manifest
```

---

## Everything you need to do first

This repo automates the cluster-side infrastructure. It does **not** and **cannot** automate the two items below, because they require compiling custom code into container images before Terraform ever runs. Skipping either step is the most common reason this stops working.

### 1. Build your Backstage app image

Terraform deploys a pre-built Backstage container image (`var.backstage_image`). It has no way to modify the source code that image was built from, so the entity-provider wiring has to be in the image before you push it.

| Step | Command / action |
|---|---|
| Scaffold a Backstage app (if you don't already have one) | `npx @backstage/create-app` |
| Install the plugin package | `yarn add --cwd packages/backend @oamdev/plugin-kubevela-backend` |
| Wire the provider into the catalog backend | Replace `packages/backend/src/plugins/catalog.ts` with the contents of [`backstage/catalog-plugin-wiring.ts`](backstage/catalog-plugin-wiring.ts) |
| Build the image | `docker build -t ghcr.io/your-org/backstage-app:latest .` |
| Push it | `docker push ghcr.io/your-org/backstage-app:latest` |
| Use it | Pass the pushed tag as `var.backstage_image` when you run `terraform apply` |

> If your Backstage app uses the newer backend system (a single `packages/backend/src/index.ts` with `backend.add(...)` calls) instead of the older plugin-file pattern, `catalog-plugin-wiring.ts` won't drop in as-is. Either adapt it to that structure, or switch to the `velaProviderModule` integration path instead, and update the config keys accordingly (see [Configuration notes](#configuration-notes)).

### 2. Build the KubeVela bridge plugin image

| Step | Command / action |
|---|---|
| Clone the connector repo | `git clone https://github.com/kubevela-contrib/backstage-plugin-kubevela` |
| Build the image (repo includes a `Dockerfile`) | `docker build -t ghcr.io/your-org/backstage-kubevela-plugin:latest .` |
| Push it | `docker push ghcr.io/your-org/backstage-kubevela-plugin:latest` |
| Use it | Pass the pushed tag as `var.kubevela_plugin_image` when you run `terraform apply` |

### 3. Point kubectl at your target cluster

Make sure a valid kubeconfig context exists for the cluster you're deploying to, and note the path/context name. You'll pass these as `var.kubeconfig_path` / `var.kube_context` (defaults: `~/.kube/config` and the current context).

---

## Deploy with Terraform

Once both images from the previous section are built and pushed:

```bash
cd terraform
terraform init
terraform apply \
  -var="kubevela_plugin_image=ghcr.io/your-org/backstage-kubevela-plugin:latest" \
  -var="backstage_image=ghcr.io/your-org/backstage-app:latest"
```

This creates:

- **`vela-system` namespace**: KubeVela core, the bridge plugin (Deployment + Service), and RBAC scoped to read-only access on `Application` resources
- **`backstage` namespace**: Backstage, a generated backend auth secret, and `vela.host` pointed at the in-cluster plugin service

---

## Terraform variables

| Variable | Description | Default |
|---|---|---|
| `kubeconfig_path` | Path to kubeconfig file for the target cluster | `~/.kube/config` |
| `kube_context` | kubeconfig context to use | `null` (current context) |
| `kubevela_namespace` | Namespace for KubeVela core + the bridge plugin | `vela-system` |
| `kubevela_chart_version` | KubeVela Helm chart version | `1.9.11` |
| `backstage_namespace` | Namespace for the Backstage portal | `backstage` |
| `backstage_chart_version` | Backstage Helm chart version | `2.8.2` |
| `kubevela_plugin_image` | Your pushed bridge plugin image (see step 2 above) | `ghcr.io/your-org/backstage-kubevela-plugin:latest` |
| `backstage_image` | Your pushed Backstage app image (see step 1 above) | `ghcr.io/your-org/backstage-app:latest` |

---

## Verify the bridge is working

```bash
kubectl apply -f examples/sample-app/application.yaml
kubectl port-forward -n backstage svc/backstage 7007:7007
```

Open Backstage and check the catalog for `hello-service`. It should appear as a Component within one refresh interval (default 30s), sourced from the live Application, not from the static `catalog-info.yaml` alone.

---

## Golden path for new services

Load `scaffolder-templates/oam-service/template.yaml` into Backstage's software templates. It scaffolds a new repo containing:

- `catalog-info.yaml` with the annotations the provider actually reads (`kubevela.io/application`, `kubevela.io/namespace`)
- `vela-application.yaml` with a minimal `webservice` component and traits

That annotation step is the part most integrations skip, and then wonder why the entity shows up once and never updates.

---

## Configuration notes

**Provider config path.** `backstage/catalog-plugin-wiring.ts` uses the "older backend" integration pattern for `@oamdev/plugin-kubevela-backend` (`new VelaProvider(...)` wired manually into `catalog.ts`). That pattern reads its config from a flat `vela:` block at the root of app-config, not from `catalog.providers.vela.<id>`, which is a different, newer integration path (`velaProviderModule` via `backend.add()`) this repo doesn't use. `helm-values.yaml.tpl` and the wiring code are kept in sync on this. If you switch to the newer backend module, both need to change together, and that path expects `schedule: { initialDelay, frequency, timeout }` as nested Duration objects, not flat `.seconds` values.

**Backend auth.** Recent Backstage backends require a signing key under `backend.auth.keys` to start. Terraform generates one (`random_password.backstage_backend_secret`) and injects it via a Kubernetes Secret and `extraEnvVarsSecrets`. Double-check your chart version supports `extraEnvVarsSecrets` the same way, since Helm chart values shapes change across releases.

---

## Known gaps this doesn't solve

| Gap | Detail |
|---|---|
| RBAC is still two systems | Backstage permissions and Kubernetes/KubeVela RBAC are configured independently; there's no single source of truth for "who can do what" |
| Polling, not push | Status is only as fresh as the refresh interval; the community plugin has no webhook/event-driven sync as of this writing |
| Multi-cluster isn't handled | This wiring assumes one cluster. KubeVela supports multi-cluster delivery; extending the provider to multiple `host` entries is the natural next step |

---

## Troubleshooting

| Symptom | Likely cause |
|---|---|
| Catalog never shows the entity | `var.backstage_image` was not rebuilt with `catalog-plugin-wiring.ts` baked in (see [step 1](#1-build-your-backstage-app-image)) |
| Backstage backend won't start | Missing or misconfigured `backend.auth.keys`; check the generated `backstage-backend-secret` in the `backstage` namespace |
| Entity appears once, then goes stale | `catalog-info.yaml` is missing the `kubevela.io/application` / `kubevela.io/namespace` annotations |
| Provider can't reach the plugin | Confirm `vela.host` in the rendered Helm values matches the in-cluster Service DNS name, and that `backend.reading.allow` includes that host |
