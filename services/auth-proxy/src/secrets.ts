import type { AppConfig } from "./config";

/**
 * Resolve the GLM/z.ai API key from the process environment.
 * In Azure, set Container App secret `glm-api-key` and map it to env `GLM_API_KEY`.
 */
export function resolveGlmApiKey(config: AppConfig): string {
  const key = config.glmApiKey?.trim();
  if (!key) {
    throw new Error("No GLM API key configured (set GLM_API_KEY from a Container App secret)");
  }
  return key;
}

/**
 * Resolve OpenAI API key for cloud voice/TTS.
 * In Azure, set Container App secret `openai-api-key` → env `OPENAI_API_KEY`.
 */
export function resolveOpenAiApiKey(config: AppConfig): string {
  const key = config.openaiApiKey?.trim();
  if (!key) {
    throw new Error("No OpenAI API key configured (set OPENAI_API_KEY from a Container App secret)");
  }
  return key;
}
