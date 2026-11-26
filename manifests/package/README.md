# k8sbot installer package

An [installer](https://github.com/confighub/installer) package for k8sbot, published as `oci://ghcr.io/confighub/packages/k8sbot:<version>`.

The base holds what k8sbot needs under every GitOps controller:
- its Namespace (Pod Security Standards restricted)
- its ServiceAccount
- `list` on CustomResourceDefinitions, StorageClasses and IngressClasses, for cluster facts
- the Deployment, at a pinned image tag, with k8sbot's environment in its `env`, reading its key from the `k8sbot-secrets` Secret, which is not part of the package

Select one controller component with it:

| Component | Adds |
|---|---|
| `argocd` (default) | A Role and RoleBinding in `argocd` to read and patch Applications, and its variables: `GITOPS_CONTROLLER=argocd`, `ARGO_NAMESPACE`, `ARGO_REFRESH_TYPE` |
| `flux` | A ClusterRole to read and patch OCIRepositories and read Kustomizations, and `GITOPS_CONTROLLER=flux` |
| `sveltos` | A ClusterRole to read and patch profiles and read ClusterSummaries and HealthCheckReports, the HealthCheck and ClusterHealthCheck that live status reads, and `GITOPS_CONTROLLER=sveltos` |

They form the required `controller` group: selecting two fails, and selecting none installs `argocd`. A render fails validation if:
- the image is `:latest` or untagged
- the pod doesn't meet the Pod Security Standards restricted level

### k8sbot's environment

k8sbot's variables are in its Deployment's `env`, as in the plain deployments in [`manifests/`](..): the base sets the ones every controller reads, and each controller component adds its own with a patch. Change one in ConfigHub with `set-env`, for example:

```sh
cub function do --space k8sbot-my-cluster --unit k8sbot \
  set-env k8sbot ARGO_REFRESH_TYPE=normal
```

Metrics are the exception: the `metrics` input also sets the `metrics` port and the scrape annotations, which `set-env` leaves alone. Turning metrics off with `set-env k8sbot METRICS_ENABLED=false` leaves Prometheus scraping a port nothing serves, and turning them on that way leaves the pod unscraped. Change the input and render again instead. Likewise, moving the port with `METRICS_ADDR` needs the `metrics` containerPort moved too.

## Install

k8sbot needs the following before installing it, set up as under [Setup](../../README.md#setup):
- a service account, and a key of it (`cub serviceaccount key add --generate`)
- its grants on the cluster's Target
- a Channel that the service account can claim

It needs installer 0.3.0 or later. The key never goes to ConfigHub: put it in the `k8sbot-secrets` Secret in the install namespace yourself, or with your secret store, under the key `CONFIGHUB_AUTH_PRIVATE_KEY`.

```sh
installer setup --pull oci://ghcr.io/confighub/packages/k8sbot:0.2.5 \
  --work-dir k8sbot-my-cluster --namespace k8sbot \
  --input channel=my-cluster/k8sbot \
  --input target=my-cluster/target
installer upload --work-dir k8sbot-my-cluster --space k8sbot-my-cluster
kubectl create namespace k8sbot
kubectl create secret generic k8sbot-secrets -n k8sbot \
  --from-file=CONFIGHUB_AUTH_PRIVATE_KEY=k8sbot-my-cluster.jwk
```

Add `--select flux` or `--select sveltos` for those controllers.

| Input | Default | Description |
|---|---|---|
| `channel` | `confighubplaceholder` | The Channel k8sbot claims, as `<space>/<slug>`. |
| `target` | `confighubplaceholder` | The Target that stands for the cluster, as `<space>/<slug>`. k8sbot stores the cluster's facts on it. |
| `confighub_url` | `https://hub.confighub.com` | The ConfigHub URL as the cluster reaches it. |
| `metrics` | `true` | Whether k8sbot serves Prometheus metrics. `true` adds the `prometheus.io/scrape` and `prometheus.io/path` pod annotations, which only a scrape config that reads `prometheus.io/*` honours (the Prometheus Operator needs a PodMonitor instead); Prometheus scrapes the `metrics` containerPort. `false` sets `METRICS_ENABLED=false` and drops that port and the annotations. Switch metrics with this input and a new render, not `set-env`: see below. |

To run another image, such as a mirror's copy, pass `--set-image ghcr.io/confighub/k8sbot=<registry>/k8sbot:<tag>`.

### As a base for variants

Every input is optional, so one install can be the base that each cluster's variant is cloned from. Leave `channel` and `target` unset, and set them in each variant's `k8sbot` Unit, which holds the Deployment:

```sh
installer setup --pull oci://ghcr.io/confighub/packages/k8sbot:0.2.5 \
  --work-dir k8sbot-base --namespace k8sbot
installer upload --work-dir k8sbot-base --space k8sbot-base
cub variant create --target my-cluster/target my-cluster k8sbot-base
cub function do --space k8sbot-my-cluster --unit k8sbot \
  set-env k8sbot CONFIGHUB_CHANNEL=my-cluster/k8sbot CONFIGHUB_TARGET=my-cluster/target
```

`cub cluster attach` installs k8sbot this way.

## Testing

`scripts/test-package.sh` renders the package for each controller and preset with `installer setup`, running its validators, and checks the renders it has to refuse. It also checks that each controller's Deployment has the environment of its plain deployment in `manifests/`. It needs installer 0.3.0 or later (or `$INSTALLER`) and yq, and no ConfigHub server. The `package` workflow runs it on every change.

## Publishing

The package's version is the k8sbot release it runs: package 0.2.5 runs k8sbot v0.2.5. `scripts/set-version.sh vX.Y.Z` sets both before a release is tagged, and the release publishes the package after its image (`release.yml`). A version is published once, so a change to the package alone ships with the next k8sbot release.
