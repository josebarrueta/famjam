import { randomBytes } from "node:crypto";
import { describe, expect, it } from "vitest";
import {
  calendarURLProtection,
  fetchPublicCalendarFeed,
} from "../src/calendar-source-adapters.js";

describe("calendar source security adapters", () => {
  it("encrypts bearer-style calendar URLs and rejects tampering", () => {
    const protection = calendarURLProtection(randomBytes(32).toString("base64"));
    const url = "https://ical.example/private-family-token.ics";

    const protectedURL = protection.protectURL(url);

    expect(protectedURL).not.toContain("private-family-token");
    expect(protection.revealURL(protectedURL)).toBe(url);
    expect(() => protection.revealURL(`${protectedURL.slice(0, -1)}x`)).toThrow();
  });

  it("rejects calendar URLs that target private infrastructure", async () => {
    await expect(fetchPublicCalendarFeed("https://127.0.0.1/calendar.ics"))
      .rejects.toThrow("public addresses");
  });
});
