# Meeting Summaries to Notion Adapter

Bundled Deno adapter used by Scribe Clerk for summary generation and Notion publishing.

## Setup

1. Copy `.env.example` to `.env` in this directory.
2. Fill in `OPENROUTER_API_KEY`, `NOTION_API_KEY`, `NOTION_MEETING_DATABASE_ID`, and `NOTION_USER_ID`.

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

Publish:

```json
{
  "action": "publish",
  "transcriptPath": "/path/to/transcript.txt",
  "summaryPath": "/path/to/summary.md",
  "flow": "meeting",
  "language": "english"
}
```

Stdout returns JSON with `success`, `title`, `documentUrl`, and `error`.

## Inbox

Drop files in the app or point external tools at Scribe Clerk's inbox folder:

`~/Library/Application Support/ScribeClerk/inbox/`

Import recordings manually from the Inbox section in the app. Scribe Clerk handles transcription locally; this adapter only summarizes and publishes.
