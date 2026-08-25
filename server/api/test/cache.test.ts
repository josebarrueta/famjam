import { describe, expect, it } from "vitest";
import { InMemoryCache } from "../src/cache.js";
import { CachedIdentityProvider } from "../src/cached-identity-provider.js";
import { CachedLocationSearchProvider } from "../src/cached-location-search-provider.js";
import type { IdentityProvider } from "../src/identity-provider.js";
import type { LocationSearchProvider } from "../src/location-search-provider.js";

describe("server caches", () => {
  it("caches verified identities and invalidates them on revocation", async () => {
    let verifications = 0;
    const provider: IdentityProvider = {
      googleAuthorizationURL: () => "https://identity.example",
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
    const cached = new CachedIdentityProvider(provider, new InMemoryCache());

    await cached.verifySession("token-1");
    await cached.verifySession("token-1");
    expect(verifications).toBe(1);

    await cached.revokeSession("token-1");
    await cached.verifySession("token-1");
    expect(verifications).toBe(2);
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
