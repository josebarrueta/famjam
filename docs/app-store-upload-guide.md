# App Store Connect Upload — Operational Guide

## Overview

The `App Store Upload` GitHub Actions workflow (`.github/workflows/app-store-upload.yml`)
provides a controlled, gated path for building and uploading signed Rallyroo
archives to App Store Connect.  It is **manual only** — no routine push,
pull-request, or tag event triggers an upload.

---

## Prerequisites (one-time setup)

### 1. GitHub Environment: `production-upload`

1. Go to **GitHub → rallyroo → Settings → Environments**.
2. Click **Add environment** → name it `production-upload`.
3. Add one or more **required reviewers** (accounts that must approve each run).
4. *(Optional)* add a **production secret** named `ASC_API_KEY_ID` as a
   non-secret environment variable — leave blank initially.

### 2. App Store Connect API Key

1. Go to **App Store Connect → Users and Access → Integrations → App Store Connect API**.
2. Click **Generate API Key** (or **Generate New Key**).
3. Choose:
   - **Name**: `rallyroo-ci`
   - **Role**: `App Manager` (minimum scope: read + manage TestFlight)
4. Download the `.p8` key file **immediately** — Apple will not show it again.

### 3. Distribution Certificate & Provisioning Profile

Already in place from existing TestFlight work:

- **Certificate**: `Apple Distribution: <Your Name>` (from Keychain Access,
  export as `.p12` with a password).
- **Provisioning Profile**: `Rallyroo App Store` (from App Store Connect →
  Devices, Profiles & Certificates → Profiles).

### 4. GitHub Secrets

Set the following in **GitHub → rallyroo → Settings → Actions → Secrets and
variables → Repository** (or Organization):

| Secret                         | Description                                      | Source                                        |
| ------------------------------ | ------------------------------------------------ | -------------------------------------------- |
| `APPLE_API_KEY_ID`             | App Store Connect API Key ID (non-secret)        | App Store Connect UI                          |
| `APPLE_API_ISSUER_ID`          | App Store Connect Issuer ID                      | App Store Connect UI                          |
| `ASC_API_PRIVATE_KEY`          | Full contents of the `.p8` key (multiline block) | Downloaded `.p8` file from Apple              |
| `APPLE_DISTRIBUTION_CERT`      | Base64 of the `.p12` certificate                 | `base64 -i cert.p12`                          |
| `APPLE_DISTRIBUTION_CERT_PWD`  | Password for the `.p12` file (use `""` if none)  | Same password set during Keychain export      |
| `APPLE_PROVISIONING_PROFILE`   | Base64 of the `.mobileprovision` file            | `base64 -i Rallyroo\ App\ Store.mobileprovision` |

---

## Running the Workflow

1. Go to **GitHub → rallyroo → Actions → App Store Upload**.
2. Click **Run workflow** on the right.
3. (Optional) provide:
   - `ref`: git tag or branch name (defaults to `HEAD`)
   - `cfbundleversion`: a unique build number > any previously uploaded (leave blank to auto-increment)
4. Click **Run workflow**.
5. Navigate to **GitHub → rallyroo → Actions → Environments → production-upload**
   and **Approve** the pending workflow run.
6. Watch the run.  A green checkmark means the archive was uploaded to
   App Store Connect.

---

## Post-upload Steps (Manual — Not Automated)

The workflow does **not** automatically:
- Assign the build to a TestFlight group
- Submit the build for App Store Review

After a successful upload:

1. Go to **App Store Connect → TestFlight** and assign the new build to
   `Rallyroo Internal` (or another group) when ready.
2. Go to **App Store Connect → Your App → TestFlight** and submit the build
   for **App Store Review** when the release is ready for public distribution.

---

## Certificate & Key Rotation

### When to rotate

- Apple Distribution certificate expires every **1 year**
- App Store Connect API key has **no expiry**, but rotate after a team member
  leaves, a key is exposed, or as a best-practice security measure
- Provisioning profile changes when device UDIDs change

### How to rotate

1. Generate a new `.p12` certificate or re-export in Keychain Access.
2. Re-upload the new `.p12`, `.p8`, and `.mobileprovision` as base64 to the
   GitHub secrets (update, do not leave old values).
3. For the API key: revoke the old key in App Store Connect, then create a new one.
4. Re-run the upload workflow to confirm the new credentials work.

---

## Failed-Upload Recovery

| Symptom                                        | Likely cause                              | Action                                          |
| --------------------------------------------- | ---------------------------------------- | ---------------------------------------------- |
| `altool: no such file or directory`            | Xcode 16 not selected / toolchain issue   | Check `/tmp/xcode-version.txt` artifact         |
| `No matching provisioning profile found`       | Profile expired or wrong team             | Regenerate `Rallyroo App Store` profile         |
| `CFBundleVersion N already exists`             | Build number not unique                   | Pass `cfbundleversion` input with a higher number |
| `Invalid API key` or `401 Unauthorized`        | Secret expired or misconfigured          | Verify secrets in GitHub → Actions              |
| `Archive verification failed`                  | Signature or entitlement mismatch        | Check `family-app-architecture.md` signing flow |

---

## Emergency Revocation

If a signing credential is exposed:

1. **Revoke** the API key: App Store Connect → Integrations → revoke `rallyroo-ci`.
2. **Revoke** the distribution certificate: App Store Connect → Certificates,
   Identifiers & Profiles → revoke `Apple Distribution: <Name>`.
3. **Generate** new credentials (see "How to rotate" above).
4. **Update** GitHub secrets with the new base64 values and key IDs.
5. Verify the next upload uses only the new credentials.

---

## Security Notes

- All signing material is loaded into a **temporary keychain** and deleted at the
  end of the job.  No certificate or key is written to the GitHub Actions runner's
  persistent disk.
- The `altool` upload log is uploaded as a **non-sensitive artifact** (no
  certificate, profile, or API key data in the log text).
- The App Store Connect API key `.p8` is stored as a GitHub Actions **secret**
  — never visible in logs or UI.
- The `production-upload` GitHub environment requires a **human approval** before
  each run.  Automated CI cannot self-approve.
