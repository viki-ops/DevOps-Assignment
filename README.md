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
| `docs/` | ADRs, runbooks, postmortems, evidence pack |

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

See `docs/evidence/` (numbered by phase) and `docs/postmortems/`.

## Promotion

```bash
./scripts/prove-digest-equality.sh
```

dev auto-syncs; stage/prod require manual Sync (see `docs/runbooks/promotion.md`).
