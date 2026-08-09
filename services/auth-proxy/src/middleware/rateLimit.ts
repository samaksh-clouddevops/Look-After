import type { Request, Response, NextFunction } from "express";
import type { AuthedRequest } from "./auth";
import type { LicenseStore } from "../store/licenseStore";
import type { AppConfig } from "../config";

type WindowState = { count: number; resetAt: number };

const windows = new Map<string, WindowState>();
const ipWindows = new Map<string, WindowState>();

function clientIp(req: Request): string {
  return req.ip || req.socket.remoteAddress || "unknown";
}

function checkWindow(
  store: Map<string, WindowState>,
  key: string,
  limit: number,
  windowMs = 60_000
): boolean {
  const now = Date.now();
  const state = store.get(key);
  if (!state || now >= state.resetAt) {
    store.set(key, { count: 1, resetAt: now + windowMs });
    return true;
  }
  state.count += 1;
  return state.count <= limit;
}

/** Rate limit by client IP — apply before auth to slow brute-force attempts. */
export function createIpRateLimitMiddleware(config: AppConfig, scope: string) {
  return (req: Request, res: Response, next: NextFunction): void => {
    const key = `${scope}:${clientIp(req)}`;
    if (!checkWindow(ipWindows, key, config.authRateLimitPerMinute)) {
      res.status(429).json({ error: "Rate limit exceeded" });
      return;
    }
    next();
  };
}

export function createRateLimitMiddleware(config: AppConfig, store: LicenseStore) {
  return async (req: AuthedRequest, res: Response, next: NextFunction): Promise<void> => {
    const uid = req.user?.uid;
    if (!uid) {
      res.status(401).json({ error: "Unauthorized" });
      return;
    }

    const key = `uid:${uid}`;
    if (!checkWindow(windows, key, config.rateLimitPerMinute)) {
      res.status(429).json({ error: "Rate limit exceeded" });
      return;
    }

    const usage = await store.usageForUid(uid);
    if (usage.tokens >= config.dailyTokenBudget) {
      res.status(429).json({ error: "Daily token budget exceeded" });
      return;
    }

    next();
  };
}

export async function requireActiveLicense(
  store: LicenseStore,
  req: AuthedRequest,
  res: Response,
  next: NextFunction
): Promise<void> {
  const uid = req.user?.uid;
  if (!uid) {
    res.status(401).json({ error: "Unauthorized" });
    return;
  }
  const status = await store.statusForUid(uid);
  if (!status.active) {
    res.status(403).json({ error: "License required" });
    return;
  }
  next();
}
