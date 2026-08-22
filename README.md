# Family Activity Coordinator

A native iOS family activity planner. The app is being built local-first: event data
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

Use Xcode to run the eventual SwiftUI application target on an iOS simulator or
device. The current package contains the local event domain and persistence layer.

## Continuous integration

The iOS workflow runs the package build and test suite on GitHub-hosted macOS. The
backend gets its own workflow when `server/supabase/` contains migrations or Edge
Functions, so iOS changes do not require backend credentials or tooling.
