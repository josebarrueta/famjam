import { createHash } from "node:crypto";
import type { Cache } from "./cache.js";
import type { LocationSearchProvider, LocationSuggestion } from "./location-search-provider.js";

export class CachedLocationSearchProvider implements LocationSearchProvider {
  constructor(
    private readonly provider: LocationSearchProvider,
    private readonly cache: Cache,
    private readonly ttlSeconds: number = 30 * 60,
  ) {}

  async search(query: string): Promise<LocationSuggestion[]> {
    const normalized = query.trim().toLocaleLowerCase("en-US").replaceAll(/\s+/g, " ");
    const key = `locations:v1:${createHash("sha256").update(normalized).digest("hex")}`;
    try {
      const cached = await this.cache.get<LocationSuggestion[]>(key);
      if (cached) return cached;
    } catch {
      // Fall through to Google Places when the optional cache is unavailable.
    }
    const suggestions = await this.provider.search(normalized);
    try {
      await this.cache.set(key, suggestions, this.ttlSeconds);
    } catch {
      // Search succeeded; cache population is best effort.
    }
    return suggestions;
  }
}
