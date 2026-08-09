import type { Request, Response, NextFunction } from "express";
import { verifyFirebaseIdToken, type VerifiedUser } from "../auth/firebase";
import type { AppConfig } from "../config";

export type AuthedRequest = Request & { user?: VerifiedUser };

export function createRequireFirebaseAuth(config: AppConfig) {
  return async (req: AuthedRequest, res: Response, next: NextFunction): Promise<void> => {
    try {
      const header = req.header("authorization") || req.header("Authorization");
      if (!header?.startsWith("Bearer ")) {
        res.status(401).json({ error: "Missing Bearer token" });
        return;
      }
      const token = header.slice("Bearer ".length).trim();
      if (!token) {
        res.status(401).json({ error: "Missing Bearer token" });
        return;
      }
      if (config.allowInsecureDevAuth && token.startsWith("dev:")) {
        const uid = token.slice("dev:".length).trim();
        if (!uid) {
          res.status(401).json({ error: "Invalid or expired token" });
          return;
        }
        req.user = { uid, email: `${uid}@dev.local` };
        next();
        return;
      }
      req.user = await verifyFirebaseIdToken(token);
      next();
    } catch {
      res.status(401).json({ error: "Invalid or expired token" });
    }
  };
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
