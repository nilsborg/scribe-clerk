/// <reference lib="deno.ns" />

import { config } from "https://deno.land/x/dotenv/mod.ts";
import { loadPrompt } from "./functions/loadPrompt.ts";
import { appendGlossaryToPrompt, loadGlossary } from "./functions/loadGlossary.ts";
import { createNotionDocument } from "./functions/createNotionDocument.ts";
import { getOpenRouterSummary } from "./functions/getOpenRouterSummary.ts";
import {
  MEETING_SUMMARY_MODELS,
  PROJECT_UPDATE_SUMMARY_MODELS,
  type SummaryModelConfig,
} from "./config/summaryModels.ts";
import {
  applyGermanTitleFlag,
  inferDocumentTitle,
} from "./functions/inferDocumentTitle.ts";
import { ADAPTER_ROOT, PROMPT_PATHS } from "./paths.ts";

type FlowKey = keyof typeof PROMPT_PATHS;
type SummaryLanguage = "english" | "german";
type RunAction = "summarize" | "publish";

interface RunRequest {
  action: RunAction;
  transcriptPath: string;
  summaryPath: string;
  flow?: FlowKey;
  language?: SummaryLanguage;
  skipCache?: boolean;
}

interface RunResponse {
  success: boolean;
  action: RunAction;
  title?: string;
  summaryPath?: string;
  documentUrl?: string;
  error?: string;
}

interface FlowConfig {
  promptFilePath: string;
  notionDatabaseEnvKey: string;
  includeAttendees?: boolean;
  documentTitleBuilder?: (baseName: string) => string;
  inferTitleFromContent?: boolean;
  summaryModels: SummaryModelConfig[];
  titlePropertyName: string;
  additionalProperties?: Record<string, unknown>;
}

const FLOW_CONFIGS: Record<FlowKey, FlowConfig> = {
  meeting: {
    promptFilePath: PROMPT_PATHS.meeting,
    notionDatabaseEnvKey: "NOTION_MEETING_DATABASE_ID",
    includeAttendees: true,
    summaryModels: [...MEETING_SUMMARY_MODELS],
    titlePropertyName: "Name",
    inferTitleFromContent: true,
    documentTitleBuilder: (name) => `Meeting - ${name}`,
  },
  "project-updates": {
    promptFilePath: PROMPT_PATHS["project-updates"],
    notionDatabaseEnvKey: "NOTION_PROJECT_UPDATES_DATABASE_ID",
    includeAttendees: false,
    summaryModels: [...PROJECT_UPDATE_SUMMARY_MODELS],
    titlePropertyName: "Title",
    documentTitleBuilder: (name) => `Project Update - ${name}`,
  },
};

const envFilePath = Deno.env.get("ADAPTER_ENV_FILE") ?? `${ADAPTER_ROOT}/.env`;
const env = config({ path: envFilePath }) as Record<string, string>;

function resolveEnv(key: string): string | undefined {
  return env[key] ?? Deno.env.get(key);
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

  if (!parsed.action || !parsed.transcriptPath || !parsed.summaryPath) {
    throw new Error("Request must include action, transcriptPath, and summaryPath.");
  }

  return parsed;
}

async function summarize(request: RunRequest): Promise<RunResponse> {
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
      const existing = await Deno.readTextFile(request.summaryPath);
      if (existing.trim().length > 0) {
        const title = inferTitle(existing, request.transcriptPath, flowConfig, language).title;
        return {
          success: true,
          action: "summarize",
          title,
          summaryPath: request.summaryPath,
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

  const summaryDir = request.summaryPath.split("/").slice(0, -1).join("/");
  if (summaryDir) {
    await Deno.mkdir(summaryDir, { recursive: true });
  }
  await Deno.writeTextFile(request.summaryPath, combinedSummary);

  const title = inferTitle(combinedSummary, request.transcriptPath, flowConfig, language).title;

  return {
    success: true,
    action: "summarize",
    title,
    summaryPath: request.summaryPath,
  };
}

async function publish(request: RunRequest): Promise<RunResponse> {
  const flow = parseFlow(request.flow);
  const language = parseLanguage(request.language);
  const flowConfig = FLOW_CONFIGS[flow];
  const notionApiKey = resolveEnv("NOTION_API_KEY");
  const notionDatabaseId = resolveEnv(flowConfig.notionDatabaseEnvKey);
  const notionUserId = resolveEnv("NOTION_USER_ID");
  const skipNotion = resolveEnv("SKIP_NOTION") === "1";

  let summaryMarkdown: string;
  let transcript: string;

  try {
    summaryMarkdown = await Deno.readTextFile(request.summaryPath);
    transcript = await Deno.readTextFile(request.transcriptPath);
  } catch (error) {
    return {
      success: false,
      action: "publish",
      error: `Could not read summary or transcript: ${error}`,
    };
  }

  const inferred = inferTitle(summaryMarkdown, request.transcriptPath, flowConfig, language);
  const documentTitle = inferred.title;
  const documentContent = inferred.content;

  if (!skipNotion && (!notionApiKey || !notionDatabaseId)) {
    return {
      success: false,
      action: "publish",
      error: "Notion credentials are not configured.",
    };
  }

  let documentUrl: string | undefined;

  try {
    if (!skipNotion) {
      documentUrl = await createNotionDocument(
        documentTitle,
        documentContent,
        flowConfig.includeAttendees ? notionUserId : undefined,
        notionDatabaseId!,
        notionApiKey!,
        {
          includeAttendees: flowConfig.includeAttendees,
          titlePropertyName: flowConfig.titlePropertyName,
          additionalProperties: flowConfig.additionalProperties,
          transcript,
        },
      );
    }

    return {
      success: true,
      action: "publish",
      title: documentTitle,
      documentUrl,
      summaryPath: request.summaryPath,
    };
  } catch (error) {
    return {
      success: false,
      action: "publish",
      error: `Publishing failed: ${error}`,
    };
  }
}

function inferTitle(
  summaryMarkdown: string,
  transcriptPath: string,
  flowConfig: FlowConfig,
  language: SummaryLanguage,
) {
  const fileName = transcriptPath.split("/").pop() || "Unknown";
  const baseName = fileName.replace(/\.[^/.]+$/, "");
  const fallbackTitle = flowConfig.documentTitleBuilder
    ? flowConfig.documentTitleBuilder(baseName)
    : `Summary - ${baseName}`;

  if (flowConfig.inferTitleFromContent) {
    return inferDocumentTitle(summaryMarkdown, fallbackTitle, { language });
  }

  return {
    title: language === "german" ? applyGermanTitleFlag(fallbackTitle) : fallbackTitle,
    content: summaryMarkdown,
  };
}

async function main() {
  try {
    const request = await readRequest();
    const response = request.action === "publish"
      ? await publish(request)
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
