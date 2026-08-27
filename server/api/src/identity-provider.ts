import type { Identity } from "./domain.js";

export interface IssuedIdentitySession {
  identity: Identity;
  accessToken: string;
}

/** Provider-neutral backend seam for hosted authentication and session lifecycle. */
export interface IdentityProvider {
  googleAuthorizationURL(codeChallenge: string): string;
  appleAuthorizationURL(codeChallenge: string): string;
  authenticateOAuthToken(token: string, codeVerifier: string): Promise<IssuedIdentitySession>;
  verifySession(token: string): Promise<Identity>;
  revokeSession(token: string): Promise<void>;
}
