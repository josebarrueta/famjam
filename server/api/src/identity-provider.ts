import type { Identity } from "./domain.js";

export interface IdentityProvider {
  verifySession(token: string): Promise<Identity>;
}
