import "dotenv/config";
import { APNSPushNotificationProvider } from "./apns-push-notification-provider.js";
import { buildApp } from "./app.js";
import { InMemoryCache, type Cache } from "./cache.js";
import { CachedIdentityProvider } from "./cached-identity-provider.js";
import { CachedLocationSearchProvider } from "./cached-location-search-provider.js";
import {
  EmptyLocationSearchProvider,
  GooglePlacesLocationSearchProvider,
  type LocationSearchProvider,
} from "./location-search-provider.js";
import { PostgresFamJamRepository } from "./postgres-repository.js";
import { NoopPushNotificationProvider } from "./push-notification-provider.js";
import { RedisCache } from "./redis-cache.js";
import { StytchIdentityProvider } from "./stytch-identity-provider.js";

const databaseURL = process.env.DATABASE_URL;
if (!databaseURL) throw new Error("DATABASE_URL is required");

const cache: Cache = process.env.REDIS_URL
  ? await RedisCache.connect(process.env.REDIS_URL)
  : new InMemoryCache();
const identityProvider = new CachedIdentityProvider(
  StytchIdentityProvider.fromEnvironment(),
  cache,
);
const googlePlacesAPIKey = process.env.GOOGLE_PLACES_API_KEY;
const locationProvider: LocationSearchProvider = googlePlacesAPIKey
  ? new GooglePlacesLocationSearchProvider(googlePlacesAPIKey)
  : new EmptyLocationSearchProvider();

const app = buildApp({
  identityProvider,
  repository: PostgresFamJamRepository.fromConnectionString(databaseURL),
  locationSearchProvider: new CachedLocationSearchProvider(locationProvider, cache),
  pushNotificationProvider: APNSPushNotificationProvider.fromEnvironment()
    ?? new NoopPushNotificationProvider(),
});
app.addHook("onClose", async () => { await cache.close?.(); });

const port = Number(process.env.PORT ?? "3000");
await app.listen({ port, host: process.env.HOST ?? "0.0.0.0" });
