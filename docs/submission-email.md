Subject: DevOps Assignment — HA Kubernetes / GitOps platform (submission)

Hi,

Please find my submission for the multi-environment HA Kubernetes platform on AWS.

Repository
----------
https://github.com/viki-ops/DevOps-Assignment

(Monorepo with five top-level components instead of five separate repos — noted in the README.)

Deliverables
------------
1. infra-modules/     — Terraform modules (VPC, DNS, KMS, IRSA, S3 backend, IAM, …)
2. infra-live/        — Bootstrap + dev stack applied; stage/prod skeletons
3. cluster-ops/       — Ansible playbooks (tools, kOps create, ArgoCD bootstrap)
4. apps/charts/       — Retail Helm charts (digest-pinned, HPA, PDB, values.schema.json)
5. gitops/            — ArgoCD App-of-Apps, RBAC projects, Kyverno, observability values
6. docs/              — ADRs, runbooks, postmortems, CLI evidence (01–09), screenshots

What was demonstrated
---------------------
• Terraform foundations: VPC (3 AZ), private/public subnets, NAT, Route53 private zone
  corp.example.internal, KMS, OIDC/IRSA
• kOps HA cluster (3 control-plane, on-demand + spot workers, bastion, Cilium, IRSA)
• Platform via GitOps: LBC, ingress-nginx (NLB), external-dns, ESO, cluster-autoscaler,
  Kyverno, cert-manager (platform CA), kube-prometheus-stack
• Retail storefront (ui/catalog/cart/checkout/orders) on digests, HPA + PDB
• Promotion: digests equal across env values; prod left OutOfSync/Missing as manual gate
• Observability: Grafana dashboards + 99.5% storefront SLO burn-rate alert
• Failure injection: ingress drift (self-heal) + memory pressure (Kyverno + OOM) with postmortems

How to review evidence quickly
------------------------------
• README (layout, access, promotion): repo root
• Screenshots: docs/screenshots/ (linked from README)
• CLI logs: docs/evidence/
• ADRs / runbooks / postmortems: docs/

Storefront access (private DNS)
-------------------------------
NLB:
https://k8s-ingressn-ingressn-0097caa2ee-380827f08f31d201.elb.eu-north-1.amazonaws.com/

Map via hosts file (NLB IP → names), then open:
  https://store.corp.example.internal/home
  https://grafana.corp.example.internal/

Details: README → “Access the storefront (and Grafana)”.

Happy to walk through a live demo or answer any questions.

Thanks,
Vignesh
