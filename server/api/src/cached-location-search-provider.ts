import { createHash } from "node:crypto";
import type { Cache } from "./cache.js";
import type { LocationSearchProvider, LocationSuggestion } from "./location-search-provider.js";
import { NoopTelemetry, type Telemetry } from "./metrics.js";

export class CachedLocationSearchProvider implements LocationSearchProvider {
  constructor(
    private readonly provider: LocationSearchProvider,
    private readonly cache: Cache,
    private readonly ttlSeconds: number = 30 * 60,
    private readonly telemetry: Telemetry = new NoopTelemetry(),
  ) {}

  async search(query: string): Promise<LocationSuggestion[]> {
    const normalized = query.trim().toLocaleLowerCase("en-US").replaceAll(/\s+/g, " ");
    const key = `locations:v1:${createHash("sha256").update(normalized).digest("hex")}`;
    try {
      const cached = await this.cache.get<LocationSuggestion[]>(key);
      this.telemetry.observeCache("locations", cached ? "hit" : "miss");
      if (cached) return cached;
    } catch {
      this.telemetry.observeCache("locations", "error");
      // Fall through to Google Places when the optional cache is unavailable.
    }
    const started = process.hrtime.bigint();
    let suggestions: LocationSuggestion[];
    try {
      suggestions = await this.provider.search(normalized);
      this.telemetry.observeProvider(
        "google_places",
        "success",
        Number(process.hrtime.bigint() - started) / 1_000_000_000,
      );
    } catch (error) {
      this.telemetry.observeProvider(
        "google_places",
        "failure",
        Number(process.hrtime.bigint() - started) / 1_000_000_000,
      );
      throw error;
    }
    try {
      await this.cache.set(key, suggestions, this.ttlSeconds);
    } catch {
      this.telemetry.observeCache("locations", "error");
      // Search succeeded; cache population is best effort.
    }
    return suggestions;
  }
}
