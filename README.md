# FamJam

FamJam is a colorful native iOS planner for keeping the whole home team in sync. The app is being built local-first: event data
and images stay on the device during Phase 1. The iOS client depends only on
backend-neutral storage contracts; Supabase is one optional implementation for later
sign-in and realtime sync.

## Repository layout

- `clients/ios/` — iOS app and its testable Swift domain module.
- `server/api/` — scalable TypeScript/Fastify API with PostgreSQL and Stytch.
- `server/supabase/` — optional Supabase-specific infrastructure, not an iOS dependency.
- `.github/workflows/` — CI workflows.
- `family-app-architecture.md` — product architecture and delivery phases.

## Local development

Requirements: Xcode 16+ with iOS 16 SDK support.

```bash
cd clients/ios
swift build
swift test
```

Open `clients/ios/FamilyApp.xcodeproj` in Xcode to run the SwiftUI app on an iOS
simulator or device. The app links the local `FamilyCore` package, which contains
the event domain and persistence layer.

## Data modes

FamJam defaults to local mode and requires no account or backend:

```bash
FAMJAM_DATA_MODE=local
```

The built-in HTTP adapters can be selected without changing app features or domain code:

```bash
FAMJAM_DATA_MODE=remote
FAMJAM_REMOTE_BASE_URL=https://api.example.com
```

Remote mode configuration is validated by `AppConfiguration`. Authentication,
events, and family members use vendor-neutral interfaces; a Supabase Edge Function,
custom server, or another provider can implement `server/http-api.md`. Conflict
alerts remain local to each device for now.

## Continuous integration

The iOS workflow runs the package build and test suite on GitHub-hosted macOS. The
API workflow independently runs TypeScript tests, typechecking, and builds. Neither
workflow requires production credentials.
