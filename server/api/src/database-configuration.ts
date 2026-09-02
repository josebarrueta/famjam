import { readFile } from "node:fs/promises";
import type { PoolConfig } from "pg";

type SecretFileReader = (path: string) => Promise<string>;

export async function databasePoolConfiguration(
  environment: NodeJS.ProcessEnv = process.env,
  readSecretFile: SecretFileReader = (path) => readFile(path, "utf8"),
): Promise<PoolConfig> {
  const passwordFile = environment.POSTGRES_PASSWORD_FILE;
  if (!passwordFile) {
    const connectionString = environment.DATABASE_URL;
    if (!connectionString) {
      throw new Error("POSTGRES_PASSWORD_FILE or DATABASE_URL is required");
    }
    return { connectionString, max: 20 };
  }

  const host = required(environment, "PGHOST");
  const rawPort = required(environment, "PGPORT");
  const database = required(environment, "PGDATABASE");
  const user = required(environment, "PGUSER");
  const port = Number(rawPort);
  if (!Number.isInteger(port) || port < 1 || port > 65_535) {
    throw new Error("PGPORT must be an integer between 1 and 65535");
  }
  const password = await readSecretFile(passwordFile);
  if (!password) throw new Error("POSTGRES_PASSWORD_FILE is empty");

  return { host, port, database, user, password, max: 20 };
}

function required(environment: NodeJS.ProcessEnv, name: string): string {
  const value = environment[name];
  if (!value) throw new Error(`${name} is required`);
  return value;
}
