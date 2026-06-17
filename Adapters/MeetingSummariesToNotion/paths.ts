const adapterRoot = decodeURIComponent(
  new URL(".", import.meta.url).pathname,
).replace(/\/$/, "");

export function adapterPath(...parts: string[]): string {
  return [adapterRoot, ...parts].join("/");
}

export const ADAPTER_ROOT = adapterRoot;
export const PROMPT_PATHS = {
  meeting: adapterPath("prompt.md"),
  "project-updates": adapterPath("project_updates_prompt.md"),
} as const;
