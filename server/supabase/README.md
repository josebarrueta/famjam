# Supabase backend adapter

This directory is intentionally empty during the local-first iOS phase. Supabase is
an optional backend implementation: the iOS client depends on the `EventStore`
contract in `clients/ios`, never on Supabase types or SDKs.

When cloud sync begins, keep all Supabase resources here:

- `migrations/` — versioned Postgres schema and row-level-security policies.
- `functions/` — Deno Edge Functions, including email extraction and notifications.

Do not store credentials in this repository. GitHub Actions will use repository
secrets only in a backend-specific workflow added with the first deployable backend
change.
