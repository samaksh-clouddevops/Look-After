import { createHash, randomUUID } from "crypto";
import { promises as fs } from "fs";
import path from "path";
import { TableClient } from "@azure/data-tables";
import type { AppConfig } from "../config";

export type LicenseRecord = {
  keyHash: string;
  createdAt: string;
  redeemedAt?: string;
  boundUid?: string;
  revoked?: boolean;
};

export type UsageDay = {
  uid: string;
  day: string; // YYYY-MM-DD UTC
  tokens: number;
  requests: number;
};

export interface LicenseStore {
  ensureReady(): Promise<void>;
  mintKeys(count: number): Promise<string[]>;
  redeem(productKey: string, uid: string): Promise<{ active: boolean; alreadyOwned: boolean }>;
  statusForUid(uid: string): Promise<{ active: boolean; redeemedAt?: string }>;
  addUsage(uid: string, tokens: number): Promise<{ tokens: number; requests: number }>;
  usageForUid(uid: string): Promise<{ tokens: number; requests: number }>;
}

export function hashProductKey(productKey: string): string {
  const normalized = productKey.trim().toLowerCase();
  return createHash("sha256").update(normalized).digest("hex");
}

function utcDay(d = new Date()): string {
  return d.toISOString().slice(0, 10);
}

function isUuidLike(value: string): boolean {
  return /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(
    value.trim()
  );
}

/** Parses PRODUCT_KEYS_JSON — array of UUIDs or `{ "keys": [...] }`. */
export function parseProductKeysJson(raw: string): string[] {
  const trimmed = raw.trim();
  if (!trimmed) return [];

  let parsed: unknown;
  try {
    parsed = JSON.parse(trimmed);
  } catch {
    throw new Error("PRODUCT_KEYS_JSON must be valid JSON");
  }

  const keys = Array.isArray(parsed)
    ? parsed
    : typeof parsed === "object" && parsed !== null && Array.isArray((parsed as { keys?: unknown }).keys)
      ? (parsed as { keys: unknown[] }).keys
      : null;

  if (!keys) {
    throw new Error('PRODUCT_KEYS_JSON must be ["uuid", ...] or { "keys": ["uuid", ...] }');
  }

  const normalized = keys.map((entry) => {
    if (typeof entry !== "string") {
      throw new Error("Each product key must be a UUID string");
    }
    const key = entry.trim();
    if (!isUuidLike(key)) {
      throw new Error(`Invalid product key UUID: ${key}`);
    }
    return key;
  });

  return [...new Set(normalized)];
}

function seedLicenseRecords(keys: string[], target: Map<string, LicenseRecord>): number {
  const now = new Date().toISOString();
  let added = 0;
  for (const key of keys) {
    const keyHash = hashProductKey(key);
    if (target.has(keyHash)) continue;
    target.set(keyHash, { keyHash, createdAt: now });
    added += 1;
  }
  return added;
}

/** File-backed store for local/dev and single-replica demos. */
export class FileLicenseStore implements LicenseStore {
  private licenses = new Map<string, LicenseRecord>();
  private usage = new Map<string, UsageDay>();
  private readonly filePath: string;
  private readonly seedKeys: string[];

  constructor(dataDir: string, seedKeys: string[] = []) {
    this.filePath = path.join(dataDir, "licenses.json");
    this.seedKeys = seedKeys;
  }

  async ensureReady(): Promise<void> {
    await fs.mkdir(path.dirname(this.filePath), { recursive: true });
    try {
      const raw = await fs.readFile(this.filePath, "utf8");
      const parsed = JSON.parse(raw) as {
        licenses?: LicenseRecord[];
        usage?: UsageDay[];
      };
      for (const lic of parsed.licenses ?? []) {
        this.licenses.set(lic.keyHash, lic);
      }
      for (const u of parsed.usage ?? []) {
        this.usage.set(`${u.uid}:${u.day}`, u);
      }
    } catch {
      // First boot — file may not exist yet.
    }

    if (this.seedKeys.length > 0) {
      const added = seedLicenseRecords(this.seedKeys, this.licenses);
      if (added > 0) {
        await this.persist();
      }
    } else if (this.licenses.size === 0 && this.usage.size === 0) {
      await this.persist();
    }
  }

  private async persist(): Promise<void> {
    const payload = {
      licenses: [...this.licenses.values()],
      usage: [...this.usage.values()],
    };
    await fs.writeFile(this.filePath, JSON.stringify(payload, null, 2), "utf8");
  }

  async mintKeys(count: number): Promise<string[]> {
    const keys: string[] = [];
    const now = new Date().toISOString();
    for (let i = 0; i < count; i++) {
      const key = randomUUID();
      const keyHash = hashProductKey(key);
      this.licenses.set(keyHash, { keyHash, createdAt: now });
      keys.push(key);
    }
    await this.persist();
    return keys;
  }

  async redeem(productKey: string, uid: string): Promise<{ active: boolean; alreadyOwned: boolean }> {
    if (!isUuidLike(productKey)) {
      throw Object.assign(new Error("Invalid product key format"), { status: 400 });
    }
    const keyHash = hashProductKey(productKey);
    const existing = this.licenses.get(keyHash);
    if (!existing || existing.revoked) {
      throw Object.assign(new Error("Unknown or revoked product key"), { status: 404 });
    }
    if (existing.boundUid && existing.boundUid !== uid) {
      throw Object.assign(new Error("Product key already redeemed by another account"), {
        status: 409,
      });
    }
    if (existing.boundUid === uid) {
      return { active: true, alreadyOwned: true };
    }
    existing.boundUid = uid;
    existing.redeemedAt = new Date().toISOString();
    this.licenses.set(keyHash, existing);
    await this.persist();
    return { active: true, alreadyOwned: false };
  }

  async statusForUid(uid: string): Promise<{ active: boolean; redeemedAt?: string }> {
    for (const lic of this.licenses.values()) {
      if (lic.boundUid === uid && !lic.revoked) {
        return { active: true, redeemedAt: lic.redeemedAt };
      }
    }
    return { active: false };
  }

  async addUsage(uid: string, tokens: number): Promise<{ tokens: number; requests: number }> {
    const day = utcDay();
    const id = `${uid}:${day}`;
    const current = this.usage.get(id) ?? { uid, day, tokens: 0, requests: 0 };
    current.tokens += Math.max(0, tokens);
    current.requests += 1;
    this.usage.set(id, current);
    await this.persist();
    return { tokens: current.tokens, requests: current.requests };
  }

  async usageForUid(uid: string): Promise<{ tokens: number; requests: number }> {
    const day = utcDay();
    const current = this.usage.get(`${uid}:${day}`);
    return { tokens: current?.tokens ?? 0, requests: current?.requests ?? 0 };
  }
}

/** Azure Table Storage-backed store for production. */
export class AzureTableLicenseStore implements LicenseStore {
  private client: TableClient;

  constructor(connectionString: string, tableName: string) {
    this.client = TableClient.fromConnectionString(connectionString, tableName);
  }

  async ensureReady(): Promise<void> {
    try {
      await this.client.createTable();
    } catch (err: unknown) {
      const code = (err as { statusCode?: number }).statusCode;
      if (code !== 409) throw err;
    }
  }

  async mintKeys(count: number): Promise<string[]> {
    const keys: string[] = [];
    const now = new Date().toISOString();
    for (let i = 0; i < count; i++) {
      const key = randomUUID();
      const keyHash = hashProductKey(key);
      await this.client.createEntity({
        partitionKey: "license",
        rowKey: keyHash,
        createdAt: now,
        revoked: false,
      });
      keys.push(key);
    }
    return keys;
  }

  async redeem(productKey: string, uid: string): Promise<{ active: boolean; alreadyOwned: boolean }> {
    if (!isUuidLike(productKey)) {
      throw Object.assign(new Error("Invalid product key format"), { status: 400 });
    }
    const keyHash = hashProductKey(productKey);
    let entity: Record<string, unknown>;
    try {
      entity = (await this.client.getEntity("license", keyHash)) as Record<string, unknown>;
    } catch {
      throw Object.assign(new Error("Unknown or revoked product key"), { status: 404 });
    }
    if (entity.revoked === true) {
      throw Object.assign(new Error("Unknown or revoked product key"), { status: 404 });
    }
    const boundUid = entity.boundUid as string | undefined;
    if (boundUid && boundUid !== uid) {
      throw Object.assign(new Error("Product key already redeemed by another account"), {
        status: 409,
      });
    }
    if (boundUid === uid) {
      return { active: true, alreadyOwned: true };
    }
    const redeemedAt = new Date().toISOString();
    await this.client.updateEntity(
      {
        partitionKey: "license",
        rowKey: keyHash,
        boundUid: uid,
        redeemedAt,
        createdAt: entity.createdAt as string,
        revoked: false,
      },
      "Replace"
    );
    // Also index by uid for fast status lookup
    await this.client.upsertEntity(
      {
        partitionKey: "uid",
        rowKey: uid,
        keyHash,
        redeemedAt,
        revoked: false,
      },
      "Replace"
    );
    return { active: true, alreadyOwned: false };
  }

  async statusForUid(uid: string): Promise<{ active: boolean; redeemedAt?: string }> {
    try {
      const entity = (await this.client.getEntity("uid", uid)) as Record<string, unknown>;
      if (entity.revoked === true) return { active: false };
      return { active: true, redeemedAt: entity.redeemedAt as string | undefined };
    } catch {
      return { active: false };
    }
  }

  async addUsage(uid: string, tokens: number): Promise<{ tokens: number; requests: number }> {
    const day = utcDay();
    const rowKey = `${uid}:${day}`;
    let tokensTotal = Math.max(0, tokens);
    let requests = 1;
    try {
      const existing = (await this.client.getEntity("usage", rowKey)) as Record<string, unknown>;
      tokensTotal += Number(existing.tokens ?? 0);
      requests += Number(existing.requests ?? 0);
    } catch {
      // new day
    }
    await this.client.upsertEntity(
      {
        partitionKey: "usage",
        rowKey,
        uid,
        day,
        tokens: tokensTotal,
        requests,
      },
      "Replace"
    );
    return { tokens: tokensTotal, requests };
  }

  async usageForUid(uid: string): Promise<{ tokens: number; requests: number }> {
    const day = utcDay();
    try {
      const existing = (await this.client.getEntity("usage", `${uid}:${day}`)) as Record<
        string,
        unknown
      >;
      return {
        tokens: Number(existing.tokens ?? 0),
        requests: Number(existing.requests ?? 0),
      };
    } catch {
      return { tokens: 0, requests: 0 };
    }
  }
}

export function createLicenseStore(config: AppConfig): LicenseStore {
  if (config.azureStorageConnectionString) {
    return new AzureTableLicenseStore(config.azureStorageConnectionString, config.azureTableName);
  }

  const seedKeys = config.productKeysJson ? parseProductKeysJson(config.productKeysJson) : [];
  return new FileLicenseStore(config.dataDir, seedKeys);
}
