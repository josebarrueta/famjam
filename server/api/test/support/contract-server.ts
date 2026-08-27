import { buildApp } from "../../src/app.js";
import { InMemoryFamJamRepository } from "../../src/in-memory-repository.js";
import type { IdentityProvider } from "../../src/identity-provider.js";

const identityProvider: IdentityProvider = {
  googleAuthorizationURL: () => "https://identity.example/google",
  appleAuthorizationURL: () => "https://identity.example/apple",
  async authenticateOAuthToken() {
    return {
      identity: { subject: "contract-parent", displayName: "Alex" },
      accessToken: "contract-token",
    };
  },
  async verifySession(token) {
    if (token !== "contract-token") throw new Error("invalid contract token");
    return { subject: "contract-parent", displayName: "Alex" };
  },
  async revokeSession() {},
};

const repository = new InMemoryFamJamRepository({
  accounts: [{
    identitySubject: "contract-parent",
    familyID: "contract-family",
    memberID: "parent-1",
    role: "parent",
  }],
  members: [
    { id: "kid-1", familyID: "contract-family", name: "Sam", role: "kid", colorTag: "purple" },
    { id: "parent-1", familyID: "contract-family", name: "Alex", role: "parent", colorTag: "blue" },
  ],
});

const app = buildApp({ identityProvider, repository });
const port = Number(process.env.CONTRACT_PORT ?? "3100");
await app.listen({ port, host: "127.0.0.1" });

async function shutdown() {
  await app.close();
  process.exit(0);
}
process.on("SIGINT", shutdown);
process.on("SIGTERM", shutdown);
