import express from "express";
import { loadConfig } from "./config";
import { initFirebase } from "./auth/firebase";
import { createLicenseStore } from "./store/licenseStore";
import { requireAdmin, createRequireFirebaseAuth, type AuthedRequest } from "./middleware/auth";
import {
  createRateLimitMiddleware,
  requireActiveLicense,
} from "./middleware/rateLimit";
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
  app.use(express.json({ limit: "1mb" }));

  app.get("/health", (_req, res) => {
    res.json({ ok: true, service: "lookafter-auth-proxy" });
  });

  app.use("/v1/admin", requireAdmin(config.adminApiKey), adminRouter(store));

  app.use("/v1/license", requireFirebaseAuth, licenseRouter(store));

  const rateLimit = createRateLimitMiddleware(config, store);
  app.use(
    "/v1/ai",
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
