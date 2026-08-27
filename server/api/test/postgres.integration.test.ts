import { randomUUID } from "node:crypto";
import { readdir, readFile } from "node:fs/promises";
import { fileURLToPath } from "node:url";
import { Pool } from "pg";
import { afterAll, afterEach, beforeAll, describe, expect, it } from "vitest";
import { buildApp } from "../src/app.js";
import type { IdentityProvider } from "../src/identity-provider.js";
import { PostgresFamJamRepository } from "../src/postgres-repository.js";

const adminURL = process.env.INTEGRATION_DATABASE_URL;
const databaseName = `famjam_test_${randomUUID().replaceAll("-", "")}`;
const migrationsDirectory = fileURLToPath(new URL("../migrations", import.meta.url));
let databaseURL = "";
let adminPool: Pool;
const repositories: PostgresFamJamRepository[] = [];

function repositoryForTest(): PostgresFamJamRepository {
  const repository = PostgresFamJamRepository.fromConnectionString(databaseURL);
  repositories.push(repository);
  return repository;
}

const identityProvider: IdentityProvider = {
  googleAuthorizationURL: () => "https://identity.example/google",
  appleAuthorizationURL: () => "https://identity.example/apple",
  async authenticateOAuthToken(token) {
    const identities: Record<string, { subject: string; displayName: string; accessToken: string }> = {
      "oauth-token": { subject: "integration-parent", displayName: "Alex", accessToken: "integration-token" },
      "child-oauth-token": { subject: "integration-child", displayName: "Sam", accessToken: "child-token" },
      "other-oauth-token": { subject: "other-parent", displayName: "Jordan", accessToken: "other-token" },
    };
    const identity = identities[token];
    if (!identity) throw new Error("invalid OAuth token");
    return {
      identity: { subject: identity.subject, displayName: identity.displayName },
      accessToken: identity.accessToken,
    };
  },
  async verifySession(token) {
    const identities: Record<string, { subject: string; displayName: string }> = {
      "integration-token": { subject: "integration-parent", displayName: "Alex" },
      "child-token": { subject: "integration-child", displayName: "Sam" },
      "other-token": { subject: "other-parent", displayName: "Jordan" },
    };
    const identity = identities[token];
    if (!identity) throw new Error("invalid session");
    return identity;
  },
  async revokeSession() {},
};

describe.skipIf(!adminURL)("PostgreSQL HTTP integration", () => {
  beforeAll(async () => {
    adminPool = new Pool({ connectionString: adminURL });
    await adminPool.query(`CREATE DATABASE ${databaseName}`);
    const url = new URL(adminURL!);
    url.pathname = `/${databaseName}`;
    databaseURL = url.toString();
    const migrationPool = new Pool({ connectionString: databaseURL });
    try {
      for (const filename of (await readdir(migrationsDirectory)).filter((name) => name.endsWith(".sql")).sort()) {
        await migrationPool.query(await readFile(`${migrationsDirectory}/${filename}`, "utf8"));
      }
    } finally {
      await migrationPool.end();
    }
  });

  afterEach(async () => {
    await Promise.all(repositories.splice(0).map((repository) => repository.close()));
  });

  afterAll(async () => {
    await adminPool.query(
      "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname = $1",
      [databaseName],
    );
    await adminPool.query(`DROP DATABASE IF EXISTS ${databaseName}`);
    await adminPool.end();
  });

  it("persists an HTTP event across PostgreSQL repository instances", async () => {
    const writerRepository = repositoryForTest();
    const writer = buildApp({
      identityProvider,
      repository: writerRepository,
      readinessCheck: () => writerRepository.checkReadiness(),
    });
    const session = await writer.inject({
      method: "POST",
      url: "/v1/sessions",
      payload: { oauthToken: "oauth-token", codeVerifier: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopq" },
    });
    expect(session.statusCode).toBe(200);

    const saved = await writer.inject({
      method: "PUT",
      url: "/v1/events/00000000-0000-4000-8000-000000000099",
      headers: { authorization: "Bearer integration-token" },
      payload: {
        id: "00000000-0000-4000-8000-000000000099",
        title: "Integration rehearsal",
        kidID: null,
        participantIDs: [],
        startTime: "2026-09-01T18:00:00Z",
        endTime: "2026-09-01T19:00:00Z",
        location: null,
        driver: null,
        source: "manual",
        status: "confirmed",
      },
    });
    expect(saved.statusCode).toBe(200);
    await writer.close();

    const readerRepository = repositoryForTest();
    const reader = buildApp({
      identityProvider,
      repository: readerRepository,
      readinessCheck: () => readerRepository.checkReadiness(),
    });
    expect((await reader.inject({ method: "GET", url: "/ready" })).statusCode).toBe(200);
    const events = await reader.inject({
      method: "GET",
      url: "/v1/events",
      headers: { authorization: "Bearer integration-token" },
    });
    expect(events.statusCode).toBe(200);
    expect(events.json()).toEqual([
      expect.objectContaining({ id: "00000000-0000-4000-8000-000000000099", title: "Integration rehearsal" }),
    ]);
    await reader.close();
  });

  it("redeems invitations atomically and isolates them from another family", async () => {
    const repository = repositoryForTest();
    const app = buildApp({ identityProvider, repository });
    await app.inject({
      method: "POST",
      url: "/v1/sessions",
      payload: { oauthToken: "oauth-token", codeVerifier: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopq" },
    });
    const invitation = await app.inject({
      method: "POST",
      url: "/v1/invitations",
      headers: { authorization: "Bearer integration-token" },
      payload: { role: "kid", email: "child@example.com" },
    });
    expect(invitation.statusCode).toBe(201);

    await app.inject({
      method: "POST",
      url: "/v1/sessions",
      payload: { oauthToken: "other-oauth-token", codeVerifier: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopq" },
    });
    const isolatedList = await app.inject({
      method: "GET",
      url: "/v1/invitations",
      headers: { authorization: "Bearer other-token" },
    });
    const isolatedDelete = await app.inject({
      method: "DELETE",
      url: `/v1/invitations/${invitation.json().id}`,
      headers: { authorization: "Bearer other-token" },
    });
    expect(isolatedList.json()).toEqual([]);
    expect(isolatedDelete.statusCode).toBe(404);

    const joined = await app.inject({
      method: "POST",
      url: "/v1/sessions",
      payload: {
        oauthToken: "child-oauth-token",
        codeVerifier: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopq",
        invitationCode: invitation.json().code,
      },
    });
    expect(joined.statusCode).toBe(200);
    expect(joined.json().role).toBe("kid");
    const pending = await app.inject({
      method: "GET",
      url: "/v1/invitations",
      headers: { authorization: "Bearer integration-token" },
    });
    expect(pending.json()).toEqual([]);
    await app.close();
  });
});
