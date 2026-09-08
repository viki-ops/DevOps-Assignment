# Mock interview — platform walkthrough Q&A

Use this as prep for a live walkthrough of
https://github.com/viki-ops/DevOps-Assignment.

Answers match **what we actually built** (eu-north-1, `dev.k8s.local`, ArgoCD
App-of-Apps, retail digests, etc.). Prefer saying “here is the ADR / evidence”
over inventing details.

---

## 0. Elevator pitch (60–90 seconds)

> We built a highly available Kubernetes platform on AWS. Terraform provisions
> networking, private DNS, KMS, and IRSA. Ansible drives kOps to create a private
> HA cluster with bastion, Cilium, and encrypted Secrets. ArgoCD then owns
> everything above the cluster kernel via App-of-Apps: ingress, DNS, policies,
> observability, and the AWS retail-store sample apps. Dev auto-syncs; stage/prod
> are manual promotion gates with digest pinning. We proved drift self-heal,
> memory-pressure behaviour, and a 99.5% storefront SLO.

Repo is a **monorepo** (brief asked for five repos) — called out in the README.

---

## 1. Architecture & topology

### Q: Draw / describe the architecture end to end.

**A:** Layers, bottom to top:

1. **AWS foundations (Terraform)** — VPC across 3 AZs, public + private subnets,
   NAT (≥2), private Route53 zone `corp.example.internal`, KMS CMK, S3/DynamoDB
   state, OIDC discovery + IAM OIDC provider, IRSA roles.
2. **Compute / control plane (kOps)** — private topology, bastion, 3 masters
   multi-AZ, workers (on-demand + spot), Cilium CNI, cloud-controller-manager,
   EBS CSI, metrics-server, pod-identity-webhook, cert-manager (kube-system).
3. **Delivery control plane (ArgoCD)** — installed once by Ansible/Helm with
   IRSA; then reconciles Git.
4. **Platform apps (GitOps)** — LBC, ingress-nginx (NLB), external-dns, ESO,
   cluster-autoscaler, Kyverno, kube-prometheus-stack, issuers.
5. **Workloads (GitOps)** — retail ui/catalog/cart/checkout/orders with HPA/PDB
   and digest-pinned images.

Traffic: Internet → **NLB** (ingress-nginx) → Ingress (Host
`store.corp.example.internal`) → UI Service → UI pods → in-cluster Services for
backends.

### Q: Why private topology + bastion?

**A:** Nodes and API should not be on the public internet. Workers/masters sit in
private subnets; bastion (and API SG allow-list) is the controlled entry.
Matches “public/bastion access only” in the brief.

### Q: How many AZs / NAT / masters / workers?

**A:**

| Piece | Choice |
|-------|--------|
| AZs | 3 |
| NAT | ≥2 (cost-aware: one AZ may share) |
| Control plane | 3 masters, multi-AZ |
| Workers | On-demand + spot mix (spot labelled `lifecycle=spot`) |
| Bastion | Yes |

### Q: Why Cilium instead of Calico?

**A:** Cilium is what we pinned in the kOps cluster features for CNI + network
policies. Either satisfies the brief; Cilium eBPF datapath and policy model fit
a modern HA platform. Policies can be enforced later without changing CNI.

---

## 2. Terraform / AWS foundations

### Q: How is remote state handled?

**A:** `infra-live/_bootstrap` creates an S3 bucket + DynamoDB lock table
(account/region specific, e.g. `platform-tfstate-eun1-…`). Env stacks
(`infra-live/dev`) use that backend with **per-env state keys** so destroy of one
env does not wipe another.

### Q: What does the `dev` stack export?

**A:** VPC ID, public/private subnet IDs, Route53 zone ID/name, KMS ARN, OIDC
issuer URL, IRSA role ARNs (external-dns, cert-manager, CA, LBC, ESO, ebs-csi,
ArgoCD, …). Ansible/kOps consume these outputs when rendering the cluster spec.

### Q: Why IRSA instead of node instance profiles for add-ons?

**A:** Least privilege. Each controller gets its own IAM role bound to a
ServiceAccount via OIDC. Compromising one pod does not grant Route53 + ELB +
autoscaling to everything on the node.

### Q: Walk me through IRSA setup on kOps (not EKS).

**A:** Terraform creates:

1. S3-hosted OIDC discovery documents for the cluster issuer.
2. IAM OIDC provider (thumbprint = **TLS chain root**, not leaf — leaf rotates).
3. IAM roles with trust on `system:serviceaccount:<ns>:<sa>`.

kOps sets `serviceAccountIssuer` to that URL; **pod-identity-webhook** injects
the projected token + `AWS_ROLE_ARN`.

**Hard lesson (ADR 0005):** kOps tokens use audience **`amazonaws.com`**, not
EKS’s `sts.amazonaws.com`. Wrong audience → `InvalidIdentityToken`, CCM crash,
nodes stuck uninitialized, `kubectl logs` broken (no node IPs). Fix: accept both
audiences on provider + trust policies.

### Q: Why a private Route53 zone named `corp.example.internal`?

**A:** `.internal` is reserved (not publicly delegable). The brief’s example is
literally a private zone. Terraform creates it associated to the VPC;
**external-dns** (IRSA) writes records like `store` / `grafana` / `proof`.
Outside the VPC you map hosts locally to the NLB IP (see README).

### Q: Why didn’t you use public ACME / Let’s Encrypt?

**A:** ACME needs public DNS challenge control. Private `.internal` cannot be
validated on the public internet. We use a **platform self-signed CA** /
ClusterIssuer for TLS in-cluster (ADR 0002). Stage/prod overlays can point at
ACME issuers when a public domain exists — config change, not infra rewrite.

### Q: Secrets encryption — KMS provider or aescbc?

**A:** ADR 0003 — **aescbc** EncryptionConfiguration for Secret objects in etcd,
plus **KMS-encrypted EBS** for etcd volumes. Full `kms` provider needs a plugin
kOps does not manage; we avoided hand-rolling static pods on the control plane.
Secrets are encrypted at rest; envelope encryption to CMK per-object is the
documented trade-off.

### Q: Modules vs live — why split?

**A:** `infra-modules/` are versioned/reusable; `infra-live/{dev,stage,prod}` pin
module versions and hold env-specific values/backends. Matches “modules + live
stacks” in the brief. Stage/prod live stacks are skeletons; workloads share one
cluster as logical envs for the assignment timeline.

---

## 3. kOps + Ansible

### Q: Why kOps instead of EKS?

**A:** Brief requires kOps. It also forced us to own IRSA/OIDC ourselves (good
interview depth) instead of EKS “checkbox IRSA”.

### Q: Why Kubernetes 1.34.10, not latest?

**A:** ADR 0001 — “not latest” but still in upstream **n-2** support window.
1.34.10 is what kOps stable recommends for that line; add-ons are GA-compatible.
Shipping 1.33- would be unpatchable; shipping bleeding-edge 1.36 adds churn.

### Q: What does Ansible do vs what you click in AWS?

**A:**

| Playbook | Role |
|----------|------|
| `install-tools.yml` | Pin/install kops, kubectl, helm, argocd CLI |
| `cluster-create.yml` | Render cluster from TF outputs → kops create/update/validate |
| `argocd-bootstrap.yml` | Install ArgoCD Helm chart + IRSA wiring |

Idempotent: re-run reconciles rather than snowflake CLI history.

### Q: What must exist before ArgoCD? (bootstrap vs GitOps)

**A:** ADR 0004 — kOps owns the **cluster kernel**: Cilium, CoreDNS, cloud
controller, EBS CSI, metrics-server, pod-identity-webhook, cert-manager.
Without those, nodes never Ready / IRSA never works / PVCs Pending / HPA dead.
ArgoCD owns ingress, DNS controllers, policies, apps, observability.

### Q: Cluster version / rolling upgrade story?

**A:** Pin versions in `cluster-ops` inventory. Rolling update via kOps
(`kops rolling-update`) after kubelet hardening (anonymousAuth off, reserved
resources). Documented in evidence under `docs/evidence/03-cluster/`.

### Q: How do you tear it down safely?

**A:** README + `docs/runbooks/teardown.md`:

1. `kops delete cluster --yes`
2. `terraform destroy` in `infra-live/dev`
3. Bootstrap buckets last
4. Orphan check (EC2, k8s NLBs, EIPs)

---

## 4. ArgoCD / GitOps

### Q: Explain App-of-Apps.

**A:** Root Applications (`root-platform`, `root-dev`, `root-stage`, `root-prod`)
point at Git paths that declare child Applications. Children deploy Helm charts
or manifests. Sync waves order platform before apps (ingress before UI).

### Q: Sync policies — who can break prod?

**A:**

| Env | Policy |
|-----|--------|
| platform / dev | automated + prune + selfHeal |
| stage / prod | **manual** sync (no automated) |

AppProjects + RBAC: developers scoped to dev; release-managers sync stage/prod.
Prod apps intentionally left **OutOfSync / Missing** as the promotion-gate proof
(screenshot `02-prod-promotion-gate-…`).

### Q: What is selfHeal? Show me an example.

**A:** If someone `kubectl patch`es a live object away from Git, ArgoCD reverts
it. We demonstrated **misconfigured Ingress host** → OutOfSync → heal back to
`store.corp.example.internal` (~10s with auto-sync). Postmortem:
`docs/postmortems/2026-09-08-ingress-drift.md`.

### Q: How do you promote an image?

**A:** Copy the same `image.digest` from `gitops/values/apps/dev/<svc>.yaml` into
stage then prod via PR. Do **not** move `:latest`. Prove with
`./scripts/prove-digest-equality.sh`. Then manual Sync on stage → validate →
prod. Runbook: `docs/runbooks/promotion.md`.

### Q: Why digests instead of tags?

**A:** Tags are mutable. Digest (`sha256:…`) is content-addressed — what you
tested in dev is bitwise what stage/prod pull. Kyverno also blocks `:latest` /
untagged images.

### Q: Where does ArgoCD’s repo-server auth to AWS?

**A:** IRSA on repo-server / controller roles created in Terraform
(`argocd-iam` / IRSA modules), annotated on ServiceAccounts.

---

## 5. Applications / Helm

### Q: What apps did you deploy?

**A:** AWS Containers **retail-store-sample-app** microservices vendored into
`apps/charts/{ui,catalog,cart,checkout,orders}` — each with values overlays for
dev/stage/prod, `values.schema.json`, HPA, PDB, probes, requests/limits.

### Q: How does the UI reach backends?

**A:** ConfigMap env `RETAIL_UI_ENDPOINTS_*` → cluster DNS. Important bug we
fixed: Helm release creates Service **`cart-carts`**, not `cart`. Wrong name →
`UnknownHostException` → `/home` 500. Fixed in GitOps values and synced.

### Q: Ingress model?

**A:** Host-based: `store.corp.example.internal` → UI. TLS via cert-manager
platform CA secret `store-tls`. Path-based `/cart` fan-out was not the primary
pattern (UI is the BFF); backends are ClusterIP.

### Q: How do you reach the store from a laptop?

**A:** Private DNS is VPC-only. Public **NLB** fronting ingress-nginx; map NLB IP
in hosts file to `store.corp.example.internal` (Chrome cannot override `Host`
via extensions). README documents NLB hostname + curl `-H Host:…` proof.

### Q: HPA / PDB — what did you set?

**A:** HPA on CPU (e.g. target ~70%, min 2 / max 6 in dev). PDB
`minAvailable: 1` (not both min and max — Helm/K8s rejects that; we fixed it).

---

## 6. Security & policy

### Q: Admission control?

**A:** **Kyverno** policies: require CPU/memory limits, disallow `:latest`,
restrict privileged pods. Memory-pressure test: untagged stress image **blocked**;
digest-pinned stress Pod **OOMKilled** inside limit without taking down retail.
Postmortem: `docs/postmortems/2026-09-08-memory-pressure.md`.

### Q: Secrets management?

**A:** Encryption at rest (ADR 0003). **External Secrets Operator** preferred
over Sealed Secrets for AWS-native SM/SSM via IRSA (brief allowed either).

### Q: Network security?

**A:** Private subnets, security groups (API allow-list to operator IP), Cilium
ready for NetworkPolicies, NLB for ingress only — not NodePorts on the public
internet.

### Q: kubelet hardening?

**A:** Anonymous auth disabled, webhook authz, reserved resources; applied via
rolling update (evidence logs).

---

## 7. Observability & SLOs

### Q: What did you install?

**A:** `kube-prometheus-stack` in `monitoring` (GitOps). Grafana dashboards:
Retail storefront overview + Retail HPA detail. Screenshots under
`docs/screenshots/grafana/`.

### Q: Define your SLO.

**A:** **99.5% success** for the storefront (multi-window burn-rate
PrometheusRule). Recordings treat missing 5xx as zero so idle periods do not
false-alert. Rule YAML in evidence `07-observability/`.

### Q: How do you open Grafana?

**A:** Same NLB + Host `grafana.corp.example.internal` (hosts file), or
port-forward the Grafana Service. Credentials from the chart/secret (do not
paste passwords into email/chat).

---

## 8. Failure injection & operations

### Q: Failures you introduced?

**A:**

1. **Ingress misconfig** — live host → `broken…` → ArgoCD OutOfSync → Git/selfHeal
   restores. Shows drift detection.
2. **Resource pressure** — low memory stress Pod; Kyverno + OOM behaviour;
   retail stays healthy.

### Q: Cluster is down / IRSA broken — how do you debug?

**A:** Lessons from ADR 0005:

- CCM CrashLoop + uninitialized taints → check OIDC audience/thumbprint.
- If nodes lack InternalIP, use **SSM** to the instance — not `kubectl logs`.
- Decode SA token `aud` claim; compare to IAM OIDC `client_id_list`.

### Q: Rollback?

**A:** Git revert of values → ArgoCD sync (dev automatic). For cluster: kOps
previous AMI/version + rolling-update. For Terraform: state + prior module
version. Promotion runbook covers digest rollback (point overlays at previous
digest).

---

## 9. Process / repo / evaluation criteria

### Q: Why a monorepo?

**A:** One PR can change module + live + GitOps + charts coherently for review.
Split scripts can still publish five remotes later. Declared deviation in README.

### Q: How do you prove reproducibility?

**A:** Pinned versions in Ansible inventory; Makefile/playbook entrypoints;
evidence logs `docs/evidence/01–09`; digest script; ADRs for non-obvious choices.

### Q: What would you do with more time?

**A:** Honest list (interviewers like this):

- Wire Slack notifications on sync fail / manual sync required
- Real separate stage/prod clusters (not only namespaces)
- Public domain + ACME DNS-01
- Path-based ingress demo if required literally
- `cluster-upgrade.yml` / `cluster-destroy.yml` Ansible wrappers
- Split to five Git remotes

### Q: Cost control?

**A:** Spot workers, teardown runbook after walkthrough, NAT count trade-off,
destroy order documented. Submission email states we destroy after demo.

---

## 10. Live demo script (suggested order)

1. **GitHub README** — layout, access, teardown, screenshot links.
2. **ArgoCD UI** — platform Synced; `retail-ui` tree; prod OutOfSync gate.
3. **Storefront** — hosts file → `/home` → product page.
4. **Grafana** — storefront overview + HPA.
5. **Terminal** — `kubectl get nodes,hpa,ingress -A`; `./scripts/prove-digest-equality.sh`.
6. **Optional** — show ADR 0005 / postmortem for depth.
7. **Close** — teardown commands in README; will run after session.

---

## 11. Quick “trap” questions

| Trap | Short answer |
|------|----------------|
| “Just use EKS” | Brief required kOps; IRSA-on-kOps was the interesting part. |
| “ACME?” | Private `.internal` → self-signed CA; ACME when public DNS exists. |
| “Five repos?” | Monorepo by choice; documented; same components. |
| “Is prod deployed?” | Gate proof: apps Missing/OutOfSync until manual Sync. |
| “NLB 404?” | Host header / hosts file required — Ingress host match. |
| “Who is Cursor contributor?” | Co-authored-by stripped; author is you. |
| “Sealed Secrets?” | ESO + IRSA instead (allowed alternative). |

---

## 12. Where to point for proof

| Topic | Pointer |
|-------|---------|
| K8s version | `docs/adr/0001-kubernetes-version.md` |
| DNS / TLS | `docs/adr/0002-dns-topology.md` |
| Secret encryption | `docs/adr/0003-secrets-encryption.md` |
| Bootstrap vs GitOps | `docs/adr/0004-bootstrap-vs-gitops.md` |
| IRSA audience | `docs/adr/0005-irsa-token-audience.md` |
| Promotion | `docs/runbooks/promotion.md` |
| Teardown | `docs/runbooks/teardown.md` |
| Failures | `docs/postmortems/` |
| Screenshots | `docs/screenshots/` |
| CLI evidence | `docs/evidence/` |

---

*End of mock. Rehearse the elevator pitch + demo script out loud once.*
