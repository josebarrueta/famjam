# FamJam local Kubernetes deployment

The Helm chart runs the API, PostgreSQL 17, Redis 8.10.1, and an unprivileged
NGINX edge proxy. The local profile uses a dedicated kind cluster and exposes
NGINX only on `127.0.0.1:8080`; it does not modify or deploy to an existing cloud
Kubernetes context.

## Requirements

- Docker Desktop
- `kubectl`
- Helm 3 or 4
- kind
- `server/api/.env` with valid Stytch test credentials

On macOS, install missing tools with `brew install helm kind`.

## Deploy locally

```bash
cp server/api/.env.example server/api/.env
# Configure STYTCH_* and any optional Resend, Places, or APNs credentials.
./deploy/local/deploy-local.sh
curl http://127.0.0.1:8080/health
curl http://127.0.0.1:8080/ready
```

The script uses a dedicated `~/.famjam/kubeconfig`, so it never selects or authenticates
to Kubernetes clusters in the default kubeconfig.

The script:

1. creates the isolated `kind-famjam` context if needed;
2. mounts `~/.famjam/data` into the cluster for durable PostgreSQL and Redis data;
3. builds and loads `famjam-api:local` without requiring a registry;
4. creates the provider/runtime Kubernetes Secret outside Helm values;
5. installs or upgrades the chart and waits for readiness.

Database migrations are bundled into the API image, serialized with a PostgreSQL
advisory lock, and recorded in `schema_migrations` before each API pod starts.
Running the script again is safe and performs a Helm upgrade.

Inspect the release without relying on the current kubectl context:

```bash
kubectl --kubeconfig ~/.famjam/kubeconfig --context kind-famjam -n famjam get all
kubectl --kubeconfig ~/.famjam/kubeconfig --context kind-famjam -n famjam logs deployment/famjam-api
helm --kubeconfig ~/.famjam/kubeconfig --kube-context kind-famjam -n famjam status famjam
```

Delete the cluster while retaining local database files:

```bash
./deploy/local/delete-local.sh
```

Delete `~/.famjam/data` separately only when a full data reset is intended.

## Domain hosting later

Keep the first milestone loopback-only. For a real domain, the preferred home-hosted
path is a Cloudflare Tunnel terminating TLS and forwarding to NGINX. It avoids
opening router ports and works with changing residential IP addresses. Direct DNS
plus router port-forwarding is possible, but requires a stable public IP, firewall
rules, TLS automation, and confirmation that the ISP permits inbound hosting.
Never expose PostgreSQL, Redis, Kubernetes, or the Docker socket—only NGINX.
