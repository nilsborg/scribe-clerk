# Meeting Summaries Adapter

Bundled Deno adapter used by Scribe Clerk for AI summary and title generation via
OpenRouter. (The directory name is kept for compatibility; Notion publishing has
been removed.)

## Setup

1. Copy `.env.example` to `.env` in this directory.
2. Fill in `OPENROUTER_API_KEY`.

## JSON API

Scribe Clerk calls `run.ts` with JSON on stdin:

```json
{
  "action": "summarize",
  "transcriptPath": "/path/to/transcript.txt",
  "summaryPath": "/path/to/summary.md",
  "flow": "meeting",
  "language": "english",
  "skipCache": false
}
```

Generate a title only:

```json
{
  "action": "title",
  "transcriptPath": "/path/to/transcript.txt"
}
```

Stdout returns JSON with `success`, `title`, `summaryPath`, and `error`.

## Inbox

Drop files in the app or point external tools at Scribe Clerk's inbox folder:

`~/Library/Application Support/ScribeClerk/inbox/`

Import recordings manually from the Inbox section in the app. Scribe Clerk handles
transcription locally; this adapter only generates summaries and titles.
