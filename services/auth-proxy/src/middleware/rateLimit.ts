import type { Response, NextFunction } from "express";
import type { AuthedRequest } from "./auth";
import type { LicenseStore } from "../store/licenseStore";
import type { AppConfig } from "../config";

type WindowState = { count: number; resetAt: number };

const windows = new Map<string, WindowState>();

export function createRateLimitMiddleware(config: AppConfig, store: LicenseStore) {
  return async (req: AuthedRequest, res: Response, next: NextFunction): Promise<void> => {
    const uid = req.user?.uid;
    if (!uid) {
      res.status(401).json({ error: "Unauthorized" });
      return;
    }

    const now = Date.now();
    const windowMs = 60_000;
    const state = windows.get(uid);
    if (!state || now >= state.resetAt) {
      windows.set(uid, { count: 1, resetAt: now + windowMs });
    } else {
      state.count += 1;
      if (state.count > config.rateLimitPerMinute) {
        res.status(429).json({ error: "Rate limit exceeded" });
        return;
      }
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
