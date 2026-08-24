import { describe, expect, it } from "vitest";
import { StytchIdentityProvider } from "../src/stytch-identity-provider.js";

describe("StytchIdentityProvider", () => {
  it("verifies a Stytch session JWT and returns its user identity", async () => {
    const provider = new StytchIdentityProvider({
      async authenticateJwt({ session_jwt }) {
        expect(session_jwt).toBe("stytch-jwt");
        return { session: { user_id: "user-test-123" }, session_jwt };
      },
    });

    const identity = await provider.verifySession("stytch-jwt");

    expect(identity.subject).toBe("user-test-123");
  });
});
