import "dotenv/config";
import { buildApp } from "./app.js";
import {
  EmptyLocationSearchProvider,
  GooglePlacesLocationSearchProvider,
} from "./location-search-provider.js";
import { PostgresFamJamRepository } from "./postgres-repository.js";
import { StytchIdentityProvider } from "./stytch-identity-provider.js";

const databaseURL = process.env.DATABASE_URL;
if (!databaseURL) throw new Error("DATABASE_URL is required");

const googlePlacesAPIKey = process.env.GOOGLE_PLACES_API_KEY;
const app = buildApp({
  identityProvider: StytchIdentityProvider.fromEnvironment(),
  repository: PostgresFamJamRepository.fromConnectionString(databaseURL),
  locationSearchProvider: googlePlacesAPIKey
    ? new GooglePlacesLocationSearchProvider(googlePlacesAPIKey)
    : new EmptyLocationSearchProvider(),
});

const port = Number(process.env.PORT ?? "3000");
await app.listen({ port, host: process.env.HOST ?? "0.0.0.0" });
