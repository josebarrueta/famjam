import { createClient } from "redis";
import type { Cache } from "./cache.js";

interface RedisCommands {
  get(key: string): Promise<string | null>;
  setEx(key: string, seconds: number, value: string): Promise<unknown>;
  del(key: string): Promise<unknown>;
  quit(): Promise<unknown>;
}

export class RedisCache implements Cache {
  private constructor(private readonly client: RedisCommands) {}

  static async connect(url: string): Promise<RedisCache> {
    const client = createClient({ url });
    client.on("error", () => {
      // Command callers fall back to source providers while Redis reconnects.
    });
    await client.connect();
    return new RedisCache(client);
  }

  async get<T>(key: string): Promise<T | null> {
    const value = await this.client.get(key);
    return value === null ? null : JSON.parse(value) as T;
  }

  async set<T>(key: string, value: T, ttlSeconds: number): Promise<void> {
    await this.client.setEx(key, ttlSeconds, JSON.stringify(value));
  }

  async delete(key: string): Promise<void> {
    await this.client.del(key);
  }

  async close(): Promise<void> {
    await this.client.quit();
  }
}
