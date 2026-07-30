# homelab-infra

GitOps configuration for my homelab Kubernetes cluster. There is no
application code here — only ArgoCD `Application` manifests, Helm values and
Kustomize overlays. ArgoCD watches the `main` branch of this repository and
reconciles the cluster from it.

## Layout

| Path            | Contents                                                     |
| --------------- | ------------------------------------------------------------ |
| `applications/` | ArgoCD `Application` manifests, one per app. `aoa.yaml` is the app-of-apps that discovers all the others. |
| `values/`       | Helm values, split into `base/` and `homelab/` per app.       |
| `manifests/`    | Kustomize overlays and raw resources applied on top of the Helm releases. |
| `renovate.json` | Dependency update automation.                                 |

Adding an application is described in [CLAUDE.md](CLAUDE.md).

## Validation

Nothing is deployed by CI — the `validate` workflow only checks that what is
committed would actually render and schema-validate. It runs on every push and
pull request:

| Job                        | What it checks                                                |
| -------------------------- | ------------------------------------------------------------- |
| `pre-commit`               | Formatting, YAML lint, `actionlint`, secret detection.        |
| `kubeconform (argocd applications)` | Every `applications/**` file against the real `argoproj.io` `Application` schema. |
| `kubeconform (raw manifests)`       | Every standalone file under `manifests/**`.          |
| `kustomize build + kubeconform`     | Every `kustomization.yaml` builds, and its output validates. |
| `helm template + kubeconform`       | Every `Application` renders with its own value files, and the output validates. |
| `renovate config validator`         | `renovate.json` is well-formed.                      |
| `gitleaks`                          | No committed secrets.                                |

All schema validation runs with `-strict`, so an unknown or misspelled field
in a known schema is an error rather than a shrug.

### Running the checks locally

Install [pre-commit](https://pre-commit.com/), then:

```bash
pre-commit install && pre-commit run --all-files
```

The heavier rendering check needs `helm`, `yq` and `kubeconform` on `PATH`
(pinned versions live in the `env:` block of
[.github/workflows/validate.yml](.github/workflows/validate.yml)):

```bash
bash .github/scripts/render-apps.sh
```
