# Rallyroo TypeScript API

Fastify reference backend for `../http-api.md`. It uses PostgreSQL for scalable,
shared persistence, Redis 8.10 for shared caching and vector-search readiness, and Stytch B2C for Apple and Google
identity verification. Rallyroo
roles and family membership remain in PostgreSQL, so identity providers stay
replaceable.

## Development

Requirements: Node 20+, PostgreSQL, and a Stytch test project.

```bash
cp .env.example .env
# Fill in all STYTCH_* values, enable Apple and Google OAuth in Stytch,
# and register rallyroo://oauth-callback as an allowed redirect URL.
docker compose up --build
```

The compose stack starts PostgreSQL and Redis, applies the schema to a fresh
PostgreSQL volume, and exposes the API at `http://localhost:3000`. The production
image also includes the ordered migration runner used by the Helm deployment.
For development outside Docker:

```bash
npm install
npm test
npm run typecheck
cat migrations/*.sql | psql "$DATABASE_URL" -v ON_ERROR_STOP=1
npm run dev
```

Unit tests do not require infrastructure. Integration tests create and migrate a
temporary PostgreSQL database and use namespaced Redis keys:

```bash
npm run test:unit
INTEGRATION_DATABASE_URL=postgres://rallyroo:rallyroo@localhost:5432/postgres \
INTEGRATION_REDIS_URL=redis://localhost:6379 \
npm run test:integration
```

GitHub Actions runs these as separate quality and service-backed integration jobs
using PostgreSQL 17 and Redis 8.10.1.

All Stytch integration and configuration is backend-owned. Never add Stytch
credentials, tokens, or SDKs to the iOS app, and never commit `.env`.

Verified Stytch identities are cached for 60 seconds and evicted on sign-out.
Normalized Google Places searches are cached for 30 minutes using hashed keys.
Redis is used when `REDIS_URL` is set; otherwise a process-local cache is used.

US address autocomplete uses Google Places when `GOOGLE_PLACES_API_KEY` is set.
Enable **Places API (New)** in Google Cloud and restrict the key to that API. If the
key is omitted, manual location entry still works and autocomplete returns no
suggestions.

## Production operations

The API writes structured JSON request logs with request IDs, status codes, and
response duration. Authorization and cookie headers are redacted. Configure
verbosity with `LOG_LEVEL` (default `info`).

- `/health` reports process liveness without checking dependencies.
- `/ready` checks PostgreSQL; Redis remains an optional accelerator.
- `/metrics` exports Prometheus request, cache, and external-provider metrics.

Set a strong `METRICS_BEARER_TOKEN` in hosted environments. Session exchange,
invitation writes, and Places search have stricter route limits under a global
request ceiling. Rate-limited responses include `Retry-After`.

## Invitation email

Only authenticated parents can create or resend invitations. Configure the reference
Resend adapter with `RESEND_API_KEY` and a verified sender in
`INVITATION_EMAIL_FROM`, for example `Rallyroo <invites@yourdomain.com>`. The API
stores recipient addresses with pending invitations, rotates codes on resend, and
rolls back invitation state when delivery fails. Email delivery remains behind the
provider-neutral `InvitationEmailSender` interface.

## Push notifications

Set `APNS_KEY_ID`, `APNS_TEAM_ID`, `APNS_BUNDLE_ID`, `APNS_PRIVATE_KEY`, and
`APNS_ENV` to enable Apple Push Notification service delivery. The `.p8` private
key stays backend-only; encode line breaks as `\\n` when the deployment platform
requires a single-line secret. Without these values, device registration remains
available but delivery uses the no-op adapter.

## Account provisioning

A first-time Apple or Google identity without an invitation is provisioned just in time as
the parent of a new family. Provisioning creates the member and identity mapping
in one transaction and is idempotent across retries. Parents can create, list, cancel, and securely resend single-use, seven-day
invitations for another parent or kid. Resending rotates the code rather than
recovering its stored hash. Redeeming an invitation during Apple or Google sign-in
atomically provisions the new member
into the inviter's family; family IDs and invited roles are never client-selected.

## Architecture

- `IdentityProvider` — verifies external identity; Stytch is the first adapter.
- `RallyrooRepository` — persistence seam; PostgreSQL and in-memory adapters exist.
- `buildApp` — HTTP handler seam used by integration tests.
- Authorization is enforced server-side for every route.
