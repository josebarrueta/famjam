# FamJam TypeScript API

Fastify reference backend for `../http-api.md`. It uses PostgreSQL for scalable,
shared persistence, Redis 8.10 for shared caching and vector-search readiness, and Stytch B2C for Google-capable
identity verification. FamJam
roles and family membership remain in PostgreSQL, so identity providers stay
replaceable.

## Development

Requirements: Node 20+, PostgreSQL, and a Stytch test project.

```bash
cp .env.example .env
# Fill in all STYTCH_* values and register famjam://oauth-callback in Stytch.
docker compose up --build
```

The compose stack starts PostgreSQL and Redis, applies the schema to a fresh
PostgreSQL volume, and exposes the API at `http://localhost:3000`. For development outside Docker:

```bash
npm install
npm test
npm run typecheck
cat migrations/*.sql | psql "$DATABASE_URL" -v ON_ERROR_STOP=1
npm run dev
```

All Stytch integration and configuration is backend-owned. Never add Stytch
credentials, tokens, or SDKs to the iOS app, and never commit `.env`.

Verified Stytch identities are cached for 60 seconds and evicted on sign-out.
Normalized Google Places searches are cached for 30 minutes using hashed keys.
Redis is used when `REDIS_URL` is set; otherwise a process-local cache is used.

US address autocomplete uses Google Places when `GOOGLE_PLACES_API_KEY` is set.
Enable **Places API (New)** in Google Cloud and restrict the key to that API. If the
key is omitted, manual location entry still works and autocomplete returns no
suggestions.

## Push notifications

Set `APNS_KEY_ID`, `APNS_TEAM_ID`, `APNS_BUNDLE_ID`, `APNS_PRIVATE_KEY`, and
`APNS_ENV` to enable Apple Push Notification service delivery. The `.p8` private
key stays backend-only; encode line breaks as `\\n` when the deployment platform
requires a single-line secret. Without these values, device registration remains
available but delivery uses the no-op adapter.

## Account provisioning

A first-time Google identity without an invitation is provisioned just in time as
the parent of a new family. Provisioning creates the member and identity mapping
in one transaction and is idempotent across retries. Parents can create, list, cancel, and securely resend single-use, seven-day
invitations for another parent or kid. Resending rotates the code rather than
recovering its stored hash. Redeeming an invitation during Google sign-in
atomically provisions the new member
into the inviter's family; family IDs and invited roles are never client-selected.

## Architecture

- `IdentityProvider` — verifies external identity; Stytch is the first adapter.
- `FamJamRepository` — persistence seam; PostgreSQL and in-memory adapters exist.
- `buildApp` — HTTP handler seam used by integration tests.
- Authorization is enforced server-side for every route.
