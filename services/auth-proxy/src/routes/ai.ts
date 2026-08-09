import { Router } from "express";
import type { AppConfig } from "../config";
import type { LicenseStore } from "../store/licenseStore";
import type { AuthedRequest } from "../middleware/auth";
import { resolveGlmApiKey, resolveOpenAiApiKey } from "../secrets";
import { callGlmChat, type ChatMessage } from "../glm/client";
import { callOpenAiSpeech } from "../openai/tts";

function asMessages(raw: unknown): ChatMessage[] {
  if (!Array.isArray(raw)) return [];
  return raw
    .map((item) => {
      if (!item || typeof item !== "object") return null;
      const role = String((item as { role?: string }).role ?? "user");
      const content = String((item as { content?: string }).content ?? "");
      if (!content) return null;
      return { role, content };
    })
    .filter((m): m is ChatMessage => m !== null);
}

export function aiRouter(config: AppConfig, store: LicenseStore): Router {
  const router = Router();

  async function handleCompletion(
    req: AuthedRequest,
    res: import("express").Response,
    defaults: { temperature: number; maxTokens: number }
  ): Promise<void> {
    const uid = req.user?.uid;
    if (!uid) {
      res.status(401).json({ error: "Unauthorized" });
      return;
    }

    const model = String(req.body?.model ?? "glm-4.7-flash");
    const temperature =
      typeof req.body?.temperature === "number" ? req.body.temperature : defaults.temperature;
    const maxTokens =
      typeof req.body?.max_tokens === "number" ? req.body.max_tokens : defaults.maxTokens;

    let messages = asMessages(req.body?.messages);
    if (messages.length === 0 && typeof req.body?.prompt === "string") {
      const systemPrompt =
        typeof req.body?.systemPrompt === "string" ? req.body.systemPrompt : undefined;
      messages = [];
      if (systemPrompt) messages.push({ role: "system", content: systemPrompt });
      messages.push({ role: "user", content: req.body.prompt });
    }
    if (messages.length === 0 && typeof req.body?.message === "string") {
      const systemPrompt =
        typeof req.body?.systemPrompt === "string" ? req.body.systemPrompt : undefined;
      messages = [];
      if (systemPrompt) messages.push({ role: "system", content: systemPrompt });
      if (Array.isArray(req.body?.history)) {
        messages.push(...asMessages(req.body.history));
      }
      messages.push({ role: "user", content: req.body.message });
    }

    if (messages.length === 0) {
      res.status(400).json({ error: "messages, message, or prompt is required" });
      return;
    }

    try {
      const apiKey = resolveGlmApiKey(config);
      const result = await callGlmChat(config.glmBaseUrl, apiKey, {
        model,
        messages,
        temperature,
        max_tokens: maxTokens,
      });
      const used = result.promptTokens + result.completionTokens;
      await store.addUsage(uid, used);
      res.json({
        content: result.content,
        model: result.model,
        usage: {
          prompt_tokens: result.promptTokens,
          completion_tokens: result.completionTokens,
          total_tokens: used,
        },
      });
    } catch (err: unknown) {
      const status = (err as { status?: number }).status ?? 502;
      const message = err instanceof Error ? err.message : "AI proxy failed";
      // Never echo secrets; upstream snippet is truncated in glm client.
      res.status(status).json({ error: message });
    }
  }

  router.post("/chat", (req, res) => {
    void handleCompletion(req, res, { temperature: 0.7, maxTokens: 4096 });
  });

  router.post("/complete", (req, res) => {
    void handleCompletion(req, res, { temperature: 0.3, maxTokens: 8192 });
  });

  router.post("/speech", (req, res) => {
    void (async () => {
      const uid = (req as AuthedRequest).user?.uid;
      if (!uid) {
        res.status(401).json({ error: "Unauthorized" });
        return;
      }

      const input =
        typeof req.body?.input === "string"
          ? req.body.input
          : typeof req.body?.text === "string"
            ? req.body.text
            : "";
      const voice = typeof req.body?.voice === "string" ? req.body.voice : undefined;
      const model = typeof req.body?.model === "string" ? req.body.model : undefined;
      const speed = typeof req.body?.speed === "number" ? req.body.speed : undefined;

      try {
        const apiKey = resolveOpenAiApiKey(config);
        const result = await callOpenAiSpeech(apiKey, { input, voice, model, speed });
        await store.addUsage(uid, result.estimatedTokens);
        res.setHeader("Content-Type", "audio/mpeg");
        res.send(result.audio);
      } catch (err: unknown) {
        const status = (err as { status?: number }).status ?? 502;
        const message = err instanceof Error ? err.message : "OpenAI speech proxy failed";
        res.status(status).json({ error: message });
      }
    })();
  });

  return router;
}
