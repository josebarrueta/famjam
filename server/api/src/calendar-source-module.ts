import { createHash, randomUUID } from "node:crypto";
import ICAL from "ical.js";
import type { FamilyEvent } from "./domain.js";

export interface CalendarSource {
  id: string;
  familyID: string;
  name: string;
  protectedURL: string;
  participantIDs: string[];
  status: "pending" | "ready" | "error";
  lastSyncedAt: string | null;
  lastError: string | null;
  etag: string | null;
  lastModified: string | null;
}

export interface PublicCalendarSource {
  id: string;
  name: string;
  participantIDs: string[];
  status: CalendarSource["status"];
  lastSyncedAt: string | null;
  lastError: string | null;
}

export interface ImportedCalendarEvent {
  familyID: string;
  sourceID: string;
  sourceName: string;
  externalUID: string;
  title: string;
  startTime: string;
  endTime: string;
  location: string | null;
  participantIDs: string[];
  fingerprint: string;
}

export interface CalendarSourceRepository {
  saveCalendarSource(source: CalendarSource): Promise<void>;
  calendarSource(familyID: string, sourceID: string): Promise<CalendarSource | null>;
  calendarSourcesForFamily(familyID: string): Promise<CalendarSource[]>;
  deleteCalendarSource(familyID: string, sourceID: string): Promise<boolean>;
  replaceCalendarEvents(source: CalendarSource, events: ImportedCalendarEvent[]): Promise<void>;
  calendarEventsForFamily(familyID: string): Promise<ImportedCalendarEvent[]>;
}

export interface CalendarFeedResponse {
  body: string;
  etag?: string;
  lastModified?: string;
  notModified?: boolean;
}

export interface CalendarFeedValidators {
  etag?: string;
  lastModified?: string;
}

export class CalendarSourceSyncError extends Error {
  readonly statusCode = 502;

  constructor() {
    super("Calendar source synchronization failed");
    this.name = "CalendarSourceSyncError";
  }
}

interface CalendarSourceModuleDependencies {
  repository: CalendarSourceRepository;
  protectURL: (url: string) => string;
  revealURL: (protectedURL: string) => string;
  fetchFeed: (url: string, validators?: CalendarFeedValidators) => Promise<CalendarFeedResponse>;
}

export class CalendarSourceModule {
  constructor(private readonly dependencies: CalendarSourceModuleDependencies) {}

  async create(input: {
    familyID: string;
    name: string;
    url: string;
    participantIDs: string[];
  }): Promise<PublicCalendarSource> {
    const source: CalendarSource = {
      id: randomUUID(),
      familyID: input.familyID,
      name: input.name,
      protectedURL: this.dependencies.protectURL(input.url),
      participantIDs: [...new Set(input.participantIDs)].sort(),
      status: "pending",
      lastSyncedAt: null,
      lastError: null,
      etag: null,
      lastModified: null,
    };
    await this.dependencies.repository.saveCalendarSource(source);
    return publicCalendarSource(source);
  }

  async list(familyID: string): Promise<PublicCalendarSource[]> {
    return (await this.dependencies.repository.calendarSourcesForFamily(familyID))
      .map(publicCalendarSource);
  }

  async delete(familyID: string, sourceID: string): Promise<boolean> {
    return this.dependencies.repository.deleteCalendarSource(familyID, sourceID);
  }

  async sync(familyID: string, sourceID: string): Promise<PublicCalendarSource | null> {
    const source = await this.dependencies.repository.calendarSource(familyID, sourceID);
    if (!source) return null;
    try {
      const response = await this.dependencies.fetchFeed(
        this.dependencies.revealURL(source.protectedURL),
        {
          ...(source.etag ? { etag: source.etag } : {}),
          ...(source.lastModified ? { lastModified: source.lastModified } : {}),
        },
      );
      const synchronized: CalendarSource = {
        ...source,
        status: "ready",
        lastSyncedAt: new Date().toISOString(),
        lastError: null,
        etag: response.etag ?? source.etag,
        lastModified: response.lastModified ?? source.lastModified,
      };
      if (response.notModified) {
        await this.dependencies.repository.saveCalendarSource(synchronized);
        return publicCalendarSource(synchronized);
      }
      const events = parseCalendar(response.body).map((event) => ({
        ...event,
        familyID,
        sourceID: source.id,
        sourceName: source.name,
        participantIDs: source.participantIDs,
        fingerprint: eventFingerprint(event),
      }));
      await this.dependencies.repository.replaceCalendarEvents(synchronized, events);
      return publicCalendarSource(synchronized);
    } catch {
      await this.dependencies.repository.saveCalendarSource({
        ...source,
        status: "error",
        lastError: "sync_failed",
      });
      throw new CalendarSourceSyncError();
    }
  }

  async events(familyID: string): Promise<FamilyEvent[]> {
    return deduplicateEvents(
      familyID,
      await this.dependencies.repository.calendarEventsForFamily(familyID),
    );
  }
}

function parseCalendar(body: string): Array<Pick<
  ImportedCalendarEvent,
  "externalUID" | "title" | "startTime" | "endTime" | "location"
>> {
  const calendar = new ICAL.Component(ICAL.parse(body));
  const components = calendar.getAllSubcomponents("vevent");
  const events = components
    .map((component) => new ICAL.Event(component))
    .filter((event) => !event.isRecurrenceException());
  const rangeStart = new Date();
  rangeStart.setUTCFullYear(rangeStart.getUTCFullYear() - 1);
  const rangeEnd = new Date();
  rangeEnd.setUTCFullYear(rangeEnd.getUTCFullYear() + 2);
  const result: Array<Pick<
    ImportedCalendarEvent,
    "externalUID" | "title" | "startTime" | "endTime" | "location"
  >> = [];
  let iterationCount = 0;

  for (const event of events) {
    if (!event.uid || !event.summary?.trim()) {
      throw new Error("Calendar contains an invalid event");
    }
    if (!event.isRecurring()) {
      appendOccurrence(result, event.uid, event, event.startDate.toJSDate(), event.endDate.toJSDate());
      continue;
    }

    const iterator = event.iterator();
    let recurrence;
    while ((recurrence = iterator.next())) {
      iterationCount += 1;
      if (iterationCount > 50_000 || result.length > 5_000) {
        throw new Error("Calendar recurrence exceeds the expansion limit");
      }
      const details = event.getOccurrenceDetails(recurrence);
      const start = details.startDate.toJSDate();
      if (start > rangeEnd) break;
      if (start < rangeStart) continue;
      if (details.item.component.getFirstPropertyValue("status") === "CANCELLED") continue;
      appendOccurrence(
        result,
        `${event.uid}::${details.recurrenceId.toString()}`,
        details.item,
        start,
        details.endDate.toJSDate(),
      );
    }
  }
  return result;
}

function appendOccurrence(
  result: Array<Pick<
    ImportedCalendarEvent,
    "externalUID" | "title" | "startTime" | "endTime" | "location"
  >>,
  externalUID: string,
  event: InstanceType<typeof ICAL.Event>,
  start: Date,
  end: Date,
): void {
  if (!event.summary?.trim() || end <= start) {
    throw new Error("Calendar contains an invalid event");
  }
  result.push({
    externalUID,
    title: event.summary.trim(),
    startTime: start.toISOString(),
    endTime: end.toISOString(),
    location: event.location?.trim() || null,
  });
}

function eventFingerprint(event: {
  title: string;
  startTime: string;
  endTime: string;
  location: string | null;
}): string {
  return [
    normalizeText(event.title),
    new Date(event.startTime).toISOString(),
    new Date(event.endTime).toISOString(),
    normalizeText(event.location ?? ""),
  ].join("\u001f");
}

function normalizeText(value: string): string {
  return value.normalize("NFKC").trim().toLocaleLowerCase("en-US").replace(/\s+/g, " ");
}

function deduplicateEvents(familyID: string, events: ImportedCalendarEvent[]): FamilyEvent[] {
  const groups: ImportedCalendarEvent[][] = [];
  for (const event of events) {
    const group = groups.find((candidate) => candidate.some((existing) =>
      existing.externalUID === event.externalUID || existing.fingerprint === event.fingerprint
    ));
    if (group) group.push(event);
    else groups.push([event]);
  }

  return groups.map((group) => {
    const selected = [...group].sort((left, right) =>
      presentationPenalty(left.title) - presentationPenalty(right.title)
      || left.sourceID.localeCompare(right.sourceID)
    )[0]!;
    const allSameFingerprint = group.every((event) => event.fingerprint === selected.fingerprint);
    const stableKey = allSameFingerprint
      ? `fingerprint:${selected.fingerprint}`
      : `uid:${[...group].map((event) => event.externalUID).sort()[0]}`;
    return {
      id: deterministicUUID(`${familyID}\u001f${stableKey}`),
      familyID,
      title: selected.title,
      kidID: null,
      participantIDs: [...new Set(group.flatMap((event) => event.participantIDs))].sort(),
      startTime: selected.startTime,
      endTime: selected.endTime,
      location: selected.location,
      driver: null,
      source: "calendar",
      status: "confirmed",
      readOnly: true,
      provenance: group
        .map((event) => ({
          sourceID: event.sourceID,
          sourceName: event.sourceName,
          externalUID: event.externalUID,
        }))
        .sort((left, right) => left.sourceID.localeCompare(right.sourceID)),
    };
  });
}

function presentationPenalty(title: string): number {
  const letters = title.replace(/[^\p{L}]/gu, "");
  return letters.length > 1 && letters === letters.toLocaleUpperCase("en-US") ? 1 : 0;
}

function deterministicUUID(value: string): string {
  const bytes = Buffer.from(createHash("sha256").update(value).digest().subarray(0, 16));
  bytes[6] = (bytes[6]! & 0x0f) | 0x50;
  bytes[8] = (bytes[8]! & 0x3f) | 0x80;
  const hex = bytes.toString("hex");
  return `${hex.slice(0, 8)}-${hex.slice(8, 12)}-${hex.slice(12, 16)}-${hex.slice(16, 20)}-${hex.slice(20)}`;
}

function publicCalendarSource(source: CalendarSource): PublicCalendarSource {
  return {
    id: source.id,
    name: source.name,
    participantIDs: source.participantIDs,
    status: source.status,
    lastSyncedAt: source.lastSyncedAt,
    lastError: source.lastError,
  };
}
