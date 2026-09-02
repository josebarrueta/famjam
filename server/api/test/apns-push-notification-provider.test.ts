import { describe, expect, it } from "vitest";
import { APNSPushNotificationProvider } from "../src/apns-push-notification-provider.js";

describe("APNSPushNotificationProvider", () => {
  it("loads rotating APNs credentials from mounted files", () => {
    const reads: string[] = [];
    const provider = APNSPushNotificationProvider.fromEnvironment({
      APNS_KEY_ID_FILE: "/run/secrets/apns/key-id",
      APNS_PRIVATE_KEY_FILE: "/run/secrets/apns/private-key",
      APNS_TEAM_ID: "TEAM123",
      APNS_BUNDLE_ID: "dev.rallyroo.app",
      APNS_ENV: "production",
    }, (path) => {
      reads.push(path);
      return path.endsWith("key-id") ? "KEY123" : "private-key";
    });

    expect(provider).not.toBeNull();
    expect(reads).toEqual([
      "/run/secrets/apns/key-id",
      "/run/secrets/apns/private-key",
    ]);
  });
});
