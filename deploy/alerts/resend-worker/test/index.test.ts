import { afterEach, describe, expect, it, vi } from "vitest";
import { handleRequest, type Environment } from "../src/index.js";

const environment: Environment = {
  FLUX_HMAC_SECRET: "test-hmac-secret",
  RESEND_API_KEY: "test-resend-key",
  ALERT_RECIPIENT: "operator@example.com",
};

const fluxEvent = {
  involvedObject: {
    apiVersion: "helm.toolkit.fluxcd.io/v2",
    kind: "HelmRelease",
    name: "rallyroo",
    namespace: "rallyroo",
    uid: "00000000-0000-4000-8000-000000000001",
  },
  metadata: {
    "helm.toolkit.fluxcd.io/revision": "0.1.4+abc123",
    application: "rallyroo",
    environment: "home-production",
  },
  severity: "error",
  reason: "UpgradeFailed",
  message: "pre-upgrade migration hook failed",
  reportingController: "helm-controller",
  timestamp: "2026-08-29T01:00:00Z",
};

async function signature(body: string, secret = environment.FLUX_HMAC_SECRET): Promise<string> {
  const key = await crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const bytes = new Uint8Array(await crypto.subtle.sign("HMAC", key, new TextEncoder().encode(body)));
  return `sha256=${Array.from(bytes, (byte) => byte.toString(16).padStart(2, "0")).join("")}`;
}

async function fluxRequest(event: unknown = fluxEvent, suppliedSignature?: string): Promise<Request> {
  const body = JSON.stringify(event);
  return new Request("https://alerts.example/flux", {
    method: "POST",
    headers: {
      "content-type": "application/json",
      "x-signature": suppliedSignature ?? await signature(body),
    },
    body,
  });
}

afterEach(() => vi.restoreAllMocks());

describe("deployment alert HTTP endpoint", () => {
  it("forwards an authenticated Rallyroo Helm failure as a Resend automation event", async () => {
    const resend = vi.fn().mockResolvedValue(new Response(JSON.stringify({ object: "event" }), { status: 202 }));

    const response = await handleRequest(await fluxRequest(), environment, resend);

    expect(response.status).toBe(202);
    expect(resend).toHaveBeenCalledOnce();
    const [url, init] = resend.mock.calls[0] as [string, RequestInit];
    expect(url).toBe("https://api.resend.com/events/send");
    expect(init.headers).toEqual({
      Authorization: "Bearer test-resend-key",
      "Content-Type": "application/json",
    });
    expect(JSON.parse(String(init.body))).toEqual({
      event: "deployment.failed",
      email: "operator@example.com",
      payload: {
        application: "rallyroo",
        environment: "home-production",
        object: "HelmRelease/rallyroo",
        namespace: "rallyroo",
        reason: "UpgradeFailed",
        message: "pre-upgrade migration hook failed",
        revision: "0.1.4+abc123",
        timestamp: "2026-08-29T01:00:00Z",
      },
    });
  });

  it("rejects an invalid HMAC without contacting Resend", async () => {
    const resend = vi.fn();
    const response = await handleRequest(await fluxRequest(fluxEvent, "sha256=00"), environment, resend);

    expect(response.status).toBe(401);
    expect(resend).not.toHaveBeenCalled();
  });

  it("rejects events outside the Rallyroo HelmRelease error boundary", async () => {
    const resend = vi.fn();
    const response = await handleRequest(
      await fluxRequest({ ...fluxEvent, severity: "info" }),
      environment,
      resend,
    );

    expect(response.status).toBe(422);
    expect(resend).not.toHaveBeenCalled();
  });

  it("returns a retryable error when Resend does not accept the event", async () => {
    const resend = vi.fn().mockResolvedValue(new Response("unavailable", { status: 503 }));
    const response = await handleRequest(await fluxRequest(), environment, resend);

    expect(response.status).toBe(502);
  });

  it("exposes only a shallow health endpoint to unauthenticated requests", async () => {
    expect((await handleRequest(new Request("https://alerts.example/health"), environment, vi.fn())).status).toBe(204);
    expect((await handleRequest(new Request("https://alerts.example/flux"), environment, vi.fn())).status).toBe(405);
    expect((await handleRequest(new Request("https://alerts.example/unknown"), environment, vi.fn())).status).toBe(404);
  });
});
