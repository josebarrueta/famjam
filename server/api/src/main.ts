import "dotenv/config";
import { APNSPushNotificationProvider } from "./apns-push-notification-provider.js";
import { buildApp } from "./app.js";
import { InMemoryCache, type Cache } from "./cache.js";
import { CachedIdentityProvider } from "./cached-identity-provider.js";
import { CachedLocationSearchProvider } from "./cached-location-search-provider.js";
import {
  UnavailableInvitationEmailSender,
  type InvitationEmailSender,
} from "./invitation-email-sender.js";
import {
  EmptyLocationSearchProvider,
  GooglePlacesLocationSearchProvider,
  type LocationSearchProvider,
} from "./location-search-provider.js";
import { FamJamMetrics } from "./metrics.js";
import { PostgresFamJamRepository } from "./postgres-repository.js";
import { NoopPushNotificationProvider } from "./push-notification-provider.js";
import { RedisCache } from "./redis-cache.js";
import { ResendInvitationEmailSender } from "./resend-invitation-email-sender.js";
import { StytchIdentityProvider } from "./stytch-identity-provider.js";

const databaseURL = process.env.DATABASE_URL;
if (!databaseURL) throw new Error("DATABASE_URL is required");

const cache: Cache = process.env.REDIS_URL
  ? await RedisCache.connect(process.env.REDIS_URL)
  : new InMemoryCache();
const metrics = new FamJamMetrics();
const identityProvider = new CachedIdentityProvider(
  StytchIdentityProvider.fromEnvironment(),
  cache,
  60,
  metrics,
);
const googlePlacesAPIKey = process.env.GOOGLE_PLACES_API_KEY;
const locationProvider: LocationSearchProvider = googlePlacesAPIKey
  ? new GooglePlacesLocationSearchProvider(googlePlacesAPIKey)
  : new EmptyLocationSearchProvider();

const repository = PostgresFamJamRepository.fromConnectionString(databaseURL);
const invitationEmailSender: InvitationEmailSender = process.env.RESEND_API_KEY
  && process.env.INVITATION_EMAIL_FROM
  ? new ResendInvitationEmailSender({
    apiKey: process.env.RESEND_API_KEY,
    from: process.env.INVITATION_EMAIL_FROM,
  })
  : new UnavailableInvitationEmailSender();
const app = buildApp({
  identityProvider,
  repository,
  invitationEmailSender,
  locationSearchProvider: new CachedLocationSearchProvider(
    locationProvider,
    cache,
    30 * 60,
    metrics,
  ),
  pushNotificationProvider: APNSPushNotificationProvider.fromEnvironment()
    ?? new NoopPushNotificationProvider(),
  readinessCheck: () => repository.checkReadiness(),
  metrics,
  ...(process.env.METRICS_BEARER_TOKEN
    ? { metricsBearerToken: process.env.METRICS_BEARER_TOKEN }
    : {}),
  logger: {
    level: process.env.LOG_LEVEL ?? "info",
    redact: {
      paths: [
        "req.headers.authorization",
        "req.headers.cookie",
        "request.headers.authorization",
        "request.headers.cookie",
      ],
      censor: "[REDACTED]",
    },
  },
});
app.addHook("onClose", async () => {
  await Promise.all([cache.close?.(), repository.close()]);
});

const port = Number(process.env.PORT ?? "3000");
await app.listen({ port, host: process.env.HOST ?? "0.0.0.0" });
