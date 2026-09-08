# DevOps Assignment — HA Kubernetes platform on AWS

Monorepo delivering a highly available Kubernetes platform on AWS with
Terraform, kOps, Ansible, Helm and ArgoCD.

> **Brief deviation:** the assignment asked for five separate repositories.
> This is one monorepo with five top-level components so review stays coherent.
> `scripts/` includes a path to split later if required.

## Layout

| Path | Role |
|------|------|
| `infra-modules/` | Reusable Terraform (VPC, DNS, KMS, IRSA, …) |
| `infra-live/` | Bootstrapped S3 backend + `dev` stack |
| `cluster-ops/` | Ansible: toolchain, kOps cluster, ArgoCD bootstrap |
| `apps/charts/` | Five retail Helm charts (digest-pinned, HPA, PDB, schema) |
| `gitops/` | App-of-apps, AppProjects, values, policies, observability |
| `docs/` | ADRs, runbooks, postmortems, evidence pack, [screenshots](docs/screenshots/) |

## What’s running (dev)

- kOps HA cluster `dev.k8s.local` (3 CP / 2 on-demand + 2 spot / bastion), Cilium, IRSA
- ArgoCD 3.5.2 with platform + retail app-of-apps
- ingress-nginx NLB, external-dns → `corp.example.internal`, Kyverno guardrails
- kube-prometheus-stack + 99.5% storefront SLO burn-rate alerts
- Retail storefront: `store.corp.example.internal` (private DNS) / NLB + Host header publicly

## Quickstart (operator)

```bash
# Tools
ansible-playbook cluster-ops/playbooks/install-tools.yml

# Infra (once)
cd infra-live/_bootstrap && terraform init && terraform apply
cd ../dev && terraform init && terraform apply

# Cluster + ArgoCD
ansible-playbook cluster-ops/playbooks/cluster-create.yml
ansible-playbook cluster-ops/playbooks/argocd-bootstrap.yml
kubectl apply -f gitops/projects/ -f gitops/bootstrap/
```

## Evidence

- CLI / logs: [`docs/evidence/`](docs/evidence/) (phases 01–09)
- Postmortems: [`docs/postmortems/`](docs/postmortems/)
- Screenshot index: [`docs/screenshots/README.md`](docs/screenshots/README.md)

### Screenshots — ArgoCD

| Screenshot | Proves |
|------------|--------|
| [01-applications-platform-overview.png](docs/screenshots/argocd/01-applications-platform-overview.png) | Platform apps Healthy/Synced (LBC, ingress, monitoring, …) |
| [02-prod-promotion-gate-outofsync-missing.png](docs/screenshots/argocd/02-prod-promotion-gate-outofsync-missing.png) | Prod OutOfSync/Missing — manual promotion gate |
| [03-retail-ui-dev-stage-prod-comparison.png](docs/screenshots/argocd/03-retail-ui-dev-stage-prod-comparison.png) | Dev UI Synced; stage/prod not auto-promoted |
| [04-retail-cart-resource-tree-synced.png](docs/screenshots/argocd/04-retail-cart-resource-tree-synced.png) | App resource tree (Deployment, PDB, pods) Synced |

### Screenshots — Grafana

| Screenshot | Proves |
|------------|--------|
| [01-dashboard-list.png](docs/screenshots/grafana/01-dashboard-list.png) | Dashboard list incl. Retail storefront + HPA |
| [02-retail-storefront-overview.png](docs/screenshots/grafana/02-retail-storefront-overview.png) | SLO overview: rate, availability, latency, HPA |
| [03-retail-hpa-detail.png](docs/screenshots/grafana/03-retail-hpa-detail.png) | HPA replicas + memory working set |

### Screenshots — Storefront

| Screenshot | Proves |
|------------|--------|
| [01-home-demo-store.png](docs/screenshots/storefront/01-home-demo-store.png) | UI at `https://store.corp.example.internal/home` |
| [02-product-detail-aqua-ace.png](docs/screenshots/storefront/02-product-detail-aqua-ace.png) | Catalog product page + recommendations |

### Related docs

| Doc | Link |
|-----|------|
| ADRs | [`docs/adr/`](docs/adr/) |
| Promotion runbook | [`docs/runbooks/promotion.md`](docs/runbooks/promotion.md) |
| Ingress drift postmortem | [`docs/postmortems/2026-09-08-ingress-drift.md`](docs/postmortems/2026-09-08-ingress-drift.md) |
| Memory pressure postmortem | [`docs/postmortems/2026-09-08-memory-pressure.md`](docs/postmortems/2026-09-08-memory-pressure.md) |

## Promotion

```bash
./scripts/prove-digest-equality.sh
```

dev auto-syncs; stage/prod require manual Sync (see [`docs/runbooks/promotion.md`](docs/runbooks/promotion.md)).
