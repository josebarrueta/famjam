# FamJam

FamJam is a colorful native iOS planner for keeping the whole home team in sync. The app is being built local-first: event data
and images stay on the device during Phase 1. The iOS client depends only on
backend-neutral storage contracts; Supabase is one optional implementation for later
sign-in and realtime sync.

## Repository layout

- `clients/ios/` — iOS app and its testable Swift domain module.
- `server/` — optional backend implementations; `supabase/` is the initial planned
  adapter, not an iOS dependency.
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

A future remote adapter is selected without changing app features or domain code:

```bash
FAMJAM_DATA_MODE=remote
FAMJAM_REMOTE_BASE_URL=https://api.example.com
```

Remote mode configuration is validated by `AppConfiguration`. Authentication,
events, family members, and conflict notifications use vendor-neutral interfaces;
a Supabase or custom-server adapter can fill those seams.

## Continuous integration

The iOS workflow runs the package build and test suite on GitHub-hosted macOS. The
backend gets its own workflow when `server/supabase/` contains migrations or Edge
Functions, so iOS changes do not require backend credentials or tooling.
