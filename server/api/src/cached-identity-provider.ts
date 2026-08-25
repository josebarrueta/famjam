import { createHash } from "node:crypto";
import type { Cache } from "./cache.js";
import type { Identity } from "./domain.js";
import type { IdentityProvider, IssuedIdentitySession } from "./identity-provider.js";

export class CachedIdentityProvider implements IdentityProvider {
  constructor(
    private readonly provider: IdentityProvider,
    private readonly cache: Cache,
    private readonly ttlSeconds: number = 60,
  ) {}

  googleAuthorizationURL(codeChallenge: string): string {
    return this.provider.googleAuthorizationURL(codeChallenge);
  }

  async authenticateOAuthToken(token: string, codeVerifier: string): Promise<IssuedIdentitySession> {
    const issued = await this.provider.authenticateOAuthToken(token, codeVerifier);
    try {
      await this.cache.set(cacheKey(issued.accessToken), issued.identity, this.ttlSeconds);
    } catch {
      // Authentication remains available when an optional cache is unavailable.
    }
    return issued;
  }

  async verifySession(token: string): Promise<Identity> {
    const key = cacheKey(token);
    try {
      const cached = await this.cache.get<Identity>(key);
      if (cached) return cached;
    } catch {
      // Fall through to the source of truth.
    }
    const identity = await this.provider.verifySession(token);
    try {
      await this.cache.set(key, identity, this.ttlSeconds);
    } catch {
      // Verification succeeded; cache population is best effort.
    }
    return identity;
  }

  async revokeSession(token: string): Promise<void> {
    await this.cache.delete(cacheKey(token));
    await this.provider.revokeSession(token);
  }
}

function cacheKey(token: string): string {
  return `identity:v1:${createHash("sha256").update(token).digest("hex")}`;
}
