# ADR 0003: Encrypt Kubernetes Secrets at rest with aescbc, not the KMS provider

- **Status:** Accepted
- **Date:** 2026-09-07
- **Applies to:** `cluster-ops/roles/kops_cluster`, `infra-modules/kms`

## Context

By default the API server stores `Secret` objects in etcd base64-encoded, which
is encoding, not encryption. Anyone who obtains an etcd snapshot — an EBS
snapshot, a backup bucket, a stolen volume — obtains every credential in the
cluster in plaintext.

Kubernetes offers two relevant `EncryptionConfiguration` providers:

- `kms`, which calls out to an external key management plugin per key, giving
  envelope encryption rooted in a customer-managed KMS key.
- `aescbc`, which encrypts locally with a key held in the API server's
  configuration.

The `kms` provider is the stronger option on paper and the obvious thing to
reach for given we already have a platform CMK. It requires a `kms-plugin`
gRPC socket running on every control-plane node, wired into the API server via
`--encryption-provider-config`. kOps does not ship or manage such a plugin, so
adopting it would mean a static pod delivered through `additionalUserData`,
plus its own upgrade and failure story — on a control plane we do not otherwise
hand-manage.

## Decision

Enable `encryptionConfig: true` with an **aescbc** provider, and rely on the
platform CMK to protect the medium rather than the individual objects:

```yaml
resources:
  - resources: [secrets]
    providers:
      - aescbc:
          keys:
            - name: key1
              secret: <32-byte key>
      - identity: {}
```

Provider order matters. `aescbc` is listed first, so it is used for writes;
`identity` second so any Secret written before encryption was enabled can still
be read. Reversing them silently disables encryption for new writes while
appearing to work.

Defence in depth comes from the layer below: every etcd volume is encrypted
with the customer-managed KMS key (`encryptedVolume: true` plus `kmsKeyId` on
each etcd member), and both etcd clusters take managed backups. So an attacker
needs both the EBS volume — protected by KMS, with key usage recorded in
CloudTrail — and the API server configuration.

The key is generated once and then left alone. The Ansible role checks for an
existing `encryptionconfig` secret before generating, because regenerating on
every run would make every existing Secret in etcd undecryptable.

## Consequences

- Secrets are encrypted at rest in etcd, and the etcd volumes themselves are
  encrypted with a rotating customer-managed CMK.
- Key rotation is manual: it means adding a second key to the provider list,
  restarting the API servers, and rewriting all Secrets
  (`kubectl get secrets -A -o json | kubectl replace -f -`). Acceptable for a
  dev environment; a production platform should either take on the kms plugin
  or automate this.
- The aescbc key lives in the kOps state store, so that bucket is as sensitive
  as etcd itself. It is versioned, encrypted, and private, and the assignment's
  requirement that state buckets be locked down applies to it directly.
- If this platform later moves to EKS, the KMS provider is available natively
  and this decision should be revisited.
