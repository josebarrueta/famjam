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

- `POST /v1/sessions` with `{ "email": "…", "password": "…" }` → session JSON.
- `DELETE /v1/sessions` with the bearer token → empty 2xx response.

Session response:

```json
{
  "accountID": "account-1",
  "displayName": "Alex",
  "role": "parent",
  "accessToken": "opaque-token"
}
```

Authenticated event and family-member requests include
`Authorization: Bearer <accessToken>`. The server must authorize parent versus kid
access; the iOS client also hides editing controls for kid sessions, but server-side
authorization remains mandatory.
