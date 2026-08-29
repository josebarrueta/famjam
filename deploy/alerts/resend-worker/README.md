# Rallyroo deployment alert adapter

This Cloudflare Worker is the narrow protocol boundary between Flux and Resend:

1. Flux sends a `generic-hmac` HelmRelease error event.
2. The Worker verifies the exact request body using `X-Signature` and
   `FLUX_HMAC_SECRET`.
3. It accepts only `HelmRelease/rallyroo` errors from the `rallyroo` namespace.
4. It reduces the event and calls Resend's `deployment.failed` custom event.
5. A Resend Automation owns recipient delivery and the published email template.

The Worker does not render or send email itself. It has no access to Kubernetes,
PostgreSQL, the Rallyroo API, or the Cloudflare Tunnel.

## Required Worker secrets

- `FLUX_HMAC_SECRET` — shared only with Flux's `generic-hmac` Provider.
- `RESEND_API_KEY` — sending-only and domain-restricted when possible.
- `ALERT_RECIPIENT` — contact used to trigger the Resend Automation.

Never commit these values or put them in Wrangler `vars`. The committed
`wrangler.jsonc` declares the required names only.

## Development

```bash
npm ci
npm test
npm run typecheck
npm run deploy:dry-run
```

The production endpoint is the Worker Custom Domain `alerts.rallyroo.dev`;
`workers.dev` and preview URLs are disabled. Only `/health` and `/flux` exist.
`/flux` requires a valid HMAC and rejects non-error, non-Rallyroo events. Resend
failures return `502` so Flux can treat the delivery as failed rather than silently
accepting it.

## Setup

From the repository root, run the repeatable interactive wizard:

```bash
./deploy/alerts/setup-alerting.sh
```

It performs Cloudflare login, walks through the Resend template and Automation,
uploads Worker secrets without writing them into the repository, configures the
Kubernetes Secret, and sends a signed end-to-end test event.

If initial deployment completed but Custom Domain DNS propagation ended the wizard
before Flux was connected, resume without re-entering the Resend key:

```bash
./deploy/alerts/connect-flux.sh
```

The resume wizard rotates only the HMAC secret. Wrangler preserves the existing
Resend secrets omitted from that deployment.
