# ADR 0002: None-DNS cluster plus a Route53 private hosted zone

**Status:** Accepted
**Date:** 2026-09-07

## Context

The brief asks for a "Route53 hosted zone (e.g., `corp.example.internal`)" and states
that "kOps will use Route53". It also asks for external-dns and for cert-manager with
ACME issuers.

Two facts constrain the design.

**First, `corp.example.internal` can never be publicly resolvable.** ICANN board
resolution [2024.07.29.06](https://www.icann.org/en/board-activities-and-meetings/materials/approved-resolutions-special-meeting-of-the-icann-board-29-07-2024-en)
permanently reserved `.internal` from delegation in the DNS root zone, as the DNS
analogue of RFC1918 address space. No registrar sells it and no public resolver will
ever answer for it. The brief's own example domain therefore *specifies* a private
hosted zone — using one is compliance, not a workaround.

**Second, no public domain is registered for this account.** Route53 held zero hosted
zones and zero registered domains at the start of the build.

## Decision

1. The kOps cluster is named **`dev.k8s.local`**, which selects **None-DNS** topology.
2. Terraform creates a Route53 **private** hosted zone for **`corp.example.internal`**,
   associated with the dev VPC.
3. external-dns writes into that private zone using IRSA.
4. cert-manager issues from a **self-signed root CA** in dev. `letsencrypt-staging` and
   `letsencrypt-prod` `ClusterIssuer`s are committed and referenced by the stage and
   prod overlays.
5. Internal hostnames are reached from outside the VPC over an **SSH SOCKS5 tunnel
   through the bastion**, not by exposing them.

## Rationale

### Why None-DNS rather than a registered domain

Since kOps 1.26, a cluster whose name ends in `.k8s.local` uses None-DNS: kOps publishes
no DNS records and instead writes the API Network Load Balancer's AWS-assigned hostname
straight into the kubeconfig. `kubectl` works from anywhere with no domain involved.
(Gossip DNS, the older mechanism for this, is deprecated and was removed entirely in
kOps 1.37 — None-DNS is its supported successor.)

This removes the domain from the critical path of cluster creation entirely, which
matters because a registration failure would have blocked every downstream task.

### What still needs to be reachable, and how it is

Nothing requires the private zone to resolve publicly. Every endpoint a human or CI job
must reach already receives a publicly-resolvable AWS hostname:

| Endpoint | Reached via |
|---|---|
| Kubernetes API | None-DNS NLB hostname in kubeconfig |
| Bastion | Public IP in a public subnet, SSH locked to the operator's egress IP |
| Retail storefront | ingress-nginx NLB hostname |
| ArgoCD / Grafana / Prometheus | Private zone names, over the bastion SOCKS tunnel |

The private zone's purpose is to prove external-dns and IRSA work, evidenced with
`aws route53 list-resource-record-sets` and `dig` from inside the VPC.

### Why tunnel instead of expose

A Route53 Resolver inbound endpoint is the production answer for resolving a private
zone from outside the VPC, but it bills two ENIs at $0.125/hour — roughly **$182.50 per
month** — which is indefensible here. An `ssh -D 1080` SOCKS5 proxy through the bastion,
with the browser configured for remote DNS (`socks5h`, so lookups resolve inside the
VPC), costs nothing and takes two minutes.

It is also **the better security posture, not merely the cheaper one**. Publishing
ArgoCD and Grafana to the open internet would be a genuine finding. Admin planes stay
private and are reached over the bastion; only the storefront is public.

### Why self-signed CA for TLS in dev

ACME validates domain control over the public internet. With no public domain, neither
the Let's Encrypt staging nor production issuer can complete a challenge. Rather than
ship issuers that cannot work, dev runs a real cert-manager chain — a self-signed root
issuing a `platform-ca`, which issues leaf certificates for
`*.dev.corp.example.internal`. The full cert-manager lifecycle (Certificate, CertificateRequest,
Order, Secret, renewal) is genuinely exercised; only the ACME challenge is substituted.

## Consequences

- Browsers show a certificate warning for internal hostnames unless the CA is trusted;
  the runbook documents importing it.
- If a public domain is registered later, the change is contained: swap the `dns` module
  to a public zone, point external-dns at it, and switch the overlay `ClusterIssuer`
  reference. The cluster itself needs no change, because None-DNS is independent of it.
- The cluster name `dev.k8s.local` is immutable. Moving to a domain-named cluster would
  require a rebuild.
