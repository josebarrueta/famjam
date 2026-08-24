import { describe, expect, it } from "vitest";
import { StytchIdentityProvider } from "../src/stytch-identity-provider.js";

const codeChallenge = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQ";
const codeVerifier = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopq";

function provider() {
  return new StytchIdentityProvider({
    publicToken: "public-token-test-project",
    callbackURL: "famjam://oauth-callback",
    environmentURL: "https://test.stytch.com/",
    sessions: {
      async authenticate({ session_token }) {
        expect(session_token).toBe("stytch-session-token");
        return { session: { user_id: "user-test-123" } };
      },
      async revoke() {},
    },
    oauth: {
      async authenticate({ token, session_duration_minutes, code_verifier }) {
        expect(token).toBe("oauth-token");
        expect(session_duration_minutes).toBe(10_080);
        expect(code_verifier).toBe(codeVerifier);
        return { user_id: "user-test-123", session_token: "stytch-session-token" };
      },
    },
  });
}

describe("StytchIdentityProvider", () => {
  it("builds the backend-owned Google authorization URL", () => {
    const url = new URL(provider().googleAuthorizationURL(codeChallenge));
    expect(`${url.origin}${url.pathname}`).toBe("https://test.stytch.com/v1/public/oauth/google/start");
    expect(url.searchParams.get("public_token")).toBe("public-token-test-project");
    expect(url.searchParams.get("login_redirect_url")).toBe("famjam://oauth-callback");
    expect(url.searchParams.get("signup_redirect_url")).toBe("famjam://oauth-callback");
    expect(url.searchParams.get("code_challenge")).toBe(codeChallenge);
  });

  it("exchanges an OAuth token for a server-created Stytch session", async () => {
    const issued = await provider().authenticateOAuthToken("oauth-token", codeVerifier);
    expect(issued).toEqual({
      identity: { subject: "user-test-123", displayName: "user-test-123" },
      accessToken: "stytch-session-token",
    });
  });

  it("verifies a Stytch session JWT and returns its user identity", async () => {
    const identity = await provider().verifySession("stytch-session-token");
    expect(identity.subject).toBe("user-test-123");
  });
});
