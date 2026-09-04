#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
WORKFLOW="$ROOT/.github/workflows/app-store-upload.yml"

[[ -f "$WORKFLOW" ]] || { echo "MISSING: $WORKFLOW" >&2; exit 1; }

#
# Trigger: workflow_dispatch only (no push or PR triggers that could
# cause automatic uploads).
#
grep -q 'workflow_dispatch:' "$WORKFLOW"
if grep -q '^on:.*push:' "$WORKFLOW"; then
   echo "WORKFLOW must not trigger on push" >&2; exit 1
fi

#
# Environment protection: must use production-upload environment.
#
grep -q 'environment:.*production-upload' "$WORKFLOW" || {
   echo "WORKFLOW must use production-upload environment" >&2; exit 1
}

#
# Ephemeral keychain: must create and delete keychain.
#
grep -q 'create-keychain' "$WORKFLOW"
grep -q 'delete-keychain' "$WORKFLOW" || {
   echo "WORKFLOW must clean up the ephemeral keychain" >&2; exit 1
}

#
# No secrets in artifacts (upload-artifact only includes logs/plists,
# not certificate or key material).
#
ARTIFACT_LINES=$(grep -n 'upload-artifact' "$WORKFLOW" -A5)
if grep -q 'APPLE_DISTRIBUTION_CERT\|ASC_API_PRIVATE_KEY\|keychain' <<< "$ARTIFACT_LINES"; then
   echo "WORKFLOW must not upload certificates or keys as artifacts" >&2; exit 1
fi

#
# No auto-distribution to TestFlight groups.
#
if grep -q 'fastlane supply\|fastlane distribute\|--groups' "$WORKFLOW"; then
   echo "WORKFLOW must not automatically assign TestFlight groups" >&2; exit 1
fi

#
# No auto-submission for App Review.
#
if grep -q 'submitTestFlight\|--submit_for_review' "$WORKFLOW"; then
   echo "WORKFLOW must not automatically submit for App Review" >&2; exit 1
fi

#
# Certificate and key must come from secrets, not be hardcoded.
#
if grep -qE -- '-----BEGIN.*PRIVATE.*KEY' "$WORKFLOW"; then
   echo "WORKFLOW must not hardcode private key material" >&2; exit 1
fi

#
# Must reference all required secrets.
#
for secret in APPLE_API_KEY_ID APPLE_API_ISSUER_ID ASC_API_PRIVATE_KEY \
   APPLE_DISTRIBUTION_CERT APPLE_DISTRIBUTION_CERT_PWD APPLE_PROVISIONING_PROFILE; do
   grep -q "secrets\.$secret\|secrets\.${secret}" "$WORKFLOW" || {
      echo "WORKFLOW must reference secrets.$secret" >&2; exit 1
   }
done

#
# Must verify privacy manifest.
#
grep -q 'PrivacyInfo.xcprivacy' "$WORKFLOW" || {
   echo "WORKFLOW must verify PrivacyInfo.xcprivacy" >&2; exit 1
}

#
# Must check encryption declaration.
#
grep -q 'ITSAppUsesNonExemptEncryption' "$WORKFLOW" || {
   echo "WORKFLOW must verify ITSAppUsesNonExemptEncryption" >&2; exit 1
}

#
# Must derive or accept a CFBundleVersion.
#
grep -q 'cfbundleversion\|CFBundleVersion' "$WORKFLOW" || {
   echo "WORKFLOW must derive or validate CFBundleVersion" >&2; exit 1
}

#
# Must NOT silently rewrite CFBundleShortVersionString.
# (No step writes to the plist's CFBundleShortVersionString)
if grep -qE -- 'PlistBuddy.*-c "set :CFBundleShortVersionString"' "$WORKFLOW"; then
   echo "WORKFLOW must not rewrite CFBundleShortVersionString" >&2; exit 1
fi

echo "App Store upload workflow contract passed"
