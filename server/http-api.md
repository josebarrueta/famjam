# FamJam HTTP adapter contract

This contract is backend-vendor neutral. A custom server, Supabase Edge Functions,
or another provider can implement it. All successful responses use a 2xx status;
JSON requests use `Content-Type: application/json`. Dates are ISO 8601 strings.

## Push notifications

- `PUT /v1/devices/{apnsToken}` registers or transfers the authenticated device.
- `DELETE /v1/devices/{apnsToken}` removes that member's device.

Event creates and updates send family-scoped APNs alerts. Conflict writes use a
conflict-specific message. Device registration is optional, and APNs failures never
roll back the source-of-truth event.

## Synchronization

- `GET /v1/changes` → `{ "version": 42 }` for the authenticated family.

Every event or family-member mutation advances this cursor. Remote iOS sessions
poll the small cursor every five seconds and reload visible family data only when
it changes. The app also refreshes whenever it becomes active.

## Events

- `GET /v1/events` → JSON array of events.
- `PUT /v1/events/{id}` with an event body → conflict result.
- `DELETE /v1/events/{id}` → empty 2xx response.

Event bodies use the Swift `FamilyEvent` fields, including `id`, `title`,
`participantIDs`, `startTime`, `endTime`, `location`, `driver`, `source`, and
`status`, and optional `recurrence`. `kidID` is temporarily included for
compatibility and may be null. A recurrence contains `frequency` (`daily`,
`weekly`, or `monthly`), a positive `interval`, and an ISO 8601 `endDate`.

Save response:

```json
{
  "conflicts": [
    {
      "kind": "overlapping_participant",
      "memberID": "parent-1",
      "driver": null,
      "eventIDs": ["existing-uuid", "new-uuid"]
    }
  ]
}
```

Supported conflict kinds are `overlapping_participant` and
`double_booked_driver`.

## Family invitations

- `POST /v1/invitations` with `{ "role": "parent" | "kid" }` creates a
  single-use, seven-day invitation. Parent authorization is required.
- `POST /v1/sessions` may include `invitationCode` with the OAuth exchange.

Invitation codes are stored as SHA-256 hashes. Successful redemption atomically
creates the invited member and account in the inviter's family. The client never
chooses a family ID or overrides the invitation's role.

## Locations

- `GET /v1/locations/search?q=123%20Main` → US address suggestions.

The reference backend uses Google Places with a US region restriction. The iOS
client only knows the provider-neutral `{ "id": "…", "address": "…" }` contract.
Manual location entry remains available when search is not configured.

## Family members

- `GET /v1/family-members` → JSON array of family members.
- `PUT /v1/family-members/{id}` with a family-member body → empty 2xx response.
- `DELETE /v1/family-members/{id}` → empty 2xx response.

Family-member fields are `id`, `name`, `role` (`parent` or `kid`), optional
`gradeOrBirthYear`, and `colorTag`.

## Authentication

The FamJam backend owns the identity-provider integration. The iOS client only
uses FamJam endpoints and has no Stytch SDK or Stytch configuration.

1. The client generates a PKCE verifier and opens
   `GET /v1/auth/google?codeChallenge=…` in a system authentication browser.
2. FamJam forwards the challenge and redirects the browser to its configured
   Stytch Google OAuth flow.
3. Google/Stytch redirects to `famjam://oauth-callback?stytch_token_type=oauth&token=…`.
4. `POST /v1/sessions` with `{ "oauthToken": "…", "codeVerifier": "…" }`
   exchanges the one-time token through the backend's `IdentityProvider` adapter.
5. If the identity is new and has no invitation, the backend atomically provisions
   it as a parent in a new family. Provisioning is idempotent across retries.
6. The backend returns the FamJam session contract:

```json
{
  "accountID": "parent-1",
  "displayName": "Alex",
  "role": "parent",
  "accessToken": "opaque-session-token"
}
```

`GET /v1/sessions` validates and restores a persisted client session.

Authenticated requests include `Authorization: Bearer <accessToken>`. The backend
validates the opaque Stytch session through its provider adapter, loads the FamJam
account, and applies family and role authorization. `DELETE /v1/sessions` revokes
the hosted session.

No Stytch secret, SDK, configuration, or provider-specific type exists in the iOS
code. The browser only interacts with Stytch after following the FamJam redirect.
