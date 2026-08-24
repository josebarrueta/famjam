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

The client authenticates directly with the configured identity provider. For the
reference implementation, the Stytch iOS SDK performs Google OAuth and returns a
Stytch session JWT. FamJam API requests include:

```http
Authorization: Bearer <stytch-session-jwt>
```

The TypeScript backend verifies that JWT through the `IdentityProvider` seam, then
loads the associated FamJam account to determine its family and `parent`/`kid`
role. The server must authorize every operation; client-side read-only controls are
not a security boundary.

No Stytch project secret is ever sent to the iOS app.
