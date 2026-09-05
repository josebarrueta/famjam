# Automatic internal TestFlight uploads

## Current status

The previous manual upload workflow was defective and has been replaced by
`.github/workflows/testflight.yml`. Static checks and archive-validation unit tests
are available; a real signed upload is still required before this is operational.
Issue #8 must remain open until that acceptance run succeeds.

## Trigger and destination

A successful **iOS** workflow on a **main push** starts TestFlight delivery of that
workflow's exact `head_sha`, not whatever main points to later. Failed CI and PR
validation runs cannot upload. The iOS workflow is path-filtered, including iOS
and API changes; API-only changes can consequently also trigger an upload.
Manual dispatch is available on main for recovery/bootstrap.

There is no approval gate for this internal-testing path, as requested. Protect
main with required PR reviews and required iOS CI checks: merged code can execute
with signing secrets. This workflow does not itself enforce branch protection.

Fastlane uploads and waits for processing, then assigns the build to **Rallyroo
Internal**. It never requests external beta review or App Store Review. Internal
testers may receive the build automatically; this supersedes the earlier manual
internal-distribution policy.

## Required one-time setup

Store these repository Actions secrets using GitHub's secret UI or a secure
file/stdin upload, never by pasting values into command arguments or chat:

- `APPLE_API_KEY_ID`: App Store Connect team API key ID.
- `APPLE_API_ISSUER_ID`: issuer ID.
- `ASC_API_PRIVATE_KEY`: complete PEM .p8 contents, not base64.
- `APPLE_DISTRIBUTION_CERT`: base64 .p12 including its private key.
- `APPLE_DISTRIBUTION_CERT_PWD`: .p12 password (may be empty).
- `APPLE_PROVISIONING_PROFILE`: base64 App Store distribution profile for
  `dev.rallyroo.app`, team `5LS29Z8553`, including Apple sign-in and production APNs.

Use a narrowly scoped key with the permissions necessary to upload and manage
internal TestFlight distribution (App Manager); do not use an Admin key.
Create/verify the internal group named exactly `Rallyroo Internal` before enabling.
No beta-group ID or hardcoded numeric app ID is needed.

The runner pins Xcode 26.3 and Fastlane 2.232.2. Missing tooling fails the job;
there is no silent fallback to another Xcode. Confirm availability on the selected
hosted runner during the first acceptance run.

## Build numbers and recovery

Build numbers are `(100 + GITHUB_RUN_NUMBER).GITHUB_RUN_ATTEMPT.0`. They are bounded
to Apple's component limits and unique for each run/retry of this workflow. The
marketing version remains in the project. Do not delete/recreate the workflow or
introduce another uploader with an independent counter without migrating the
numbering policy. App Store Connect remains authoritative for acceptance.

Concurrent uploads or reruns of older commits can arrive out of order. Such a
build may be rejected by Apple; rerun the latest main workflow rather than silently
reusing an accepted number. This is not a durable FIFO release queue and does not
guarantee delivery of every historical commit during concurrent merges.

## Verification and credential lifecycle

The script validates bundle ID, build number, remote production configuration,
iPhone-only device family, privacy manifest presence/parseability, encryption
flag, code signature, Apple sign-in, production APNs, team/application identifiers,
and absence of a debug entitlement before export/upload.

Credentials live in a private temporary directory and ephemeral keychain. Keychain
password commands are sent over stdin to `security -i`, not process arguments.
Cleanup restores the runner keychain search list and removes installed signing
material on normal failure/success. Hosted-runner disposal is the final boundary
for cancellation or machine failure. Raw build/provider logs are deliberately not
printed or uploaded: errors identify only the failing stage/tool.

Rotate certificates/profiles before expiry and API keys after exposure or personnel
changes. App Store profiles contain no device UDIDs. Revoke compromised keys in
App Store Connect and certificates in the Apple Developer portal, replace secrets,
and validate a new upload. Never put credentials in screenshots or issues.

## Acceptance

- Run `./scripts/test-app-store-upload-workflow.sh` locally.
- Configure secrets and verify required branch protections.
- Merge an iOS PR; confirm successful iOS CI triggers the exact SHA's upload.
- Confirm the build finishes processing and appears in Rallyroo Internal.
- Confirm a retry gets a different build number.
- Test issue #9 on a physical device; CI smoke tests do not prove delivery.
