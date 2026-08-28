import { describe, expect, it } from "vitest";
import { InMemoryCache } from "../src/cache.js";
import { CachedIdentityProvider } from "../src/cached-identity-provider.js";
import { CachedLocationSearchProvider } from "../src/cached-location-search-provider.js";
import type { IdentityProvider } from "../src/identity-provider.js";
import type { LocationSearchProvider } from "../src/location-search-provider.js";
import { RallyrooMetrics } from "../src/metrics.js";

describe("server caches", () => {
  it("caches verified identities and invalidates them on revocation", async () => {
    let verifications = 0;
    const provider: IdentityProvider = {
      googleAuthorizationURL: () => "https://identity.example/google",
      appleAuthorizationURL: () => "https://identity.example/apple",
      authenticateOAuthToken: async () => ({
        identity: { subject: "user-1", displayName: "Alex" },
        accessToken: "token-1",
      }),
      verifySession: async () => {
        verifications += 1;
        return { subject: "user-1", displayName: "Alex" };
      },
      revokeSession: async () => {},
    };
    const metrics = new RallyrooMetrics();
    const cached = new CachedIdentityProvider(provider, new InMemoryCache(), 60, metrics);

    await cached.verifySession("token-1");
    await cached.verifySession("token-1");
    expect(verifications).toBe(1);

    await cached.revokeSession("token-1");
    await cached.verifySession("token-1");
    expect(verifications).toBe(2);
    const output = await metrics.render();
    expect(output).toContain('rallyroo_cache_operations_total{cache="identities",result="miss"} 2');
    expect(output).toContain('rallyroo_cache_operations_total{cache="identities",result="hit"} 1');
    expect(output).toContain('provider="stytch",result="success"');
  });

  it("exports cache and provider outcomes without exposing cache keys", async () => {
    const metrics = new RallyrooMetrics();
    const provider: LocationSearchProvider = {
      async search(query) {
        if (query === "failure") throw new Error("provider unavailable");
        return [{ id: "place-1", address: "123 Main St, Springfield, IL, USA" }];
      },
    };
    const cached = new CachedLocationSearchProvider(
      provider,
      new InMemoryCache(),
      30 * 60,
      metrics,
    );

    await cached.search("123 Main");
    await cached.search("123 main");
    await expect(cached.search("failure")).rejects.toThrow("provider unavailable");
    const output = await metrics.render();

    expect(output).toContain('rallyroo_cache_operations_total{cache="locations",result="miss"} 2');
    expect(output).toContain('rallyroo_cache_operations_total{cache="locations",result="hit"} 1');
    expect(output).toContain('provider="google_places",result="success"');
    expect(output).toContain('provider="google_places",result="failure"');
  });

  it("shares cached address results across normalized queries", async () => {
    let searches = 0;
    const provider: LocationSearchProvider = {
      async search() {
        searches += 1;
        return [{ id: "place-1", address: "123 Main St, Springfield, IL, USA" }];
      },
    };
    const cached = new CachedLocationSearchProvider(provider, new InMemoryCache());

    await cached.search(" 123 Main ");
    await cached.search("123 main");

    expect(searches).toBe(1);
  });
});
