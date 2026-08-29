import { createHmac } from "node:crypto";

const endpoint = process.env.RALLYROO_DEPLOYMENT_ALERT_WEBHOOK_URL;
const secret = process.env.RALLYROO_DEPLOYMENT_ALERT_HMAC_SECRET;
if (!endpoint || !secret) {
  console.error("RALLYROO_DEPLOYMENT_ALERT_WEBHOOK_URL and RALLYROO_DEPLOYMENT_ALERT_HMAC_SECRET are required");
  process.exit(2);
}

const body = JSON.stringify({
  involvedObject: {
    apiVersion: "helm.toolkit.fluxcd.io/v2",
    kind: "HelmRelease",
    name: "rallyroo",
    namespace: "rallyroo",
    uid: "00000000-0000-4000-8000-000000000001",
  },
  metadata: {
    "helm.toolkit.fluxcd.io/revision": "setup-test",
    application: "rallyroo",
    environment: "home-production",
  },
  severity: "error",
  reason: "SetupTest",
  message: "Controlled setup test: deployment alerting is connected.",
  reportingController: "setup-wizard",
  timestamp: new Date().toISOString(),
});
const signature = `sha256=${createHmac("sha256", secret).update(body).digest("hex")}`;
const response = await fetch(endpoint, {
  method: "POST",
  headers: {
    "content-type": "application/json",
    "x-signature": signature,
  },
  body,
});
if (response.status !== 202) {
  console.error(`Alert endpoint returned HTTP ${response.status}`);
  process.exit(1);
}
console.log("Deployment test event accepted by Resend Automation.");
