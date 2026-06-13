# Voice Memo Transcriber

Personal macOS app that reads recordings from Apple Voice Memos and transcribes them locally with [whisper.cpp](https://github.com/ggerganov/whisper.cpp).

## Requirements

- macOS 14+
- Voice Memos with recordings on this Mac
- `whisper-cli` (Homebrew: `brew install whisper-cpp`)
- A GGML model in `~/whisper-models/` (defaults to `ggml-small.bin`)

## Build

```bash
cd ~/repos/voice-memo-transcriber
chmod +x scripts/build-app.sh
./scripts/build-app.sh
open dist/Voice\ Memo\ Transcriber.app
```

Or run directly during development:

```bash
swift run
```

## First launch

1. Open **System Settings → Privacy & Security → Full Disk Access**
2. Add **Voice Memo Transcriber** (or Terminal/Cursor if using `swift run`)
3. Restart the app and click **Refresh**

## Usage

- Select a memo in the sidebar to view or create its transcript
- **Transcribe** runs `whisper-cli` against the `.m4a` file
- **Transcribe New** processes all memos that do not have a saved transcript yet
- Transcripts are cached in `~/Library/Application Support/VoiceMemoTranscriber/transcripts/`

## Settings

Defaults:

- Whisper binary: `/opt/homebrew/bin/whisper-cli`
- Model: `~/whisper-models/ggml-small.bin`
- Language: `auto`
