import { describe, expect, it } from "vitest";
import { buildApp } from "../src/app.js";
import { InMemoryFamJamRepository } from "../src/in-memory-repository.js";
import type { IdentityProvider } from "../src/identity-provider.js";

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
    throw new Error("invalid session");
  },
  async revokeSession() {},
};

function repository() {
  return new InMemoryFamJamRepository({
    accounts: [
      { identitySubject: "parent-subject", familyID: "family-1", memberID: "parent-1", role: "parent" },
      { identitySubject: "kid-subject", familyID: "family-1", memberID: "kid-1", role: "kid" },
    ],
    members: [
      { id: "parent-1", familyID: "family-1", name: "Alex", role: "parent", colorTag: "blue" },
      { id: "kid-1", familyID: "family-1", name: "Emma", role: "kid", colorTag: "purple" },
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
