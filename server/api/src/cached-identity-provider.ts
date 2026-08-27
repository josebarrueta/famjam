import { createHash } from "node:crypto";
import type { Cache } from "./cache.js";
import type { Identity } from "./domain.js";
import type { IdentityProvider, IssuedIdentitySession } from "./identity-provider.js";
import { NoopTelemetry, type ProviderResult, type Telemetry } from "./metrics.js";

export class CachedIdentityProvider implements IdentityProvider {
  constructor(
    private readonly provider: IdentityProvider,
    private readonly cache: Cache,
    private readonly ttlSeconds: number = 60,
    private readonly telemetry: Telemetry = new NoopTelemetry(),
  ) {}

  googleAuthorizationURL(codeChallenge: string): string {
    return this.provider.googleAuthorizationURL(codeChallenge);
  }

  appleAuthorizationURL(codeChallenge: string): string {
    return this.provider.appleAuthorizationURL(codeChallenge);
  }

  async authenticateOAuthToken(token: string, codeVerifier: string): Promise<IssuedIdentitySession> {
    const issued = await this.observeProvider(() =>
      this.provider.authenticateOAuthToken(token, codeVerifier)
    );
    try {
      await this.cache.set(cacheKey(issued.accessToken), issued.identity, this.ttlSeconds);
    } catch {
      this.telemetry.observeCache("identities", "error");
      // Authentication remains available when an optional cache is unavailable.
    }
    return issued;
  }

  async verifySession(token: string): Promise<Identity> {
    const key = cacheKey(token);
    try {
      const cached = await this.cache.get<Identity>(key);
      this.telemetry.observeCache("identities", cached ? "hit" : "miss");
      if (cached) return cached;
    } catch {
      this.telemetry.observeCache("identities", "error");
      // Fall through to the source of truth.
    }
    const identity = await this.observeProvider(() => this.provider.verifySession(token));
    try {
      await this.cache.set(key, identity, this.ttlSeconds);
    } catch {
      this.telemetry.observeCache("identities", "error");
      // Verification succeeded; cache population is best effort.
    }
    return identity;
  }

  async revokeSession(token: string): Promise<void> {
    try {
      await this.cache.delete(cacheKey(token));
    } catch {
      this.telemetry.observeCache("identities", "error");
    }
    await this.observeProvider(() => this.provider.revokeSession(token));
  }

  private async observeProvider<T>(operation: () => Promise<T>): Promise<T> {
    const started = process.hrtime.bigint();
    let result: ProviderResult = "success";
    try {
      return await operation();
    } catch (error) {
      result = "failure";
      throw error;
    } finally {
      this.telemetry.observeProvider(
        "stytch",
        result,
        Number(process.hrtime.bigint() - started) / 1_000_000_000,
      );
    }
  }
}

function cacheKey(token: string): string {
  return `identity:v1:${createHash("sha256").update(token).digest("hex")}`;
}
