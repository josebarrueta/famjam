import "dotenv/config";
import { APNSPushNotificationProvider } from "./apns-push-notification-provider.js";
import { buildApp } from "./app.js";
import { calendarURLProtection, fetchPublicCalendarFeed } from "./calendar-source-adapters.js";
import { CalendarSourceModule } from "./calendar-source-module.js";
import { databasePoolConfiguration } from "./database-configuration.js";
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
import { RallyrooMetrics } from "./metrics.js";
import { PostgresRallyrooRepository } from "./postgres-repository.js";
import { NoopPushNotificationProvider } from "./push-notification-provider.js";
import { RedisCache } from "./redis-cache.js";
import { ResendInvitationEmailSender } from "./resend-invitation-email-sender.js";
import { configuredSecret } from "./runtime-configuration.js";
import { StytchIdentityProvider } from "./stytch-identity-provider.js";

const databaseConfiguration = await databasePoolConfiguration();

const cache: Cache = process.env.REDIS_URL
  ? await RedisCache.connect(process.env.REDIS_URL)
  : new InMemoryCache();
const metrics = new RallyrooMetrics();
const identityProvider = new CachedIdentityProvider(
  StytchIdentityProvider.fromEnvironment(),
  cache,
  60,
  metrics,
);
const googlePlacesAPIKey = configuredSecret("GOOGLE_PLACES_API_KEY");
const locationProvider: LocationSearchProvider = googlePlacesAPIKey
  ? new GooglePlacesLocationSearchProvider(googlePlacesAPIKey)
  : new EmptyLocationSearchProvider();

const repository = PostgresRallyrooRepository.fromConfiguration(databaseConfiguration);
const calendarEncryptionKey = configuredSecret("CALENDAR_SOURCE_ENCRYPTION_KEY");
const calendarSources = calendarEncryptionKey
  ? new CalendarSourceModule({
    repository,
    ...calendarURLProtection(calendarEncryptionKey),
    fetchFeed: fetchPublicCalendarFeed,
  })
  : undefined;
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
  ...(calendarSources ? { calendarSources } : {}),
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
