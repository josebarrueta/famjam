# FamJam TypeScript API

Fastify reference backend for `../http-api.md`. It uses PostgreSQL for scalable,
shared persistence, Redis for shared caching, and Stytch B2C for Google-capable
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
psql "$DATABASE_URL" -f migrations/001_initial.sql
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

## Account provisioning

A first-time Google identity without an invitation is provisioned just in time as
the parent of a new family. Provisioning creates the member and identity mapping
in one transaction and is idempotent across retries. Parents can create single-use, seven-day invitations for another parent or kid.
Redeeming an invitation during Google sign-in atomically provisions the new member
into the inviter's family; family IDs and invited roles are never client-selected.

## Architecture

- `IdentityProvider` — verifies external identity; Stytch is the first adapter.
- `FamJamRepository` — persistence seam; PostgreSQL and in-memory adapters exist.
- `buildApp` — HTTP handler seam used by integration tests.
- Authorization is enforced server-side for every route.
