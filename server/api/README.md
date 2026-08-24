# FamJam TypeScript API

Fastify reference backend for `../http-api.md`. It uses PostgreSQL for scalable,
shared persistence and Stytch B2C for Google-capable identity verification. FamJam
roles and family membership remain in PostgreSQL, so identity providers stay
replaceable.

## Development

Requirements: Node 20+, PostgreSQL, and a Stytch test project.

```bash
cp .env.example .env
# Fill in STYTCH_PROJECT_ID and STYTCH_SECRET.
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

The Stytch secret is server-only. Never add it to the iOS app or commit `.env`.

## Provisioning the first parent

After a user authenticates with Google through Stytch, insert a family member and
map the Stytch `user_id` to it in one transaction:

```sql
BEGIN;
INSERT INTO family_members (family_id, id, name, role, color_tag)
VALUES ('my-family', 'parent-1', 'Alex', 'parent', 'blue');
INSERT INTO accounts (identity_subject, family_id, member_id, role)
VALUES ('user-test-from-stytch', 'my-family', 'parent-1', 'parent');
COMMIT;
```

Automated family onboarding/invitations will replace this bootstrap step later.

## Architecture

- `IdentityProvider` — verifies external identity; Stytch is the first adapter.
- `FamJamRepository` — persistence seam; PostgreSQL and in-memory adapters exist.
- `buildApp` — HTTP handler seam used by integration tests.
- Authorization is enforced server-side for every route.
