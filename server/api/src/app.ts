import Fastify, { type FastifyReply, type FastifyRequest } from "fastify";
import { z } from "zod";
import type { Account, EventConflict, FamilyEvent, FamilyMember } from "./domain.js";
import type { IdentityProvider } from "./identity-provider.js";
import type { FamJamRepository } from "./repository.js";

declare module "fastify" {
  interface FastifyRequest {
    account: Account | null;
  }
}

const eventSchema = z.object({
  id: z.string().uuid(),
  title: z.string().trim().min(1),
  kidID: z.string().nullable(),
  participantIDs: z.array(z.string()).default([]),
  startTime: z.string().datetime(),
  endTime: z.string().datetime(),
  location: z.string().nullable(),
  driver: z.string().nullable(),
  source: z.enum(["manual", "email_suggested", "voice"]),
  status: z.enum(["confirmed", "pending_review"]),
}).refine((event) => new Date(event.endTime) > new Date(event.startTime), {
  message: "endTime must follow startTime",
});

const oauthAuthorizationSchema = z.object({ codeChallenge: z.string().min(43).max(128) });
const oauthSessionSchema = z.object({
  oauthToken: z.string().min(1),
  codeVerifier: z.string().min(43).max(128),
});

const memberSchema = z.object({
  id: z.string().min(1),
  name: z.string().trim().min(1),
  role: z.enum(["parent", "kid"]),
  gradeOrBirthYear: z.string().nullable().optional(),
  colorTag: z.string().min(1),
});

interface Dependencies {
  identityProvider: IdentityProvider;
  repository: FamJamRepository;
}

export function buildApp({ identityProvider, repository }: Dependencies) {
  const app = Fastify({ logger: false });
  app.decorateRequest("account", null);

  app.addHook("onRequest", async (request, reply) => {
    if (["/health", "/v1/auth/google", "/v1/sessions"].includes(request.routeOptions.url ?? "")) return;
    const token = bearerToken(request.headers.authorization);
    if (!token) return reply.code(401).send({ error: "missing_bearer_token" });
    try {
      const identity = await identityProvider.verifySession(token);
      request.account = await repository.accountForIdentity(identity.subject);
      if (!request.account) return reply.code(403).send({ error: "account_not_provisioned" });
    } catch {
      return reply.code(401).send({ error: "invalid_session" });
    }
  });

  app.get("/health", async () => ({ status: "ok" }));

  app.get("/v1/auth/google", async (request, reply) => {
    const parsed = oauthAuthorizationSchema.safeParse(request.query);
    if (!parsed.success) return reply.code(400).send({ error: "invalid_code_challenge" });
    return reply.redirect(identityProvider.googleAuthorizationURL(parsed.data.codeChallenge));
  });

  app.post("/v1/sessions", async (request, reply) => {
    const parsed = oauthSessionSchema.safeParse(request.body);
    if (!parsed.success) return reply.code(400).send({ error: "invalid_oauth_token" });
    try {
      const issued = await identityProvider.authenticateOAuthToken(
        parsed.data.oauthToken,
        parsed.data.codeVerifier,
      );
      const existingAccount = await repository.accountForIdentity(issued.identity.subject);
      const account = existingAccount ?? await repository.provisionParentAccount(
        issued.identity.subject,
        issued.identity.displayName,
      );
      const members = await repository.membersForFamily(account.familyID);
      const member = members.find((candidate) => candidate.id === account.memberID);
      return {
        accountID: account.memberID,
        displayName: member?.name ?? issued.identity.displayName,
        role: account.role,
        accessToken: issued.accessToken,
      };
    } catch {
      return reply.code(401).send({ error: "invalid_oauth_token" });
    }
  });

  app.delete("/v1/sessions", async (request, reply) => {
    const token = bearerToken(request.headers.authorization);
    if (!token) return reply.code(401).send({ error: "missing_bearer_token" });
    await identityProvider.revokeSession(token);
    return reply.code(204).send();
  });

  app.get("/v1/events", async (request) => {
    const account = requiredAccount(request);
    const events = await repository.eventsForFamily(account.familyID);
    const visible = account.role === "parent"
      ? events
      : events.filter((event) => event.participantIDs.includes(account.memberID));
    return visible.map(clientEvent);
  });

  app.put("/v1/events/:id", async (request, reply) => {
    const account = await requireParent(request, reply);
    if (!account) return;
    const parsed = eventSchema.safeParse(request.body);
    if (!parsed.success) return reply.code(400).send({ error: "invalid_event", details: parsed.error.issues });
    const routeID = (request.params as { id: string }).id;
    if (routeID !== parsed.data.id) return reply.code(400).send({ error: "event_id_mismatch" });
    const familyMembers = await repository.membersForFamily(account.familyID);
    const memberIDs = new Set(familyMembers.map((member) => member.id));
    const referencedMemberIDs = [
      ...parsed.data.participantIDs,
      ...(parsed.data.kidID ? [parsed.data.kidID] : []),
    ];
    if (referencedMemberIDs.some((memberID) => !memberIDs.has(memberID))) {
      return reply.code(400).send({ error: "unknown_participant" });
    }
    const event: FamilyEvent = { ...parsed.data, familyID: account.familyID };
    const existing = await repository.eventsForFamily(account.familyID);
    const conflicts = detectConflicts(event, existing.filter((candidate) => candidate.id !== event.id));
    await repository.saveEvent(event);
    return { conflicts };
  });

  app.delete("/v1/events/:id", async (request, reply) => {
    const account = await requireParent(request, reply);
    if (!account) return;
    await repository.deleteEvent(account.familyID, (request.params as { id: string }).id);
    return reply.code(204).send();
  });

  app.get("/v1/family-members", async (request) => {
    const account = requiredAccount(request);
    return (await repository.membersForFamily(account.familyID)).map(clientMember);
  });

  app.put("/v1/family-members/:id", async (request, reply) => {
    const account = await requireParent(request, reply);
    if (!account) return;
    const parsed = memberSchema.safeParse(request.body);
    if (!parsed.success) return reply.code(400).send({ error: "invalid_family_member", details: parsed.error.issues });
    const routeID = (request.params as { id: string }).id;
    if (routeID !== parsed.data.id) return reply.code(400).send({ error: "member_id_mismatch" });
    const { gradeOrBirthYear, ...memberData } = parsed.data;
    const member: FamilyMember = {
      ...memberData,
      familyID: account.familyID,
      ...(gradeOrBirthYear !== undefined ? { gradeOrBirthYear } : {}),
    };
    await repository.saveMember(member);
    return reply.code(204).send();
  });

  app.delete("/v1/family-members/:id", async (request, reply) => {
    const account = await requireParent(request, reply);
    if (!account) return;
    const memberID = (request.params as { id: string }).id;
    const events = await repository.eventsForFamily(account.familyID);
    if (events.some((event) => event.participantIDs.includes(memberID))) {
      return reply.code(409).send({ error: "member_has_scheduled_events" });
    }
    await repository.deleteMember(account.familyID, memberID);
    return reply.code(204).send();
  });

  return app;
}

function bearerToken(authorization: string | undefined): string | null {
  const match = authorization?.match(/^Bearer (.+)$/i);
  return match?.[1] ?? null;
}

function requiredAccount(request: FastifyRequest): Account {
  if (!request.account) throw new Error("Authentication hook did not provide an account");
  return request.account;
}

async function requireParent(request: FastifyRequest, reply: FastifyReply): Promise<Account | null> {
  const account = requiredAccount(request);
  if (account.role !== "parent") {
    await reply.code(403).send({ error: "parent_role_required" });
    return null;
  }
  return account;
}

function detectConflicts(event: FamilyEvent, existingEvents: FamilyEvent[]): EventConflict[] {
  const conflicts: EventConflict[] = [];
  for (const existing of existingEvents) {
    const overlaps = new Date(event.startTime) < new Date(existing.endTime)
      && new Date(existing.startTime) < new Date(event.endTime);
    if (!overlaps) continue;
    const memberID = event.participantIDs.find((id) => existing.participantIDs.includes(id));
    if (memberID) {
      conflicts.push({
        kind: "overlapping_participant",
        memberID,
        driver: null,
        eventIDs: [existing.id, event.id],
      });
    } else if (event.driver && event.driver === existing.driver) {
      conflicts.push({
        kind: "double_booked_driver",
        memberID: null,
        driver: event.driver,
        eventIDs: [existing.id, event.id],
      });
    }
  }
  return conflicts;
}

function clientEvent({ familyID: _familyID, ...event }: FamilyEvent) {
  return event;
}

function clientMember({ familyID: _familyID, ...member }: FamilyMember) {
  return member;
}
