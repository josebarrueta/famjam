# Deployment architecture decision journal

This journal records why Rallyroo's maintainers made its deployment decisions. It describes this repository's supported path, not universal rules. Other open-source users can adopt the whole design or use the trade-offs as input for their own environment.

## 2026-08-27 — Isolate local Kubernetes from other clusters

**Decision:** Rallyroo runs in a dedicated kind cluster, context, kubeconfig, namespace, and data directory. Deployment scripts always name the context instead of relying on the operator's current context.

**Why:** A maintainer may already have access to production or customer clusters. Isolation makes an accidental deployment to another context much less likely and gives the project a reproducible local target.

**Suggestion for other projects:** Treat kubeconfig selection as a safety boundary. Dedicated credentials and explicit contexts are inexpensive even when the target is only a development machine.

## 2026-08-27 — Persist state outside the disposable kind cluster

**Decision:** PostgreSQL and Redis data live under `~/.rallyroo/data` and are mounted into the kind node. Deleting the cluster does not delete application data.

**Why:** kind nodes are replaceable infrastructure, while PostgreSQL is authoritative application state. Redis persistence improves restart behavior but remains a cache that can be rebuilt from PostgreSQL.

**Suggestion for other projects:** Document separately how to destroy compute and how to destroy data. Never make a routine cluster reset silently become a database reset.

## 2026-08-27 — Publish only the application image

**Decision:** Rallyroo builds its API image and references public, pinned PostgreSQL, Redis, and unprivileged NGINX images instead of repackaging them.

**Why:** Rebuilding upstream infrastructure images would add maintenance and supply-chain responsibilities without changing their behavior. The application image is the only project-owned runtime artifact.

**Suggestion for other projects:** Build an image only when you own its contents or need a reviewed customization. Pin upstream versions and test upgrades in CI.

## 2026-08-27 — Expose only loopback NGINX through Cloudflare Tunnel

**Decision:** Kubernetes maps NGINX to `127.0.0.1:8080`; Cloudflare Tunnel forwards public HTTPS traffic to that HTTP loopback origin. PostgreSQL, Redis, Kubernetes, metrics credentials, and the Docker socket are never public. Router port forwarding and local TLS are not used.

**Why:** Cloudflare terminates trusted public TLS, the connector and origin share one host, and loopback is not reachable from the LAN. Local TLS would add certificate operations without protecting a network hop. NGINX provides one auditable public boundary and keeps API error behavior stable.

**Suggestion for other projects:** Minimize public ingress before adding authentication to internal services. If the tunnel and origin cross hosts or an untrusted network, use authenticated TLS for that hop instead.

## 2026-08-27 — Use immutable semantic-version release artifacts

**Decision:** A `vX.Y.Z` Git tag publishes matching API and OCI Helm chart versions to GHCR. Stable releases additionally update `latest`, but deployments select semantic chart versions rather than `latest`. The release workflow publishes the chart only after all image variants exist.

**Why:** Git tags provide a reviewable release source of truth. Immutable version tags make diagnosis and rollback deterministic. Publishing the chart last makes it a promotion signal: consumers never discover a chart whose application image is incomplete.

**Suggestion for other projects:** Separate artifact construction from promotion, even if both happen in one workflow. The final promoted artifact should reference only artifacts that are already available.

## 2026-08-27 — Build multi-architecture images on native runners

**Decision:** GitHub-hosted AMD64 and ARM64 Linux runners build their matching image variants. A later job combines the digests into one multi-platform manifest. QEMU is not used.

**Why:** The deployment host is ARM64, common servers are AMD64, and an earlier emulated ARM build failed with an illegal instruction. Native jobs retain portability without accepting emulation instability or giving a self-hosted runner access to the home Docker socket.

**Suggestion for other projects:** Match published image platforms to real deployment nodes. Prefer native builders when hosted runners are available; emulation is useful, but it should not be the only path for a production artifact.

## 2026-08-27 — Pull releases with Flux instead of receiving deployment webhooks

**Decision:** Flux `OCIRepository` polls the public GHCR chart once per minute. `HelmRelease` performs upgrades, readiness waiting, tests, retries, rollback remediation, and drift correction. Rallyroo automatically accepts patch releases in the selected minor series; changing minor series requires an explicit manifest change.

**Why:** Pull reconciliation works through outbound HTTPS, survives missed notifications, and does not add an internet-facing deployment endpoint or custom webhook service. Patch-only selection balances unattended security/fix delivery with deliberate compatibility changes.

**Suggestion for other projects:** Start with polling unless seconds of deployment latency are materially important. A webhook should accelerate reconciliation, not be the only event delivery mechanism.

## 2026-08-27 — Constrain application reconciliation to its namespace

**Decision:** The Rallyroo `HelmRelease` impersonates a dedicated service account with full access inside only the `rallyroo` namespace. It cannot create cluster-scoped resources or modify another namespace.

**Why:** Flux's default Helm controller identity is highly privileged. The Rallyroo chart needs broad namespaced operations for Helm storage, workloads, services, jobs, secrets, and persistent volume claims, but it needs no cluster-wide authority.

**Suggestion for other projects:** Set `serviceAccountName` on every Helm release. Start with namespace isolation, then narrow resource and verb permissions further when the chart's API surface is stable.

## 2026-08-27 — Sanitize OCI revisions before using them as Kubernetes labels

**Decision:** The Helm chart label helper replaces `+` in chart versions and truncates the result to Kubernetes' label length limit. CI packages and renders a chart containing SemVer build metadata to preserve this contract.

**Why:** Flux appends an OCI digest to a chart version as SemVer build metadata, such as `0.1.2+abcdef`. The full revision is valid SemVer but `+` is invalid in a Kubernetes label value. The first Flux adoption exposed this mismatch in the migration hook before workloads changed; version `0.1.1` remains immutable and `0.1.2` contains the correction.

**Suggestion for other projects:** Test charts with the exact revisions produced by the deployment controller, not only the source `Chart.yaml` version. Artifact identifiers often have a wider character set than Kubernetes names and labels.

## 2026-08-27 — Gate upgrades with forward-only database migrations

**Decision:** First installation retains an API init container because PostgreSQL is created by the same chart. Every later Helm upgrade runs the new API image's migration script in a blocking `pre-upgrade` Job. Migrations are transactional, recorded in `schema_migrations`, and serialized by a PostgreSQL advisory lock.

**Why:** A pre-install hook cannot reach PostgreSQL before this combined chart creates it. On upgrades PostgreSQL already exists, so a hook can fail the release before application workloads change. The init container remains an idempotent safety net.

**Consequence:** Application rollback does not reverse schema changes. Automated migrations must use expand/contract sequencing: add compatible schema, deploy compatible code, backfill when needed, stop using old schema, and remove it only in a later release. Destructive changes require explicit review and a verified backup.

**Suggestion for other projects:** Make migration success a rollout gate, but design the database for both the old and new application during rolling deployment and rollback. If database infrastructure has a separate lifecycle, a `pre-install,pre-upgrade` migration Job can replace the first-install init-container compromise.

## 2026-08-27 — Define release success beyond pod startup

**Decision:** Kubernetes readiness gates traffic, and a Helm test calls the API `/ready` endpoint after installation or upgrade. Flux treats test failure as release failure and remediates the upgrade.

**Why:** A running process is not necessarily connected to its required database or able to serve its contract. The Helm test turns application-level readiness into recorded release status.

**Suggestion for other projects:** Keep liveness shallow, readiness dependency-aware, and post-deployment tests small enough to run on every release.
