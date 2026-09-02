import { readFileSync } from "node:fs";

export type SecretFileReader = (path: string) => string;

export function configuredSecret(
  name: string,
  environment: NodeJS.ProcessEnv = process.env,
  readSecretFile: SecretFileReader = (path) => readFileSync(path, "utf8"),
): string | undefined {
  const file = environment[`${name}_FILE`];
  if (file) {
    const value = readSecretFile(file);
    if (!value) throw new Error(`${name}_FILE is empty`);
    return value;
  }
  return environment[name];
}
