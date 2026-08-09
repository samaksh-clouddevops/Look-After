export type AppConfig = {
  port: number;
  firebaseProjectId: string;
  firebaseServiceAccountJson?: string;
  /** Injected from Container App secret → env GLM_API_KEY (never shipped to clients). */
  glmApiKey?: string;
  /** Injected from Container App secret → env OPENAI_API_KEY for cloud voice/TTS proxy. */
  openaiApiKey?: string;
  glmBaseUrl: string;
  adminApiKey: string;
  dataDir: string;
  azureStorageConnectionString?: string;
  azureTableName: string;
  rateLimitPerMinute: number;
  dailyTokenBudget: number;
  /** Local-only: accept Bearer tokens of form `dev:<uid>`. Never enable in production. */
  allowInsecureDevAuth: boolean;
  /** Optional JSON allowlist of product key UUIDs — Container App secret in production. */
  productKeysJson?: string;
};

function required(name: string, value: string | undefined): string {
  if (!value || !value.trim()) {
    throw new Error(`Missing required env var: ${name}`);
  }
  return value.trim();
}

export function loadConfig(): AppConfig {
  const firebaseProjectId =
    process.env.FIREBASE_PROJECT_ID?.trim() ||
    process.env.GCLOUD_PROJECT?.trim() ||
    "";

  return {
    port: Number(process.env.PORT || 8080),
    firebaseProjectId: required("FIREBASE_PROJECT_ID", firebaseProjectId),
    firebaseServiceAccountJson: process.env.FIREBASE_SERVICE_ACCOUNT_JSON?.trim() || undefined,
    glmApiKey: process.env.GLM_API_KEY?.trim() || undefined,
    openaiApiKey: process.env.OPENAI_API_KEY?.trim() || undefined,
    glmBaseUrl: (process.env.GLM_BASE_URL || "https://api.z.ai/api/paas/v4").replace(/\/$/, ""),
    adminApiKey: required("ADMIN_API_KEY", process.env.ADMIN_API_KEY),
    dataDir: process.env.DATA_DIR?.trim() || "./data",
    azureStorageConnectionString: process.env.AZURE_STORAGE_CONNECTION_STRING?.trim() || undefined,
    azureTableName: process.env.AZURE_TABLE_NAME?.trim() || "lookafterlicenses",
    rateLimitPerMinute: Number(process.env.RATE_LIMIT_PER_MINUTE || 30),
    dailyTokenBudget: Number(process.env.DAILY_TOKEN_BUDGET || 200_000),
    allowInsecureDevAuth: process.env.AUTH_DEV_ALLOW_INSECURE === "true",
    productKeysJson: process.env.PRODUCT_KEYS_JSON?.trim() || undefined,
  };
}
