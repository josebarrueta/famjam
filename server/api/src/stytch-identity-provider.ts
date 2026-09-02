import { Client, envs } from "stytch";
import type { Identity } from "./domain.js";
import type { IdentityProvider, IssuedIdentitySession } from "./identity-provider.js";
import { configuredSecret, type SecretFileReader } from "./runtime-configuration.js";

export interface StytchSessionClient {
  authenticate(request: { session_token: string }): Promise<{
    session: { user_id: string };
  }>;
  revoke(request: { session_token: string }): Promise<unknown>;
}

export interface StytchOAuthClient {
  authenticate(request: {
    token: string;
    session_duration_minutes: number;
    code_verifier: string;
  }): Promise<{
    user_id: string;
    session_token: string;
    user?: {
      name?: { first_name?: string; last_name?: string };
    };
  }>;
}

interface StytchIdentityProviderConfiguration {
  publicToken: string;
  callbackURL: string;
  environmentURL: string;
  sessions: StytchSessionClient;
  oauth: StytchOAuthClient;
}

export class StytchIdentityProvider implements IdentityProvider {
  constructor(private readonly configuration: StytchIdentityProviderConfiguration) {}

  googleAuthorizationURL(codeChallenge: string): string {
    const url = new URL("v1/public/oauth/google/start", this.configuration.environmentURL);
    url.searchParams.set("public_token", this.configuration.publicToken);
    url.searchParams.set("login_redirect_url", this.configuration.callbackURL);
    url.searchParams.set("signup_redirect_url", this.configuration.callbackURL);
    url.searchParams.set("code_challenge", codeChallenge);
    return url.toString();
  }

  appleAuthorizationURL(codeChallenge: string): string {
    const url = new URL("v1/public/oauth/apple/start", this.configuration.environmentURL);
    url.searchParams.set("public_token", this.configuration.publicToken);
    url.searchParams.set("login_redirect_url", this.configuration.callbackURL);
    url.searchParams.set("signup_redirect_url", this.configuration.callbackURL);
    url.searchParams.set("code_challenge", codeChallenge);
    return url.toString();
  }

  async authenticateOAuthToken(token: string, codeVerifier: string): Promise<IssuedIdentitySession> {
    const result = await this.configuration.oauth.authenticate({
      token,
      session_duration_minutes: 10_080,
      code_verifier: codeVerifier,
    });
    const providerName = [result.user?.name?.first_name, result.user?.name?.last_name]
      .filter((part): part is string => Boolean(part))
      .join(" ");
    return {
      identity: identity(result.user_id, providerName || result.user_id),
      accessToken: result.session_token,
    };
  }

  async verifySession(token: string): Promise<Identity> {
    const result = await this.configuration.sessions.authenticate({ session_token: token });
    return identity(result.session.user_id);
  }

  async revokeSession(token: string): Promise<void> {
    await this.configuration.sessions.revoke({ session_token: token });
  }

  static fromEnvironment(
    environment: NodeJS.ProcessEnv = process.env,
    readSecretFile?: SecretFileReader,
  ): StytchIdentityProvider {
    const projectID = environment.STYTCH_PROJECT_ID;
    const secret = configuredSecret("STYTCH_SECRET", environment, readSecretFile);
    const publicToken = environment.STYTCH_PUBLIC_TOKEN;
    const callbackURL = environment.STYTCH_OAUTH_CALLBACK_URL;
    if (!projectID || !secret || !publicToken || !callbackURL) {
      throw new Error(
        "STYTCH_PROJECT_ID, STYTCH_SECRET, STYTCH_PUBLIC_TOKEN, and STYTCH_OAUTH_CALLBACK_URL are required",
      );
    }
    const apiEnvironmentURL = environment.STYTCH_ENV === "live" ? envs.live : envs.test;
    const environmentURL = authorizationBaseURL(
      environment.STYTCH_CUSTOM_BASE_URL,
      apiEnvironmentURL,
    );
    const client = new Client({ project_id: projectID, secret, env: apiEnvironmentURL });
    return new StytchIdentityProvider({
      publicToken,
      callbackURL,
      environmentURL,
      sessions: client.sessions,
      oauth: client.oauth,
    });
  }
}

function authorizationBaseURL(customBaseURL: string | undefined, fallback: string): string {
  if (!customBaseURL) return fallback;
  const parsed = new URL(customBaseURL);
  if (parsed.protocol !== "https:" || parsed.username || parsed.password || parsed.search || parsed.hash) {
    throw new Error("STYTCH_CUSTOM_BASE_URL must be an HTTPS origin");
  }
  return `${parsed.origin}/`;
}

function identity(subject: string, displayName: string = subject): Identity {
  return { subject, displayName };
}
