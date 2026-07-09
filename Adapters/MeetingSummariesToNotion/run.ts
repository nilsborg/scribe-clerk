/// <reference lib="deno.ns" />

import { config } from "https://deno.land/x/dotenv/mod.ts";
import { loadPrompt } from "./functions/loadPrompt.ts";
import { appendGlossaryToPrompt, loadGlossary } from "./functions/loadGlossary.ts";
import { getOpenRouterSummary } from "./functions/getOpenRouterSummary.ts";
import {
  MEETING_SUMMARY_MODELS,
  PROJECT_UPDATE_SUMMARY_MODELS,
  type SummaryModelConfig,
} from "./config/summaryModels.ts";
import { applyGermanTitleFlag } from "./functions/inferDocumentTitle.ts";
import { generateRecordingTitle } from "./functions/generateRecordingTitle.ts";
import { ADAPTER_ROOT, PROMPT_PATHS } from "./paths.ts";

type FlowKey = keyof typeof PROMPT_PATHS;
type SummaryLanguage = "english" | "german";
type RunAction = "summarize" | "title";

interface RunRequest {
  action: RunAction;
  transcriptPath: string;
  summaryPath?: string;
  recordingTitle?: string;
  flow?: FlowKey;
  language?: SummaryLanguage;
  skipCache?: boolean;
}

interface RunResponse {
  success: boolean;
  action: RunAction;
  title?: string;
  summaryPath?: string;
  error?: string;
}

interface FlowConfig {
  promptFilePath: string;
  documentTitleBuilder?: (baseName: string) => string;
  summaryModels: SummaryModelConfig[];
}

const FLOW_CONFIGS: Record<FlowKey, FlowConfig> = {
  meeting: {
    promptFilePath: PROMPT_PATHS.meeting,
    summaryModels: [...MEETING_SUMMARY_MODELS],
    documentTitleBuilder: (name) => `Meeting - ${name}`,
  },
  "project-updates": {
    promptFilePath: PROMPT_PATHS["project-updates"],
    summaryModels: [...PROJECT_UPDATE_SUMMARY_MODELS],
    documentTitleBuilder: (name) => `Project Update - ${name}`,
  },
};

const envFilePath = Deno.env.get("ADAPTER_ENV_FILE") ?? `${ADAPTER_ROOT}/.env`;
const env = config({ path: envFilePath }) as Record<string, string>;

function resolveEnv(key: string): string | undefined {
  const value = env[key] ?? Deno.env.get(key);
  if (!value) return undefined;

  const normalized = value.trim().replace(/^["']|["']$/g, "");
  if (!normalized || normalized === "xxx") {
    return undefined;
  }

  return normalized;
}

function parseFlow(value: string | undefined): FlowKey {
  const normalized = (value ?? "meeting").trim().toLowerCase();
  if (normalized === "project-updates" || normalized === "project_updates" || normalized === "project") {
    return "project-updates";
  }
  return "meeting";
}

function parseLanguage(value: string | undefined): SummaryLanguage {
  const normalized = (value ?? "english").trim().toLowerCase();
  if (normalized === "de" || normalized === "german" || normalized === "deutsch") {
    return "german";
  }
  return "english";
}

function getSummaryLanguageInstruction(language: SummaryLanguage): string {
  if (language === "german") {
    return "Write the entire summary in German.";
  }
  return "Write the entire summary in English.";
}

function getSummaryCacheFlowKey(language: SummaryLanguage, flow: FlowKey): string {
  if (flow === "project-updates") {
    return language === "german" ? "project-updates-german" : "project-updates";
  }
  return language === "german" ? "meeting-german" : "meeting";
}

async function readRequest(): Promise<RunRequest> {
  const text = await new Response(Deno.stdin.readable).text();
  const parsed = JSON.parse(text) as RunRequest;

  if (!parsed.action || !parsed.transcriptPath) {
    throw new Error("Request must include action and transcriptPath.");
  }

  if (parsed.action !== "title" && !parsed.summaryPath) {
    throw new Error("Request must include summaryPath for the summarize action.");
  }

  return parsed;
}

async function generateTitle(request: RunRequest): Promise<RunResponse> {
  const openRouterKey = resolveEnv("OPENROUTER_API_KEY");

  if (!openRouterKey) {
    return { success: false, action: "title", error: "OPENROUTER_API_KEY is not configured." };
  }

  let transcript: string;
  try {
    transcript = await Deno.readTextFile(request.transcriptPath);
  } catch (error) {
    return {
      success: false,
      action: "title",
      error: `Could not read transcript: ${error}`,
    };
  }

  const fileName = request.transcriptPath.split("/").pop() || "Unknown";
  const fallback = fileName.replace(/\.[^/.]+$/, "");

  try {
    const title = await generateRecordingTitle({
      transcript,
      apiKey: openRouterKey,
      fallback,
    });

    return {
      success: true,
      action: "title",
      title,
    };
  } catch (error) {
    return {
      success: false,
      action: "title",
      error: `Title generation failed: ${error}`,
    };
  }
}

async function summarize(request: RunRequest): Promise<RunResponse> {
  const summaryPath = request.summaryPath!;
  const flow = parseFlow(request.flow);
  const language = parseLanguage(request.language);
  const flowConfig = FLOW_CONFIGS[flow];
  const openRouterKey = resolveEnv("OPENROUTER_API_KEY");

  if (!openRouterKey) {
    return { success: false, action: "summarize", error: "OPENROUTER_API_KEY is not configured." };
  }

  let transcript: string;
  try {
    transcript = await Deno.readTextFile(request.transcriptPath);
  } catch (error) {
    return {
      success: false,
      action: "summarize",
      error: `Could not read transcript: ${error}`,
    };
  }

  if (!request.skipCache) {
    try {
      const existing = await Deno.readTextFile(summaryPath);
      if (existing.trim().length > 0) {
        const title = await resolveDocumentTitle(
          request,
          request.transcriptPath,
          flowConfig,
          language,
          transcript,
        );
        return {
          success: true,
          action: "summarize",
          title,
          summaryPath,
        };
      }
    } catch {
      // generate fresh summary
    }
  }

  const glossary = await loadGlossary();
  const basePrompt = appendGlossaryToPrompt(
    await loadPrompt(flowConfig.promptFilePath),
    glossary,
  );
  const systemPrompt =
    `${basePrompt.trim()}\n\nAdditional instruction:\n${getSummaryLanguageInstruction(language)}`;

  const summaries: { label: string; content: string }[] = [];

  for (const modelConfig of flowConfig.summaryModels) {
    try {
      const content = await getOpenRouterSummary({
        systemPrompt,
        content: transcript,
        apiKey: openRouterKey,
        model: modelConfig.model,
      });
      summaries.push({ label: modelConfig.label, content });
    } catch (error) {
      return {
        success: false,
        action: "summarize",
        error: `Summarization failed (${modelConfig.label}): ${error}`,
      };
    }
  }

  const combinedSummary = summaries.length > 1
    ? summaries
      .map((summary) => `## ${summary.label}\n\n${summary.content.trim()}`)
      .join("\n\n")
    : (summaries[0]?.content.trim() ?? "");

  const summaryDir = summaryPath.split("/").slice(0, -1).join("/");
  if (summaryDir) {
    await Deno.mkdir(summaryDir, { recursive: true });
  }
  await Deno.writeTextFile(summaryPath, combinedSummary);

  const title = await resolveDocumentTitle(
    request,
    request.transcriptPath,
    flowConfig,
    language,
    transcript,
  );

  return {
    success: true,
    action: "summarize",
    title,
    summaryPath,
  };
}

function filenameFallbackTitle(
  transcriptPath: string,
  flowConfig: FlowConfig,
  language: SummaryLanguage,
): string {
  const fileName = transcriptPath.split("/").pop() || "Unknown";
  const baseName = fileName.replace(/\.[^/.]+$/, "");
  const fallbackTitle = flowConfig.documentTitleBuilder
    ? flowConfig.documentTitleBuilder(baseName)
    : `Summary - ${baseName}`;

  return language === "german" ? applyGermanTitleFlag(fallbackTitle) : fallbackTitle;
}

async function resolveDocumentTitle(
  request: RunRequest,
  transcriptPath: string,
  flowConfig: FlowConfig,
  language: SummaryLanguage,
  transcript: string,
): Promise<string> {
  const preferred = request.recordingTitle?.trim();
  if (preferred) {
    return language === "german" ? applyGermanTitleFlag(preferred) : preferred;
  }

  const fallbackTitle = filenameFallbackTitle(transcriptPath, flowConfig, language);
  const openRouterKey = resolveEnv("OPENROUTER_API_KEY");

  if (!openRouterKey || !transcript.trim()) {
    return fallbackTitle;
  }

  try {
    return await generateRecordingTitle({
      transcript,
      apiKey: openRouterKey,
      fallback: fallbackTitle,
    });
  } catch {
    return fallbackTitle;
  }
}

async function main() {
  try {
    const request = await readRequest();
    const response = request.action === "title"
      ? await generateTitle(request)
      : await summarize(request);

    await Deno.stdout.write(new TextEncoder().encode(JSON.stringify(response)));
    Deno.exit(response.success ? 0 : 1);
  } catch (error) {
    const response: RunResponse = {
      success: false,
      action: "summarize",
      error: error instanceof Error ? error.message : String(error),
    };
    await Deno.stdout.write(new TextEncoder().encode(JSON.stringify(response)));
    Deno.exit(1);
  }
}

if (import.meta.main) {
  await main();
}
