# FamJam HTTP adapter contract

This contract is backend-vendor neutral. A custom server, Supabase Edge Functions,
or another provider can implement it. All successful responses use a 2xx status;
JSON requests use `Content-Type: application/json`. Dates are ISO 8601 strings.

## Events

- `GET /v1/events` → JSON array of events.
- `PUT /v1/events/{id}` with an event body → conflict result.
- `DELETE /v1/events/{id}` → empty 2xx response.

Event bodies use the Swift `FamilyEvent` fields, including `id`, `title`,
`participantIDs`, `startTime`, `endTime`, `location`, `driver`, `source`, and
`status`. `kidID` is temporarily included for compatibility and may be null.

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
5. The backend returns the FamJam session contract:

```json
{
  "accountID": "parent-1",
  "displayName": "Alex",
  "role": "parent",
  "accessToken": "opaque-session-token"
}
```

Authenticated requests include `Authorization: Bearer <accessToken>`. The backend
validates the opaque Stytch session through its provider adapter, loads the FamJam
account, and applies family and role authorization. `DELETE /v1/sessions` revokes
the hosted session.

No Stytch secret, SDK, configuration, or provider-specific type exists in the iOS
code. The browser only interacts with Stytch after following the FamJam redirect.
