import { createHash, randomBytes, randomUUID } from "node:crypto";
import { fastifyRateLimit } from "@fastify/rate-limit";
import Fastify, {
  type FastifyReply,
  type FastifyRequest,
  type FastifyServerOptions,
} from "fastify";
import { z } from "zod";
import type { Account, EventConflict, FamilyEvent, FamilyMember } from "./domain.js";
import type { IdentityProvider } from "./identity-provider.js";
import {
  NoopInvitationEmailSender,
  type InvitationEmailSender,
} from "./invitation-email-sender.js";
import {
  EmptyLocationSearchProvider,
  type LocationSearchProvider,
} from "./location-search-provider.js";
import { FamJamMetrics } from "./metrics.js";
import {
  NoopPushNotificationProvider,
  type PushNotificationProvider,
} from "./push-notification-provider.js";
import type { FamJamRepository } from "./repository.js";

declare module "fastify" {
  interface FastifyRequest {
    account: Account | null;
  }
}

const eventSchema = z.object({
  id: z.string().uuid(),
  title: z.string().trim().min(1),
  kidID: z.string().nullable().default(null),
  participantIDs: z.array(z.string()).default([]),
  startTime: z.string().datetime(),
  endTime: z.string().datetime(),
  location: z.string().nullable().default(null),
  driver: z.string().nullable().default(null),
  source: z.enum(["manual", "email_suggested", "voice"]),
  status: z.enum(["confirmed", "pending_review"]),
  recurrence: z.object({
    frequency: z.enum(["daily", "weekly", "monthly"]),
    interval: z.number().int().positive(),
    endDate: z.string().datetime(),
  }).nullable().optional(),
}).refine((event) => new Date(event.endTime) > new Date(event.startTime), {
  message: "endTime must follow startTime",
});

const locationSearchSchema = z.object({ q: z.string().trim().min(2).max(200) });
const oauthAuthorizationSchema = z.object({ codeChallenge: z.string().min(43).max(128) });
const oauthSessionSchema = z.object({
  oauthToken: z.string().min(1),
  codeVerifier: z.string().min(43).max(128),
  invitationCode: z.string().min(20).optional(),
});
const invitationSchema = z.object({
  role: z.enum(["parent", "kid"]),
  email: z.email().transform((email) => email.toLowerCase()),
});

const memberSchema = z.object({
  id: z.string().min(1),
  name: z.string().trim().min(1),
  role: z.enum(["parent", "kid"]),
  gradeOrBirthYear: z.string().nullable().optional(),
  colorTag: z.string().min(1),
});

interface RouteRateLimit {
  max: number;
  timeWindow: number;
}

interface Dependencies {
  identityProvider: IdentityProvider;
  repository: FamJamRepository;
  locationSearchProvider?: LocationSearchProvider;
  pushNotificationProvider?: PushNotificationProvider;
  invitationEmailSender?: InvitationEmailSender;
  readinessCheck?: () => Promise<void>;
  rateLimits?: Partial<Record<"sessions" | "invitations" | "locations", RouteRateLimit>>;
  metrics?: FamJamMetrics;
  metricsBearerToken?: string;
  logger?: FastifyServerOptions["logger"];
}

export function buildApp({
  identityProvider,
  repository,
  locationSearchProvider = new EmptyLocationSearchProvider(),
  pushNotificationProvider = new NoopPushNotificationProvider(),
  invitationEmailSender = new NoopInvitationEmailSender(),
  readinessCheck = async () => {},
  rateLimits = {},
  metrics = new FamJamMetrics(),
  metricsBearerToken,
  logger = false,
}: Dependencies) {
  const limits = {
    sessions: { max: 10, timeWindow: 60_000 },
    invitations: { max: 20, timeWindow: 60 * 60_000 },
    locations: { max: 60, timeWindow: 60_000 },
    ...rateLimits,
  };
  const app = Fastify({ logger });
  fastifyRateLimit(
    app,
    { global: true, max: 120, timeWindow: 60_000 },
    () => {},
  );
  app.decorateRequest("account", null);
  const requestStarts = new WeakMap<object, bigint>();

  app.addHook("onRequest", async (request, reply) => {
    requestStarts.set(request, process.hrtime.bigint());
    reply.header("x-request-id", request.id);
  });
  app.addHook("onResponse", async (request, reply) => {
    const started = requestStarts.get(request);
    const duration = started ? Number(process.hrtime.bigint() - started) / 1_000_000_000 : 0;
    metrics.observeRequest(
      request.method,
      request.routeOptions.url ?? "unknown",
      reply.statusCode,
      duration,
    );
  });

  app.setErrorHandler((error, request, reply) => {
    const suppliedStatus = typeof error === "object" && error !== null && "statusCode" in error
      ? (error as { statusCode?: unknown }).statusCode
      : undefined;
    const statusCode = typeof suppliedStatus === "number" && suppliedStatus < 500
      ? suppliedStatus
      : 500;
    const errorType = error instanceof Error ? error.name : "Error";
    request.log.error({ requestId: request.id, errorType, statusCode }, "request failed");
    return reply.code(statusCode).send({
      error: statusCode === 500 ? "internal_server_error" : errorType,
      requestID: request.id,
    });
  });

  app.addHook("onRequest", async (request, reply) => {
    const routeURL = request.routeOptions.url ?? "";
    if (
      routeURL === "/health" ||
      routeURL === "/ready" ||
      routeURL === "/metrics" ||
      routeURL === "/v1/auth/google"
    ) return;
    if (routeURL === "/v1/sessions" && request.method === "POST") return;
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

  app.get("/health", { config: { rateLimit: false } }, async () => ({ status: "ok" }));

  app.get("/ready", { config: { rateLimit: false } }, async (_request, reply) => {
    try {
      await readinessCheck();
      return { status: "ready" };
    } catch {
      return reply.code(503).send({ status: "unavailable" });
    }
  });

  app.get("/metrics", { config: { rateLimit: false } }, async (request, reply) => {
    if (metricsBearerToken && bearerToken(request.headers.authorization) !== metricsBearerToken) {
      return reply.code(401).send({ error: "invalid_metrics_token" });
    }
    return reply.type(metrics.contentType).send(await metrics.render());
  });

  app.get("/v1/auth/google", async (request, reply) => {
    const parsed = oauthAuthorizationSchema.safeParse(request.query);
    if (!parsed.success) return reply.code(400).send({ error: "invalid_code_challenge" });
    return reply.redirect(identityProvider.googleAuthorizationURL(parsed.data.codeChallenge));
  });

  app.post("/v1/sessions", {
    config: { rateLimit: limits.sessions },
  }, async (request, reply) => {
    const parsed = oauthSessionSchema.safeParse(request.body);
    if (!parsed.success) return reply.code(400).send({ error: "invalid_oauth_token" });
    try {
      const issued = await identityProvider.authenticateOAuthToken(
        parsed.data.oauthToken,
        parsed.data.codeVerifier,
      );
      const existingAccount = await repository.accountForIdentity(issued.identity.subject);
      const account = existingAccount ?? (parsed.data.invitationCode
        ? await repository.consumeInvitation(
          invitationHash(parsed.data.invitationCode),
          issued.identity.subject,
          issued.identity.displayName,
        )
        : await repository.provisionParentAccount(
          issued.identity.subject,
          issued.identity.displayName,
        ));
      if (!account) {
        await identityProvider.revokeSession(issued.accessToken);
        return reply.code(403).send({ error: "invalid_invitation" });
      }
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

  app.get("/v1/sessions", async (request) => {
    const account = requiredAccount(request);
    const members = await repository.membersForFamily(account.familyID);
    const member = members.find((candidate) => candidate.id === account.memberID);
    return {
      accountID: account.memberID,
      displayName: member?.name ?? account.memberID,
      role: account.role,
      accessToken: bearerToken(request.headers.authorization),
    };
  });

  app.delete("/v1/sessions", async (request, reply) => {
    const token = bearerToken(request.headers.authorization);
    if (!token) return reply.code(401).send({ error: "missing_bearer_token" });
    await identityProvider.revokeSession(token);
    return reply.code(204).send();
  });

  app.post("/v1/invitations", {
    config: { rateLimit: limits.invitations },
  }, async (request, reply) => {
    const account = await requireParent(request, reply);
    if (!account) return;
    const parsed = invitationSchema.safeParse(request.body);
    if (!parsed.success) return reply.code(400).send({ error: "invalid_invitation" });
    const code = randomBytes(24).toString("base64url");
    const expiresAt = new Date(Date.now() + 7 * 24 * 60 * 60 * 1000).toISOString();
    const id = randomUUID();
    await repository.saveInvitation({
      id,
      codeHash: invitationHash(code),
      familyID: account.familyID,
      recipientEmail: parsed.data.email,
      role: parsed.data.role,
      expiresAt,
    });
    const members = await repository.membersForFamily(account.familyID);
    const inviterName = members.find((member) => member.id === account.memberID)?.name
      ?? "Your family";
    const invitationURL = new URL("rallyroo://invite");
    invitationURL.searchParams.set("code", code);
    try {
      await invitationEmailSender.send({
        recipientEmail: parsed.data.email,
        inviterName,
        role: parsed.data.role,
        invitationURL: invitationURL.toString(),
        expiresAt,
      });
    } catch {
      await repository.cancelInvitation(account.familyID, id);
      return reply.code(502).send({ error: "invitation_email_failed" });
    }
    await repository.markFamilyChanged(account.familyID);
    return reply.code(201).send({
      id,
      code,
      email: parsed.data.email,
      role: parsed.data.role,
      expiresAt,
    });
  });

  app.get("/v1/invitations", async (request, reply) => {
    const account = await requireParent(request, reply);
    if (!account) return;
    return (await repository.pendingInvitations(account.familyID)).map((invitation) => ({
      id: invitation.id,
      email: invitation.recipientEmail,
      role: invitation.role,
      expiresAt: invitation.expiresAt,
    }));
  });

  app.delete("/v1/invitations/:id", async (request, reply) => {
    const account = await requireParent(request, reply);
    if (!account) return;
    const cancelled = await repository.cancelInvitation(
      account.familyID,
      (request.params as { id: string }).id,
    );
    if (!cancelled) return reply.code(404).send({ error: "invitation_not_found" });
    await repository.markFamilyChanged(account.familyID);
    return reply.code(204).send();
  });

  app.post("/v1/invitations/:id/resend", {
    config: { rateLimit: limits.invitations },
  }, async (request, reply) => {
    const account = await requireParent(request, reply);
    if (!account) return;
    const invitationID = (request.params as { id: string }).id;
    const existing = (await repository.pendingInvitations(account.familyID))
      .find((invitation) => invitation.id === invitationID);
    if (!existing) return reply.code(404).send({ error: "invitation_not_found" });
    if (!existing.recipientEmail) {
      return reply.code(400).send({ error: "invitation_email_missing" });
    }
    const code = randomBytes(24).toString("base64url");
    const expiresAt = new Date(Date.now() + 7 * 24 * 60 * 60 * 1000).toISOString();
    const invitation = await repository.rotateInvitation(
      account.familyID,
      invitationID,
      invitationHash(code),
      expiresAt,
    );
    if (!invitation) return reply.code(404).send({ error: "invitation_not_found" });
    const members = await repository.membersForFamily(account.familyID);
    const inviterName = members.find((member) => member.id === account.memberID)?.name
      ?? "Your family";
    const invitationURL = new URL("rallyroo://invite");
    invitationURL.searchParams.set("code", code);
    try {
      await invitationEmailSender.send({
        recipientEmail: existing.recipientEmail,
        inviterName,
        role: invitation.role,
        invitationURL: invitationURL.toString(),
        expiresAt: invitation.expiresAt,
      });
    } catch {
      await repository.rotateInvitation(
        account.familyID,
        invitationID,
        existing.codeHash,
        existing.expiresAt,
      );
      return reply.code(502).send({ error: "invitation_email_failed" });
    }
    await repository.markFamilyChanged(account.familyID);
    return {
      id: invitation.id,
      code,
      email: existing.recipientEmail,
      role: invitation.role,
      expiresAt: invitation.expiresAt,
    };
  });

  app.get("/v1/locations/search", {
    config: { rateLimit: limits.locations },
  }, async (request, reply) => {
    const parsed = locationSearchSchema.safeParse(request.query);
    if (!parsed.success) return reply.code(400).send({ error: "invalid_location_query" });
    return locationSearchProvider.search(parsed.data.q);
  });

  app.put("/v1/devices/:token", async (request, reply) => {
    const account = requiredAccount(request);
    const token = (request.params as { token: string }).token;
    if (token.length < 10 || token.length > 256) {
      return reply.code(400).send({ error: "invalid_device_token" });
    }
    await repository.saveDeviceToken(account.familyID, account.memberID, token);
    return reply.code(204).send();
  });

  app.delete("/v1/devices/:token", async (request, reply) => {
    const account = requiredAccount(request);
    await repository.deleteDeviceToken(
      account.memberID,
      (request.params as { token: string }).token,
    );
    return reply.code(204).send();
  });

  app.get("/v1/changes", async (request) => {
    const account = requiredAccount(request);
    return { version: await repository.familyChangeVersion(account.familyID) };
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
    const { recurrence, ...eventData } = parsed.data;
    const event: FamilyEvent = {
      ...eventData,
      familyID: account.familyID,
      ...(recurrence !== undefined ? { recurrence } : {}),
    };
    const existing = await repository.eventsForFamily(account.familyID);
    const conflicts = detectConflicts(event, existing.filter((candidate) => candidate.id !== event.id));
    await repository.saveEvent(event);
    await repository.markFamilyChanged(account.familyID);
    const deviceTokens = await repository.deviceTokensForFamily(account.familyID);
    try {
      await pushNotificationProvider.send(deviceTokens, {
        title: event.title,
        body: conflicts.length > 0
          ? "Schedule conflict detected. Open Rallyroo to review."
          : "Your family schedule was updated.",
        data: { eventID: event.id },
      });
    } catch {
      // Saving the source-of-truth event must not fail because APNs is unavailable.
    }
    return { conflicts };
  });

  app.delete("/v1/events/:id", async (request, reply) => {
    const account = await requireParent(request, reply);
    if (!account) return;
    await repository.deleteEvent(account.familyID, (request.params as { id: string }).id);
    await repository.markFamilyChanged(account.familyID);
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
    await repository.markFamilyChanged(account.familyID);
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
    await repository.markFamilyChanged(account.familyID);
    return reply.code(204).send();
  });

  return app;
}

function invitationHash(code: string): string {
  return createHash("sha256").update(code).digest("hex");
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
  const rangeEnd = [event, ...existingEvents].reduce((latest, candidate) => {
    const candidateEnd = new Date(candidate.recurrence?.endDate ?? candidate.endTime);
    return candidateEnd > latest ? candidateEnd : latest;
  }, new Date(event.endTime));
  const eventOccurrences = occurrenceRanges(event, rangeEnd);
  for (const existing of existingEvents) {
    const overlaps = eventOccurrences.some((occurrence) =>
      occurrenceRanges(existing, rangeEnd).some((existingOccurrence) =>
        occurrence.start < existingOccurrence.end && existingOccurrence.start < occurrence.end
      )
    );
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

function occurrenceRanges(event: FamilyEvent, rangeEnd: Date): Array<{ start: Date; end: Date }> {
  const firstStart = new Date(event.startTime);
  const duration = new Date(event.endTime).getTime() - firstStart.getTime();
  if (!event.recurrence) return [{ start: firstStart, end: new Date(firstStart.getTime() + duration) }];

  const recurrenceEnd = new Date(event.recurrence.endDate);
  const occurrences: Array<{ start: Date; end: Date }> = [];
  let start = firstStart;
  while (start <= recurrenceEnd && start <= rangeEnd) {
    occurrences.push({ start, end: new Date(start.getTime() + duration) });
    const next = new Date(start);
    switch (event.recurrence.frequency) {
      case "daily": next.setUTCDate(next.getUTCDate() + event.recurrence.interval); break;
      case "weekly": next.setUTCDate(next.getUTCDate() + 7 * event.recurrence.interval); break;
      case "monthly": next.setUTCMonth(next.getUTCMonth() + event.recurrence.interval); break;
    }
    if (next <= start) break;
    start = next;
  }
  return occurrences;
}

function clientEvent({ familyID: _familyID, ...event }: FamilyEvent) {
  return event;
}

function clientMember({ familyID: _familyID, ...member }: FamilyMember) {
  return member;
}
