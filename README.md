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
- Retail storefront: `store.corp.example.internal` (private Route53 zone)

## Access the storefront (and Grafana)

DNS for `*.corp.example.internal` lives in a **private Route53 zone** (VPC-only).
Your laptop cannot resolve those names unless you map them locally (or are on the VPC).

### 1) Public NLB (ingress-nginx)

```text
https://k8s-ingressn-ingressn-0097caa2ee-380827f08f31d201.elb.eu-north-1.amazonaws.com/
```

Opening that URL alone returns nginx **404** — Ingress matches on **Host**, not the ELB name.

Refresh the hostname anytime with:

```bash
kubectl -n ingress-nginx get svc ingress-nginx-controller \
  -o jsonpath='{.status.loadBalancer.ingress[0].hostname}{"\n"}'
```

### 2) Map the private names on your machine (hosts file)

Resolve one NLB IP, then edit hosts:

```bash
# Linux / macOS
nslookup k8s-ingressn-ingressn-0097caa2ee-380827f08f31d201.elb.eu-north-1.amazonaws.com

# Windows (PowerShell)
Resolve-DnsName k8s-ingressn-ingressn-0097caa2ee-380827f08f31d201.elb.eu-north-1.amazonaws.com
```

Add lines (use any returned A record; NLB IPs can change):

| OS | File |
|----|------|
| Windows | `C:\Windows\System32\drivers\etc\hosts` (Notepad as Administrator) |
| Linux / macOS | `/etc/hosts` (`sudo`) |

```text
13.61.136.135  store.corp.example.internal
13.61.136.135  grafana.corp.example.internal
```

### 3) Open in the browser

| App | URL | Notes |
|-----|-----|--------|
| Storefront | https://store.corp.example.internal/home | Accept self-signed cert warning |
| Grafana | https://grafana.corp.example.internal/ | `admin` / see Grafana secret in cluster |

Browser extensions **cannot** override the `Host` header (Chrome blocks it) — use the hosts-file method above.

### 4) Quick curl check (no hosts file)

```bash
curl -sk -H "Host: store.corp.example.internal" \
  https://k8s-ingressn-ingressn-0097caa2ee-380827f08f31d201.elb.eu-north-1.amazonaws.com/home
```

Expect HTTP **200** and HTML titled `Demo Store`.

Why private DNS + public NLB: see [`docs/adr/0002-dns-topology.md`](docs/adr/0002-dns-topology.md).

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
| Teardown runbook | [`docs/runbooks/teardown.md`](docs/runbooks/teardown.md) |
| Ingress drift postmortem | [`docs/postmortems/2026-09-08-ingress-drift.md`](docs/postmortems/2026-09-08-ingress-drift.md) |
| Memory pressure postmortem | [`docs/postmortems/2026-09-08-memory-pressure.md`](docs/postmortems/2026-09-08-memory-pressure.md) |

## Promotion (dev → stage → prod)

We promote by copying the **same image digest** (`sha256:…`) from
`gitops/values/apps/dev/` into `stage/` and `prod/` — not by retagging `:latest`.
That proves what you tested in dev is exactly what stage/prod will run.

| Env | How it deploys |
|-----|----------------|
| **dev** | ArgoCD auto-sync |
| **stage / prod** | Manual Sync only (promotion gate) |

After a promote PR, verify digests match across all three envs:

```bash
./scripts/prove-digest-equality.sh
# expect: OK for ui, catalog, cart, checkout, orders (same sha256 each)
```

Full steps: [`docs/runbooks/promotion.md`](docs/runbooks/promotion.md).

## Teardown (destroy after walkthrough)

Stop AWS spend once review is done. Full checklist:
[`docs/runbooks/teardown.md`](docs/runbooks/teardown.md).

```bash
# 1) kOps cluster (instances, ASGs, API/ingress NLBs, volumes)
export AWS_REGION=eu-north-1
export KOPS_STATE_STORE=s3://platform-kops-state-eun1-125788629837
export NAME=dev.k8s.local
kops delete cluster --name "${NAME}" --yes

# 2) Terraform VPC / DNS / IRSA / KMS (dev stack)
cd infra-live/dev && terraform init && terraform destroy -auto-approve

# 3) Optional last: remote state + kOps state buckets
# cd infra-live/_bootstrap && terraform init && terraform destroy -auto-approve
```

Then confirm no leftover EC2 / k8s NLBs / unattached EIPs (commands in the runbook).
