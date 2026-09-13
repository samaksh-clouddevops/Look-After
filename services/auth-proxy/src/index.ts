import express from "express";
import { loadConfig } from "./config";
import { initFirebase } from "./auth/firebase";
import { createLicenseStore } from "./store/licenseStore";
import { requireAdmin, createRequireFirebaseAuth, type AuthedRequest } from "./middleware/auth";
import {
  createIpRateLimitMiddleware,
  createRateLimitMiddleware,
  requireActiveLicense,
} from "./middleware/rateLimit";
import { requestContextMiddleware } from "./middleware/requestContext";
import { licenseRouter } from "./routes/license";
import { aiRouter } from "./routes/ai";
import { adminRouter } from "./routes/admin";

async function main(): Promise<void> {
  const config = loadConfig();
  if (!config.allowInsecureDevAuth) {
    initFirebase(config);
  } else {
    // eslint-disable-next-line no-console
    console.warn("AUTH_DEV_ALLOW_INSECURE=true — Firebase verification disabled");
  }

  const store = createLicenseStore(config);
  await store.ensureReady();
  const requireFirebaseAuth = createRequireFirebaseAuth(config);

  const app = express();
  app.disable("x-powered-by");
  app.set("trust proxy", 1);
  app.use(express.json({ limit: "1mb" }));
  // Phase 6.1 — request id + structured access logs (+ optional App Check enforce).
  app.use(requestContextMiddleware);

  const adminIpLimit = createIpRateLimitMiddleware(config, "admin");
  const licenseIpLimit = createIpRateLimitMiddleware(config, "license");
  const aiIpLimit = createIpRateLimitMiddleware(config, "ai");
  const rateLimit = createRateLimitMiddleware(config, store);

  app.get("/health", (_req, res) => {
    res.json({
      ok: true,
      service: "lookafter-auth-proxy",
      appCheckEnforce: process.env.APP_CHECK_ENFORCE === "true",
    });
  });

  app.get("/metrics/summary", requireAdmin(config.adminApiKey), async (_req, res) => {
    // Lightweight ops snapshot — expand with OTel later (Phase 6.3).
    res.json({
      ok: true,
      uptimeSec: Math.floor(process.uptime()),
      node: process.version,
    });
  });

  app.use(
    "/v1/admin",
    adminIpLimit,
    requireAdmin(config.adminApiKey),
    adminRouter(store)
  );

  app.use(
    "/v1/license",
    licenseIpLimit,
    requireFirebaseAuth,
    licenseRouter(store)
  );

  app.use(
    "/v1/ai",
    aiIpLimit,
    requireFirebaseAuth,
    (req, res, next) => {
      void requireActiveLicense(store, req as AuthedRequest, res, next);
    },
    (req, res, next) => {
      void rateLimit(req as AuthedRequest, res, next);
    },
    aiRouter(config, store)
  );

  app.use((_req, res) => {
    res.status(404).json({ error: "Not found" });
  });

  app.listen(config.port, () => {
    // eslint-disable-next-line no-console
    console.log(`lookafter-auth-proxy listening on :${config.port}`);
  });
}

main().catch((err) => {
  // eslint-disable-next-line no-console
  console.error("Fatal startup error", err);
  process.exit(1);
});
