import { describe, expect, it } from "vitest";
import { buildApp } from "../src/app.js";
import { InMemoryFamJamRepository } from "../src/in-memory-repository.js";
import type { IdentityProvider } from "../src/identity-provider.js";
import type { LocationSearchProvider } from "../src/location-search-provider.js";
import type { PushNotificationProvider } from "../src/push-notification-provider.js";

const codeChallenge = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQ";
const codeVerifier = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopq";

const identityProvider: IdentityProvider = {
  googleAuthorizationURL(challenge) {
    if (challenge !== codeChallenge) throw new Error("invalid challenge");
    return "https://identity.example/google";
  },
  async authenticateOAuthToken(token, verifier) {
    if (verifier !== codeVerifier) throw new Error("invalid OAuth token");
    if (token === "oauth-token") {
      return {
        identity: { subject: "parent-subject", displayName: "Alex" },
        accessToken: "parent-token",
      };
    }
    if (token === "new-oauth-token") {
      return {
        identity: { subject: "new-parent-subject", displayName: "Sam Rivera" },
        accessToken: "new-parent-token",
      };
    }
    throw new Error("invalid OAuth token");
  },
  async verifySession(token) {
    if (token === "parent-token") return { subject: "parent-subject", displayName: "Alex" };
    if (token === "kid-token") return { subject: "kid-subject", displayName: "Emma" };
    if (token === "other-parent-token") return { subject: "other-parent-subject", displayName: "Jordan" };
    throw new Error("invalid session");
  },
  async revokeSession() {},
};

const locationSearchProvider: LocationSearchProvider = {
  async search(query) {
    return query === "123 Main" ? [{
      id: "place-1",
      address: "123 Main St, Springfield, IL, USA",
    }] : [];
  },
};

function repository() {
  return new InMemoryFamJamRepository({
    accounts: [
      { identitySubject: "parent-subject", familyID: "family-1", memberID: "parent-1", role: "parent" },
      { identitySubject: "kid-subject", familyID: "family-1", memberID: "kid-1", role: "kid" },
      { identitySubject: "other-parent-subject", familyID: "family-2", memberID: "parent-2", role: "parent" },
    ],
    members: [
      { id: "parent-1", familyID: "family-1", name: "Alex", role: "parent", colorTag: "blue" },
      { id: "kid-1", familyID: "family-1", name: "Emma", role: "kid", colorTag: "purple" },
      { id: "parent-2", familyID: "family-2", name: "Jordan", role: "parent", colorTag: "green" },
    ],
    events: [{
      id: "00000000-0000-4000-8000-000000000001",
      familyID: "family-1",
      title: "Soccer practice",
      kidID: "kid-1",
      participantIDs: ["kid-1"],
      startTime: "2026-08-23T16:00:00Z",
      endTime: "2026-08-23T17:00:00Z",
      location: null,
      driver: null,
      source: "manual",
      status: "confirmed",
    }],
  });
}

describe("FamJam API", () => {
  it("exposes backend-owned Google authorization and session exchange", async () => {
    const app = buildApp({ identityProvider, repository: repository() });

    const authorization = await app.inject({
      method: "GET",
      url: `/v1/auth/google?codeChallenge=${codeChallenge}`,
    });
    expect(authorization.statusCode).toBe(302);
    expect(authorization.headers.location).toBe("https://identity.example/google");

    const session = await app.inject({
      method: "POST",
      url: "/v1/sessions",
      payload: { oauthToken: "oauth-token", codeVerifier },
    });
    expect(session.statusCode).toBe(200);
    expect(session.json()).toEqual({
      accountID: "parent-1",
      displayName: "Alex",
      role: "parent",
      accessToken: "parent-token",
    });
    await app.close();
  });

  it("JIT provisions a new Google identity as an idempotent parent account", async () => {
    const data = repository();
    const app = buildApp({ identityProvider, repository: data });

    const signUp = () => app.inject({
      method: "POST",
      url: "/v1/sessions",
      payload: { oauthToken: "new-oauth-token", codeVerifier },
    });
    const first = await signUp();
    const retry = await signUp();

    expect(first.statusCode).toBe(200);
    expect(first.json()).toMatchObject({
      displayName: "Sam Rivera",
      role: "parent",
      accessToken: "new-parent-token",
    });
    expect(retry.statusCode).toBe(200);
    expect(retry.json().accountID).toBe(first.json().accountID);
    const account = await data.accountForIdentity("new-parent-subject");
    expect(account?.role).toBe("parent");
    expect(await data.membersForFamily(account!.familyID)).toHaveLength(1);
    await app.close();
  });

  it("searches US addresses through the backend location provider", async () => {
    const app = buildApp({
      identityProvider,
      repository: repository(),
      locationSearchProvider,
    });
    const response = await app.inject({
      method: "GET",
      url: "/v1/locations/search?q=123%20Main",
      headers: { authorization: "Bearer parent-token" },
    });
    expect(response.statusCode).toBe(200);
    expect(response.json()).toEqual([{
      id: "place-1",
      address: "123 Main St, Springfield, IL, USA",
    }]);
    await app.close();
  });

  it("lets a parent invite a kid into the same family", async () => {
    const data = repository();
    const app = buildApp({ identityProvider, repository: data });
    const invitation = await app.inject({
      method: "POST",
      url: "/v1/invitations",
      headers: { authorization: "Bearer parent-token" },
      payload: { role: "kid" },
    });
    expect(invitation.statusCode).toBe(201);
    const invitationCode = invitation.json().code as string;

    const session = await app.inject({
      method: "POST",
      url: "/v1/sessions",
      payload: { oauthToken: "new-oauth-token", codeVerifier, invitationCode },
    });

    expect(session.statusCode).toBe(200);
    expect(session.json()).toMatchObject({ displayName: "Sam Rivera", role: "kid" });
    const account = await data.accountForIdentity("new-parent-subject");
    expect(account?.familyID).toBe("family-1");
    expect(account?.role).toBe("kid");
    await app.close();
  });

  it("lets only parents list pending family invitations", async () => {
    const app = buildApp({ identityProvider, repository: repository() });
    const created = await app.inject({
      method: "POST",
      url: "/v1/invitations",
      headers: { authorization: "Bearer parent-token" },
      payload: { role: "kid" },
    });

    const pending = await app.inject({
      method: "GET",
      url: "/v1/invitations",
      headers: { authorization: "Bearer parent-token" },
    });
    const forbidden = await app.inject({
      method: "GET",
      url: "/v1/invitations",
      headers: { authorization: "Bearer kid-token" },
    });

    expect(created.statusCode).toBe(201);
    expect(pending.statusCode).toBe(200);
    expect(pending.json()).toEqual([{
      id: created.json().id,
      role: "kid",
      expiresAt: created.json().expiresAt,
    }]);
    expect(forbidden.statusCode).toBe(403);
    await app.close();
  });

  it("lets a parent cancel only a pending invitation in their family", async () => {
    const app = buildApp({ identityProvider, repository: repository() });
    const created = await app.inject({
      method: "POST",
      url: "/v1/invitations",
      headers: { authorization: "Bearer parent-token" },
      payload: { role: "parent" },
    });
    const id = created.json().id as string;

    const otherFamily = await app.inject({
      method: "DELETE",
      url: `/v1/invitations/${id}`,
      headers: { authorization: "Bearer other-parent-token" },
    });
    const cancelled = await app.inject({
      method: "DELETE",
      url: `/v1/invitations/${id}`,
      headers: { authorization: "Bearer parent-token" },
    });
    const repeated = await app.inject({
      method: "DELETE",
      url: `/v1/invitations/${id}`,
      headers: { authorization: "Bearer parent-token" },
    });
    const pending = await app.inject({
      method: "GET",
      url: "/v1/invitations",
      headers: { authorization: "Bearer parent-token" },
    });

    expect(otherFamily.statusCode).toBe(404);
    expect(cancelled.statusCode).toBe(204);
    expect(repeated.statusCode).toBe(404);
    expect(pending.json()).toEqual([]);
    await app.close();
  });

  it("rotates an invitation code when a parent resends it", async () => {
    const app = buildApp({ identityProvider, repository: repository() });
    const created = await app.inject({
      method: "POST",
      url: "/v1/invitations",
      headers: { authorization: "Bearer parent-token" },
      payload: { role: "kid" },
    });

    const resent = await app.inject({
      method: "POST",
      url: `/v1/invitations/${created.json().id}/resend`,
      headers: { authorization: "Bearer parent-token" },
    });
    const oldCodeSession = await app.inject({
      method: "POST",
      url: "/v1/sessions",
      payload: {
        oauthToken: "new-oauth-token",
        codeVerifier,
        invitationCode: created.json().code,
      },
    });
    const newCodeSession = await app.inject({
      method: "POST",
      url: "/v1/sessions",
      payload: {
        oauthToken: "new-oauth-token",
        codeVerifier,
        invitationCode: resent.json().code,
      },
    });

    expect(resent.statusCode).toBe(200);
    expect(resent.json()).toMatchObject({ id: created.json().id, role: "kid" });
    expect(resent.json().code).not.toBe(created.json().code);
    expect(oldCodeSession.statusCode).toBe(403);
    expect(newCodeSession.statusCode).toBe(200);
    expect(newCodeSession.json().role).toBe("kid");
    await app.close();
  });

  it("advances the family change cursor after a mutation", async () => {
    const data = repository();
    const app = buildApp({ identityProvider, repository: data });
    const before = await app.inject({
      method: "GET",
      url: "/v1/changes",
      headers: { authorization: "Bearer parent-token" },
    });
    const write = await app.inject({
      method: "PUT",
      url: "/v1/events/00000000-0000-4000-8000-000000000005",
      headers: { authorization: "Bearer parent-token" },
      payload: {
        id: "00000000-0000-4000-8000-000000000005",
        title: "Piano lesson",
        kidID: "kid-1",
        participantIDs: ["kid-1"],
        startTime: "2026-08-25T18:00:00Z",
        endTime: "2026-08-25T19:00:00Z",
        location: null,
        driver: null,
        source: "manual",
        status: "confirmed"
      },
    });
    const after = await app.inject({
      method: "GET",
      url: "/v1/changes",
      headers: { authorization: "Bearer parent-token" },
    });

    expect(before.json()).toEqual({ version: 0 });
    expect(write.statusCode).toBe(200);
    expect(after.json()).toEqual({ version: 1 });
    await app.close();
  });

  it("registers a device and pushes event changes to the family", async () => {
    const pushes: Array<{ tokens: string[]; title: string }> = [];
    const pushNotificationProvider: PushNotificationProvider = {
      async send(tokens, notification) {
        pushes.push({ tokens, title: notification.title });
      },
    };
    const app = buildApp({
      identityProvider,
      repository: repository(),
      pushNotificationProvider,
    });
    const registration = await app.inject({
      method: "PUT",
      url: "/v1/devices/device-token-1",
      headers: { authorization: "Bearer parent-token" },
    });
    const write = await app.inject({
      method: "PUT",
      url: "/v1/events/00000000-0000-4000-8000-000000000006",
      headers: { authorization: "Bearer parent-token" },
      payload: {
        id: "00000000-0000-4000-8000-000000000006",
        title: "Band practice",
        kidID: "kid-1",
        participantIDs: ["kid-1"],
        startTime: "2026-08-26T18:00:00Z",
        endTime: "2026-08-26T19:00:00Z",
        location: null,
        driver: null,
        source: "manual",
        status: "confirmed"
      },
    });

    expect(registration.statusCode).toBe(204);
    expect(write.statusCode).toBe(200);
    expect(pushes).toEqual([{ tokens: ["device-token-1"], title: "Band practice" }]);
    await app.close();
  });

  it("requires a verified bearer session", async () => {
    const app = buildApp({ identityProvider, repository: repository() });
    const response = await app.inject({ method: "GET", url: "/v1/events" });
    expect(response.statusCode).toBe(401);
    await app.close();
  });

  it("returns only a kid's own events", async () => {
    const app = buildApp({ identityProvider, repository: repository() });
    const response = await app.inject({
      method: "GET",
      url: "/v1/events",
      headers: { authorization: "Bearer kid-token" },
    });
    expect(response.statusCode).toBe(200);
    expect(response.json()).toHaveLength(1);
    await app.close();
  });

  it("blocks kid accounts from writing events", async () => {
    const app = buildApp({ identityProvider, repository: repository() });
    const response = await app.inject({
      method: "PUT",
      url: "/v1/events/00000000-0000-4000-8000-000000000002",
      headers: { authorization: "Bearer kid-token" },
      payload: {
        id: "00000000-0000-4000-8000-000000000002",
        title: "Work meeting",
        kidID: "parent-1",
        participantIDs: ["parent-1"],
        startTime: "2026-08-23T16:30:00Z",
        endTime: "2026-08-23T17:30:00Z",
        location: null,
        driver: null,
        source: "manual",
        status: "confirmed"
      },
    });
    expect(response.statusCode).toBe(403);
    await app.close();
  });

  it("rejects participants outside the authenticated family", async () => {
    const app = buildApp({ identityProvider, repository: repository() });
    const response = await app.inject({
      method: "PUT",
      url: "/v1/events/00000000-0000-4000-8000-000000000003",
      headers: { authorization: "Bearer parent-token" },
      payload: {
        id: "00000000-0000-4000-8000-000000000003",
        title: "Unknown participant event",
        kidID: null,
        participantIDs: ["not-in-this-family"],
        startTime: "2026-08-23T18:00:00Z",
        endTime: "2026-08-23T19:00:00Z",
        location: null,
        driver: null,
        source: "manual",
        status: "confirmed"
      },
    });
    expect(response.statusCode).toBe(400);
    expect(response.json().error).toBe("unknown_participant");
    await app.close();
  });

  it("reports a conflict on a future recurring occurrence", async () => {
    const app = buildApp({ identityProvider, repository: repository() });
    const response = await app.inject({
      method: "PUT",
      url: "/v1/events/00000000-0000-4000-8000-000000000004",
      headers: { authorization: "Bearer parent-token" },
      payload: {
        id: "00000000-0000-4000-8000-000000000004",
        title: "Recurring soccer",
        kidID: "kid-1",
        participantIDs: ["kid-1"],
        startTime: "2026-08-16T16:00:00Z",
        endTime: "2026-08-16T17:00:00Z",
        location: null,
        driver: null,
        source: "manual",
        status: "confirmed",
        recurrence: {
          frequency: "weekly",
          interval: 1,
          endDate: "2026-09-30T23:59:59Z"
        }
      },
    });
    expect(response.statusCode).toBe(200);
    expect(response.json().conflicts[0]?.kind).toBe("overlapping_participant");
    await app.close();
  });

  it("stores recurrence and reports conflicts when a parent writes an event", async () => {
    const data = repository();
    const app = buildApp({ identityProvider, repository: data });
    const response = await app.inject({
      method: "PUT",
      url: "/v1/events/00000000-0000-4000-8000-000000000002",
      headers: { authorization: "Bearer parent-token" },
      payload: {
        id: "00000000-0000-4000-8000-000000000002",
        title: "Doctor appointment",
        kidID: "kid-1",
        participantIDs: ["kid-1"],
        startTime: "2026-08-23T16:30:00Z",
        endTime: "2026-08-23T17:30:00Z",
        location: null,
        driver: null,
        source: "manual",
        status: "confirmed",
        recurrence: {
          frequency: "weekly",
          interval: 1,
          endDate: "2026-12-31T23:59:59Z"
        }
      },
    });
    expect(response.statusCode).toBe(200);
    expect(response.json().conflicts[0]).toMatchObject({
      kind: "overlapping_participant",
      memberID: "kid-1",
    });
    const saved = (await data.eventsForFamily("family-1")).find(
      (event) => event.id === "00000000-0000-4000-8000-000000000002",
    );
    expect(saved?.recurrence?.frequency).toBe("weekly");
    await app.close();
  });
});
