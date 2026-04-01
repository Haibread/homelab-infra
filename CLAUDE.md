# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

This is a **GitOps homelab infrastructure** repository. There is no application code — only Kubernetes manifests, Helm values, and ArgoCD Application definitions. Deployments are driven by ArgoCD watching the `main` branch of this repo at `https://github.com/Haibread/homelab-infra.git`.

## Repository Structure

```
applications/     # ArgoCD Application manifests (one per app)
  aoa.yaml        # Root "App of Apps" — reconciles all other applications
manifests/        # Kustomize overlays, patches, and raw Kubernetes resources
  {namespace}/{app}/
values/           # Helm values files
  {namespace}/{app}/
    base/values.yaml      # Default/shared values
    homelab/values.yaml   # Environment-specific overrides
renovate.json     # Automated dependency update config
```

## Key Architectural Patterns

### Three-Source ArgoCD Pattern
Most applications use three sources:
1. **Helm chart** from a public registry (pinned version)
2. **`ref: values`** — mounts this repo so Helm can reference local value files
3. **`path: manifests/...`** — applies Kustomize overlays on top of the Helm release

```yaml
sources:
- repoURL: https://charts.example.com
  chart: chart-name
  targetRevision: "X.Y.Z"
  helm:
    valueFiles:
    - $values/values/{ns}/{app}/base/values.yaml
    - $values/values/{ns}/{app}/homelab/values.yaml
- repoURL: https://github.com/Haibread/homelab-infra.git
  targetRevision: main
  ref: values
- repoURL: https://github.com/Haibread/homelab-infra.git
  targetRevision: main
  path: manifests/{ns}/{app}/
```

### Sync Policy
All applications use server-side apply and manual sync (no auto-sync):
- `ServerSideApply=true`, `ServerSideDiff=true`
- `ApplyOutOfSyncOnly=true`, `CreateNamespace=true`
- `Validate=false` (skips kubectl schema validation)

### Networking
- **Envoy Gateway** handles all ingress via `Gateway` + `HTTPRoute` resources
- **Cilium** is the CNI with BGP Control Plane enabled
- **Multus** provides additional network interfaces for VMs
- Domain: `newgamer.lan`

### Storage
- **Rook Ceph** for distributed storage (StorageClasses, CephBlockPools, etc.)
- **CloudNative PG** operator for PostgreSQL

### Observability Stack
Prometheus → Grafana, Loki (logs), Mimir (long-term metrics), Alloy (agent)

### Media Stack
Radarr, Sonarr, Lidarr, Bazarr, Prowlarr, Flaresolverr, Tautulli, Seerr, Requestrr — all using the `bjw-s/app-template` Helm chart.

## Adding a New Application

1. Create `applications/{namespace}/{app}.yaml` — ArgoCD Application manifest
2. Create `values/{namespace}/{app}/base/values.yaml` (and optionally `homelab/values.yaml`)
3. If patches/extra resources are needed, create `manifests/{namespace}/{app}/kustomization.yaml`
4. The root `aoa.yaml` auto-discovers apps in `applications/`, so no registration needed

## Dependency Updates

Renovate is configured to auto-create PRs for:
- Helm chart versions in `applications/**/*.yaml`
- Docker image tags in `values/**/*.yaml` and `manifests/**/*.yaml`
