import assert from "node:assert/strict";
import test from "node:test";
import { resolveAllowInsecureDevAuth } from "../src/config";
import { createRequireFirebaseAuth, type AuthedRequest } from "../src/middleware/auth";
import type { AppConfig } from "../src/config";
import type { Response, NextFunction } from "express";

test("resolveAllowInsecureDevAuth is false by default", () => {
  assert.equal(resolveAllowInsecureDevAuth({}), false);
});

test("resolveAllowInsecureDevAuth allows local insecure flag", () => {
  assert.equal(
    resolveAllowInsecureDevAuth({ AUTH_DEV_ALLOW_INSECURE: "true", NODE_ENV: "development" }),
    true
  );
});

test("resolveAllowInsecureDevAuth fails closed in production", () => {
  assert.throws(
    () =>
      resolveAllowInsecureDevAuth({
        AUTH_DEV_ALLOW_INSECURE: "true",
        NODE_ENV: "production",
      }),
    /forbidden/
  );
});

test("production auth middleware rejects missing bearer", async () => {
  const config = { allowInsecureDevAuth: false } as AppConfig;
  const middleware = createRequireFirebaseAuth(config);
  let statusCode = 0;
  let body: unknown;
  const req = { header: () => undefined } as unknown as AuthedRequest;
  const res = {
    status(code: number) {
      statusCode = code;
      return this;
    },
    json(payload: unknown) {
      body = payload;
      return this;
    },
  } as unknown as Response;
  let nextCalled = false;
  const next: NextFunction = () => {
    nextCalled = true;
  };
  await middleware(req, res, next);
  assert.equal(statusCode, 401);
  assert.deepEqual(body, { error: "Missing Bearer token" });
  assert.equal(nextCalled, false);
});

test("dev auth middleware accepts dev uid token", async () => {
  const config = { allowInsecureDevAuth: true } as AppConfig;
  const middleware = createRequireFirebaseAuth(config);
  let nextCalled = false;
  const req = {
    header(name: string) {
      return name.toLowerCase() === "authorization" ? "Bearer dev:reviewer" : undefined;
    },
  } as unknown as AuthedRequest;
  const res = {} as Response;
  await middleware(req, res, () => {
    nextCalled = true;
  });
  assert.equal(nextCalled, true);
  assert.equal(req.user?.uid, "reviewer");
});
