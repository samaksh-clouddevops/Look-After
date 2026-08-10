import { randomUUID } from "crypto";
import type { Request, Response, NextFunction } from "express";

export type RequestWithContext = Request & {
  requestId?: string;
  startMs?: number;
};

/**
 * Phase 6.1 — assign request id, structured access log, optional App Check header presence.
 * Does not fail closed on missing App Check until APP_CHECK_ENFORCE=true.
 */
export function requestContextMiddleware(
  req: RequestWithContext,
  res: Response,
  next: NextFunction
): void {
  const incoming = req.header("x-request-id") || req.header("x-correlation-id");
  const requestId = incoming && incoming.length > 0 ? incoming : randomUUID();
  req.requestId = requestId;
  req.startMs = Date.now();
  res.setHeader("x-request-id", requestId);

  const appCheck = req.header("x-firebase-appcheck");
  if (process.env.APP_CHECK_ENFORCE === "true" && !appCheck) {
    res.status(401).json({ error: "App Check token required", requestId });
    return;
  }

  res.on("finish", () => {
    const ms = Date.now() - (req.startMs ?? Date.now());
    const uid =
      (req as RequestWithContext & { user?: { uid?: string } }).user?.uid ?? "-";
    // Structured single-line JSON for log drains / OTel collectors later.
    // eslint-disable-next-line no-console
    console.log(
      JSON.stringify({
        msg: "http_access",
        requestId,
        method: req.method,
        path: req.path,
        status: res.statusCode,
        ms,
        uid,
        hasAppCheck: Boolean(appCheck),
      })
    );
  });

  next();
}
