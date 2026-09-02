import { describe, expect, it } from "vitest";
import { StytchIdentityProvider } from "../src/stytch-identity-provider.js";

const codeChallenge = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQ";
const codeVerifier = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopq";

function provider() {
  return new StytchIdentityProvider({
    publicToken: "public-token-test-project",
    callbackURL: "rallyroo://oauth-callback",
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
        return {
          user_id: "user-test-123",
          session_token: "stytch-session-token",
          user: { name: { first_name: "Sam", last_name: "Rivera" } },
        };
      },
    },
  });
}

describe("StytchIdentityProvider", () => {
  it("uses the configured custom domain for browser and server Stytch calls", () => {
    let clientConfiguration: { custom_base_url?: string } | undefined;
    const configured = StytchIdentityProvider.fromEnvironment({
      STYTCH_PROJECT_ID: "project-live-test",
      STYTCH_SECRET_FILE: "/run/secrets/stytch/secret",
      STYTCH_PUBLIC_TOKEN: "public-token-live-test",
      STYTCH_OAUTH_CALLBACK_URL: "rallyroo://oauth-callback",
      STYTCH_ENV: "live",
      STYTCH_CUSTOM_BASE_URL: "https://login.rallyroo.dev",
    }, (path) => {
      expect(path).toBe("/run/secrets/stytch/secret");
      return "secret-live-test";
    }, (configuration) => {
      clientConfiguration = configuration;
      return {
        sessions: { async authenticate() { throw new Error("not called"); }, async revoke() {} },
        oauth: { async authenticate() { throw new Error("not called"); } },
      };
    });

    expect(clientConfiguration?.custom_base_url).toBe("https://login.rallyroo.dev/");
    const url = new URL(configured.googleAuthorizationURL(codeChallenge));
    expect(`${url.origin}${url.pathname}`).toBe(
      "https://login.rallyroo.dev/v1/public/oauth/google/start",
    );
  });

  it("builds the backend-owned Google authorization URL", () => {
    const url = new URL(provider().googleAuthorizationURL(codeChallenge));
    expect(`${url.origin}${url.pathname}`).toBe("https://test.stytch.com/v1/public/oauth/google/start");
    expect(url.searchParams.get("public_token")).toBe("public-token-test-project");
    expect(url.searchParams.get("login_redirect_url")).toBe("rallyroo://oauth-callback");
    expect(url.searchParams.get("signup_redirect_url")).toBe("rallyroo://oauth-callback");
    expect(url.searchParams.get("code_challenge")).toBe(codeChallenge);
  });

  it("builds the backend-owned Apple authorization URL", () => {
    const url = new URL(provider().appleAuthorizationURL(codeChallenge));
    expect(`${url.origin}${url.pathname}`).toBe("https://test.stytch.com/v1/public/oauth/apple/start");
    expect(url.searchParams.get("public_token")).toBe("public-token-test-project");
    expect(url.searchParams.get("login_redirect_url")).toBe("rallyroo://oauth-callback");
    expect(url.searchParams.get("signup_redirect_url")).toBe("rallyroo://oauth-callback");
    expect(url.searchParams.get("code_challenge")).toBe(codeChallenge);
  });

  it("exchanges an OAuth token for a server-created Stytch session", async () => {
    const issued = await provider().authenticateOAuthToken("oauth-token", codeVerifier);
    expect(issued).toEqual({
      identity: { subject: "user-test-123", displayName: "Sam Rivera" },
      accessToken: "stytch-session-token",
    });
  });

  it("verifies a Stytch session JWT and returns its user identity", async () => {
    const identity = await provider().verifySession("stytch-session-token");
    expect(identity.subject).toBe("user-test-123");
  });
});
