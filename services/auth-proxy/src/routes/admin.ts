import { Router } from "express";
import type { LicenseStore } from "../store/licenseStore";

export function adminRouter(store: LicenseStore): Router {
  const router = Router();

  router.post("/keys", async (req, res) => {
    try {
      const countRaw = Number(req.body?.count ?? 1);
      const count = Number.isFinite(countRaw) ? Math.min(Math.max(Math.floor(countRaw), 1), 100) : 1;
      const keys = await store.mintKeys(count);
      res.json({ count: keys.length, keys });
    } catch {
      res.status(500).json({ error: "Failed to mint keys" });
    }
  });

  return router;
}
