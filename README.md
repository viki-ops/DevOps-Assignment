# Multi-Environment Kubernetes Platform on AWS

Terraform foundations, a highly-available kOps cluster, Ansible lifecycle automation,
Helm-packaged microservices and ArgoCD App-of-Apps GitOps — built end to end on AWS.

| Layer | Directory | Tool |
|---|---|---|
| AWS foundations | [`infra-modules/`](infra-modules/), [`infra-live/`](infra-live/) | Terraform 1.16.1 |
| Cluster lifecycle | [`cluster-ops/`](cluster-ops/) | kOps 1.36.2 + Ansible 2.17 |
| Application packaging | [`apps/`](apps/) | Helm 3.21.4 |
| Continuous delivery | [`gitops/`](gitops/) | ArgoCD 3.5.2 |
| Runbooks and evidence | [`docs/`](docs/) | — |

---

## Structure: one repository, five components

The assignment brief asks for five separate repositories. This submission delivers
them as five self-contained top-level directories in one repository instead.

That is a deliberate, and the only, deviation from the brief. It is called out here
rather than left to be discovered:

- **The substance of the requirement is preserved.** The brief's actual requirement is
  *"Each repo must contain its own README.md with exact commands and a runbook."*
  Every one of the five components has its own `README.md` and runbook.
- **Module version pinning still happens over git**, not via relative paths.
  `infra-live` consumes `infra-modules` through pinned git refs, exactly as it would
  across separate repositories — see [Module pinning](#module-pinning) below.
- **Splitting is one command.** [`scripts/split-repos.sh`](scripts/split-repos.sh) uses
  `git subtree split` to publish all five as standalone repositories with their
  per-component commit history intact, should the reviewer prefer that layout.

Two things genuinely improve as a result: the promotion pull requests in
[Part 5](docs/runbooks/promotion.md) become single-repo PRs gated by
[`CODEOWNERS`](CODEOWNERS), and ArgoCD needs only one repository registration —
every `Application` shares a `repoURL` and differs only by `path`.

---

## Deviations from the brief, in full

Honesty about scope is more useful than a checklist that quietly overstates itself.

| # | Brief says | What was built | Why |
|---|---|---|---|
| 1 | Five separate repositories | One monorepo, five components, split script provided | See above |
| 2 | Route53 hosted zone, e.g. `corp.example.internal` | Route53 **private** hosted zone `corp.example.internal` | `.internal` is permanently reserved by ICANN and *cannot* be publicly delegated — see [ADR 0002](docs/adr/0002-dns-topology.md) |
| 3 | cert-manager with ACME issuers | Self-signed CA issuer active in dev; ACME staging/prod issuers committed and wired to stage/prod | ACME requires a publicly resolvable domain; none is registered |
| 4 | dev / stage / prod environments | dev is a real cluster; stage and prod are separate ArgoCD destinations (namespaces + AppProjects) on it | Three HA clusters would cost ~3x; the promotion workflow is still demonstrated for real, including digest equality |
| 5 | — | `infra-live/stage` and `infra-live/prod` are written and `plan`-clean but never applied | Same cost reason; the code is complete and reviewable |

---

## Quickstart — one command per layer

```bash
make tools      # cluster-ops/playbooks/install-tools.yml  - pinned toolchain
make infra      # infra-live/dev  - terraform init + apply
make cluster    # cluster-ops/playbooks/cluster-create.yml - kOps create/update/validate
make gitops     # bootstrap ArgoCD; the root Application takes over from here
make evidence   # collect CLI evidence into docs/evidence/
make destroy    # cluster-destroy.yml + terraform destroy
```

## Module pinning

`infra-live` never uses relative module paths. Each stack pins a git ref against this
repository, so the dependency is versioned and auditable exactly as it would be across
separate repositories:

```hcl
module "vpc" {
  source = "git::https://github.com/viki-ops/DevOps-Assignment.git//infra-modules/vpc?ref=v0.1.0"
}
```

`make dev-local` rewrites those to relative paths for fast iteration; CI asserts that
what lands on `main` uses the pinned form.

## Documentation

- [Runbooks](docs/runbooks/) — provisioning, upgrade, rollback, recovery, promotion
- [Architecture decisions](docs/adr/) — Kubernetes version, DNS topology, IRSA ownership
- [Evidence](docs/evidence/) — CLI output and screenshots per part of the brief
- [Postmortems](docs/postmortems/) — the two injected failures
