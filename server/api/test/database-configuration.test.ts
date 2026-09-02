import { describe, expect, it } from "vitest";
import { databasePoolConfiguration } from "../src/database-configuration.js";

describe("databasePoolConfiguration", () => {
  it("loads production connection fields and the mounted password into memory", async () => {
    const reads: string[] = [];
    const configuration = await databasePoolConfiguration({
      PGHOST: "rallyroo-postgres",
      PGPORT: "5432",
      PGDATABASE: "rallyroo",
      PGUSER: "rallyroo",
      POSTGRES_PASSWORD_FILE: "/run/secrets/postgres/password",
      DATABASE_URL: "postgres://legacy-value-must-not-win",
    }, async (path) => {
      reads.push(path);
      return "production-password";
    });

    expect(configuration).toEqual({
      host: "rallyroo-postgres",
      port: 5432,
      database: "rallyroo",
      user: "rallyroo",
      password: "production-password",
      max: 20,
    });
    expect(reads).toEqual(["/run/secrets/postgres/password"]);
  });

  it("keeps DATABASE_URL compatibility for local development", async () => {
    const configuration = await databasePoolConfiguration({
      DATABASE_URL: "postgres://rallyroo:local@localhost:5432/rallyroo",
    });

    expect(configuration).toEqual({
      connectionString: "postgres://rallyroo:local@localhost:5432/rallyroo",
      max: 20,
    });
  });

  it("rejects incomplete structured production configuration", async () => {
    await expect(databasePoolConfiguration({
      PGHOST: "rallyroo-postgres",
      POSTGRES_PASSWORD_FILE: "/run/secrets/postgres/password",
    }, async () => "password")).rejects.toThrow("PGPORT is required");
  });
});
