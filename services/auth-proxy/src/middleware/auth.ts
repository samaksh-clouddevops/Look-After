import type { Request, Response, NextFunction } from "express";
import { verifyFirebaseIdToken, type VerifiedUser } from "../auth/firebase";
import type { AppConfig } from "../config";

export type AuthedRequest = Request & { user?: VerifiedUser };

function readBearerToken(req: Request): string | null {
  const header = req.header("authorization") || req.header("Authorization");
  if (!header?.startsWith("Bearer ")) {
    return null;
  }
  const token = header.slice("Bearer ".length).trim();
  return token || null;
}

function createProductionFirebaseAuth(config: AppConfig) {
  return async (req: AuthedRequest, res: Response, next: NextFunction): Promise<void> => {
    try {
      const token = readBearerToken(req);
      if (!token) {
        res.status(401).json({ error: "Missing Bearer token" });
        return;
      }
      req.user = await verifyFirebaseIdToken(token);
      next();
    } catch {
      res.status(401).json({ error: "Invalid or expired token" });
    }
  };
}

/** Dev-only middleware: accepts `dev:<uid>` tokens. Never register in production. */
function createInsecureDevFirebaseAuth() {
  return async (req: AuthedRequest, res: Response, next: NextFunction): Promise<void> => {
    const token = readBearerToken(req);
    if (!token) {
      res.status(401).json({ error: "Missing Bearer token" });
      return;
    }
    if (!token.startsWith("dev:")) {
      res.status(401).json({ error: "Invalid or expired token" });
      return;
    }
    const uid = token.slice("dev:".length).trim();
    if (!uid) {
      res.status(401).json({ error: "Invalid or expired token" });
      return;
    }
    req.user = { uid, email: `${uid}@dev.local` };
    next();
  };
}

export function createRequireFirebaseAuth(config: AppConfig) {
  if (config.allowInsecureDevAuth) {
    return createInsecureDevFirebaseAuth();
  }
  return createProductionFirebaseAuth(config);
}

export function requireAdmin(adminApiKey: string) {
  return (req: Request, res: Response, next: NextFunction): void => {
    const header = req.header("x-admin-key") || "";
    if (!header || header !== adminApiKey) {
      res.status(401).json({ error: "Unauthorized" });
      return;
    }
    next();
  };
}
