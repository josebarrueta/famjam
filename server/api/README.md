# FamJam TypeScript API

Fastify reference backend for `../http-api.md`. It uses PostgreSQL for scalable,
shared persistence and Stytch B2C for Google-capable identity verification. FamJam
roles and family membership remain in PostgreSQL, so identity providers stay
replaceable.

## Development

Requirements: Node 20+, PostgreSQL, and a Stytch test project.

```bash
cp .env.example .env
# Fill in all STYTCH_* values and register famjam://oauth-callback in Stytch.
docker compose up --build
```

The compose stack starts PostgreSQL, applies the initial schema to a fresh volume,
and exposes the API at `http://localhost:3000`. For development outside Docker:

```bash
npm install
npm test
npm run typecheck
psql "$DATABASE_URL" -f migrations/001_initial.sql
npm run dev
```

All Stytch integration and configuration is backend-owned. Never add Stytch
credentials, tokens, or SDKs to the iOS app, and never commit `.env`.

## Account provisioning

A first-time Google identity without an invitation is provisioned just in time as
the parent of a new family. Provisioning creates the member and identity mapping
in one transaction and is idempotent across retries. Future family invitations
will provision additional parents or kids into an existing family instead.

## Architecture

- `IdentityProvider` — verifies external identity; Stytch is the first adapter.
- `FamJamRepository` — persistence seam; PostgreSQL and in-memory adapters exist.
- `buildApp` — HTTP handler seam used by integration tests.
- Authorization is enforced server-side for every route.
