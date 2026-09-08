# Screenshots evidence pack

| File | What it proves |
|------|----------------|
| `argocd/01-applications-platform-overview.png` | Platform apps (LBC, ingress, monitoring, etc.) Healthy/Synced |
| `argocd/02-prod-promotion-gate-outofsync-missing.png` | Prod apps OutOfSync/Missing — intentional manual promotion gate |
| `argocd/03-retail-ui-dev-stage-prod-comparison.png` | Dev UI Synced; stage/prod not auto-promoted |
| `argocd/04-retail-cart-resource-tree-synced.png` | App-of-Apps child resource tree (Deployment, HPA-related PDB, pods) |
| `grafana/01-dashboard-list.png` | Grafana dashboards incl. Retail storefront + HPA |
| `grafana/02-retail-storefront-overview.png` | SLO dashboard: rate, availability, latency, HPA |
| `grafana/03-retail-hpa-detail.png` | HPA replicas + memory working set |
| `storefront/01-home-demo-store.png` | Storefront reachable at `store.corp.example.internal/home` |
| `storefront/02-product-detail-aqua-ace.png` | Catalog path routing + product page |

Optional still useful to add: ingress-drift OutOfSync diff, post-heal Synced recovery, Grafana SLO alert rule page.
