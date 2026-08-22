# Family Activity Coordinator — Architecture & Build Plan

## 1. Overview

A native iOS app for coordinating family activities (kids' games, practices, events),
built primarily for the parents to use day-to-day, with limited access for one kid
who has a phone. Beyond a shared calendar, the app has "agentic" features: it scans
email for game/activity info, accepts voice input to add events, and proactively
flags scheduling conflicts.

## 2. Users & Roles

| Role | Access |
|---|---|
| Parent (x2) | Full read/write on all events, kids, drivers. Approves AI-suggested events. |
| Kid (1, has a phone) | Read access to their own activities; can view schedule, no edit rights on others' events. |

## 3. Platform

- **Client:** Native iOS app, Swift + SwiftUI
- **Distribution (dev/family use):** TestFlight — no public App Store listing needed
- **Why native (not React Native/PWA):** direct access to EventKit, Siri Shortcuts /
  App Intents, and push notifications without cross-platform framework overhead

## 4. Backend

- **Client/backend boundary:** the iOS client depends on backend-neutral contracts
  (for example, `EventStore`), not a specific vendor SDK or transport.
- **Initial backend implementation:** Supabase (Postgres + Auth + Edge Functions)
- **Images (local use):** regular image files bundled with the app (Xcode asset catalog) or selected from the device photo library; do not use Supabase Storage for local images.
- **Why Supabase initially:** free/near-free at family scale, no server to manage,
  built-in cron support for scheduled polling, Swift client SDK available. A custom
  API or another backend can implement the same client contracts later.
- **Local development:** Supabase CLI, which runs the full stack (Postgres, Auth,
  Edge Functions runtime, local Studio UI) as Docker containers
  - `supabase init` / `supabase start` — spins up local stack
  - `supabase functions serve` — run Edge Functions locally
  - `supabase db push` / `supabase functions deploy` — promote to the cloud project
    when ready
- **Environment switching:** app config (e.g. `Config.swift` with `#if DEBUG` or an
  `.xcconfig`) points to `localhost` in dev builds, real Supabase project URL in
  release builds

## 5. Data Model (initial)

Minimal v1 schema — expected to evolve:

- **kids**: id, name, birth_year_or_grade (no exact DOB), color_tag
- **events**: id, title, kid_id (nullable — can apply to multiple kids), start_time,
  end_time, location, driver, source (`manual` | `email_suggested` | `voice`),
  status (`confirmed` | `pending_review`)
- **users**: id, role (`parent` | `kid`), auth link to Supabase Auth
- **conflicts** (derived, not stored): computed at write-time by checking new events
  against existing ones for overlapping times or the same driver double-booked

## 6. Core Features (v1)

- Parent sign-in (Supabase Auth)
- Add / edit / delete events manually (kid, time, location, driver)
- Weekly view, color-coded per kid
- Data synced across both parents' devices in real time (Supabase realtime
  subscriptions)

## 7. Agentic Features (v2+)

### 7.1 Email scanning for games/activities
- Supabase Edge Function on a cron schedule (every 10–15 min)
- Polls Gmail via the Gmail API (OAuth-scoped to read only)
- Each new email is sent to Claude (Anthropic API) with a prompt to extract:
  is this about a kid's game/activity, and if so, date/time/location/opponent
- High-confidence extractions are written to `events` with
  `status = pending_review` and `source = email_suggested`
- Push notification to parents: "New event detected — review to confirm"
- Explicitly NOT auto-confirmed — false positives would erode trust

### 7.2 Voice input
- **On-device (fast path):** Siri Shortcuts / App Intents (iOS 16+) for simple,
  well-structured phrases ("add soccer practice Tuesday at 4")
- **NLP path (for casual/complex phrasing):** transcribed text sent to Claude API
  to parse into a structured event (kid, date, time, location), then written the
  same way manual entries are

### 7.3 Conflict detection
- Pure logic, no LLM needed
- On any event write (manual, email-suggested, or voice), check for:
  - overlapping times for the same kid
  - the same driver double-booked across kids
- Push notification on conflict: "Heads up — Jake's game overlaps with Emma's
  practice on Thursday"

## 8. Tech Stack Summary

| Layer | Choice | Why |
|---|---|---|
| iOS app | Swift + SwiftUI | Native EventKit/Siri/push access |
| Backend logic | TypeScript (Supabase Edge Functions, Deno-based) | Best SDK support for Gmail, Calendar, Anthropic API; fastest iteration for prompt-heavy logic |
| Database | Postgres (via Supabase) | Managed, free tier, realtime subscriptions |
| LLM | Claude (Anthropic API) | Email parsing, voice-text parsing |
| Local dev | Supabase CLI + Docker; local image files | Full backend stack runs locally; image assets stay in the app bundle/device rather than Supabase Storage |
| Hosting | Supabase free tier (serverless) | $0–10/month at family scale; main variable cost is LLM API usage, expected to be low |

## 9. Build Phases

**Phase 1 — Core app**
- Supabase project + local Docker dev environment
- Local image assets in the Xcode asset catalog (no Supabase Storage)
- Data model (kids, events)
- SwiftUI app: parent sign-in, add/edit events, weekly list view
- Realtime sync between both parents' devices
- TestFlight build for family testing

**Phase 2 — Kid access + notifications**
- Restricted kid login/view
- Push notifications for new/updated events

**Phase 3 — Agentic features**
- Email-polling Edge Function + Claude-based extraction
- Pending-review UI for AI-suggested events
- Conflict-detection logic + notifications

**Phase 4 — Voice input**
- Siri Shortcuts / App Intents integration
- Claude-based NLP parsing for casual voice phrasing

## 10. Open Questions / Decisions to Revisit

- Whether to sync events to the iPhone's native Calendar app (EventKit) in addition
  to the in-app view, or keep the app as the sole source of truth
- Whether Gmail polling should move from cron-based polling to Gmail push
  notifications (Pub/Sub) later for lower latency, which would require an
  always-on service (e.g. Fly.io) instead of pure serverless
- Carpool coordination across other families (out of scope for v1–v4, noted as a
  possible future direction)
