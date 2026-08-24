import { Client, envs } from "stytch";
import type { Identity } from "./domain.js";
import type { IdentityProvider } from "./identity-provider.js";

export interface StytchSessionVerifier {
  authenticateJwt(request: { session_jwt: string }): Promise<{
    session: { user_id: string };
    session_jwt: string;
  }>;
}

export class StytchIdentityProvider implements IdentityProvider {
  constructor(private readonly sessions: StytchSessionVerifier) {}

  async verifySession(token: string): Promise<Identity> {
    const result = await this.sessions.authenticateJwt({ session_jwt: token });
    return {
      subject: result.session.user_id,
      displayName: result.session.user_id,
    };
  }

  static fromEnvironment(environment: NodeJS.ProcessEnv = process.env): StytchIdentityProvider {
    const projectID = environment.STYTCH_PROJECT_ID;
    const secret = environment.STYTCH_SECRET;
    if (!projectID || !secret) {
      throw new Error("STYTCH_PROJECT_ID and STYTCH_SECRET are required");
    }
    const environmentURL = environment.STYTCH_ENV === "live" ? envs.live : envs.test;
    const client = new Client({ project_id: projectID, secret, env: environmentURL });
    return new StytchIdentityProvider(client.sessions);
  }
}
