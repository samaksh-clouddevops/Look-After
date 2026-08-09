import { Router } from "express";
import type { LicenseStore } from "../store/licenseStore";
import type { AuthedRequest } from "../middleware/auth";

export function licenseRouter(store: LicenseStore): Router {
  const router = Router();

  router.post("/redeem", async (req: AuthedRequest, res) => {
    try {
      const uid = req.user?.uid;
      if (!uid) {
        res.status(401).json({ error: "Unauthorized" });
        return;
      }
      const productKey = String(req.body?.productKey ?? "").trim();
      if (!productKey) {
        res.status(400).json({ error: "productKey is required" });
        return;
      }
      const result = await store.redeem(productKey, uid);
      res.json({
        active: result.active,
        alreadyOwned: result.alreadyOwned,
      });
    } catch (err: unknown) {
      const status = (err as { status?: number }).status ?? 500;
      const message = err instanceof Error ? err.message : "Redeem failed";
      res.status(status).json({ error: message });
    }
  });

  router.get("/status", async (req: AuthedRequest, res) => {
    try {
      const uid = req.user?.uid;
      if (!uid) {
        res.status(401).json({ error: "Unauthorized" });
        return;
      }
      const status = await store.statusForUid(uid);
      res.json(status);
    } catch {
      res.status(500).json({ error: "Status check failed" });
    }
  });

  return router;
}
