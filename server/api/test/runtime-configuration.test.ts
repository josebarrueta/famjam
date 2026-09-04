import { describe, expect, it } from "vitest";
import { configuredSecret } from "../src/runtime-configuration.js";

describe("configuredSecret", () => {
  it("prefers a mounted secret file over a legacy environment value", () => {
    const value = configuredSecret("PROVIDER_TOKEN", {
      PROVIDER_TOKEN: "legacy-local-value",
      PROVIDER_TOKEN_FILE: "/run/secrets/provider/token",
    }, (path) => {
      expect(path).toBe("/run/secrets/provider/token");
      return "mounted-value";
    });

    expect(value).toBe("mounted-value");
  });

  it("trims line endings from mounted secret files", () => {
    const value = configuredSecret("PROVIDER_TOKEN", {
      PROVIDER_TOKEN_FILE: "/run/secrets/provider/token",
    }, () => "mounted-value\n");

    expect(value).toBe("mounted-value");
  });

  it("retains environment compatibility for local development", () => {
    expect(configuredSecret("PROVIDER_TOKEN", {
      PROVIDER_TOKEN: "local-value",
    })).toBe("local-value");
  });
});
