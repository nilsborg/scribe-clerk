# Scribe Clerk

Transcribe audio locally with [whisper.cpp](https://github.com/ggerganov/whisper.cpp), keep a managed recording library, and generate editable summaries.

## Requirements

- macOS 14+
- `whisper-cli` (Homebrew: `brew install whisper-cpp`)
- `deno` (Homebrew: `brew install deno`)
- GGML models in `~/whisper-models/` (defaults to `ggml-medium.bin`)
- Adapter `.env` with an OpenRouter credential (see `Adapters/MeetingSummariesToNotion/.env.example`)
- (Optional) sherpa-onnx for speaker detection — see below

## Speaker detection (optional)

Enable **Identify speakers** in the transcribe dialog to label the transcript by
speaker (`Speaker 1:`, `Speaker 2:` …). Whisper still does the transcription in
your chosen language and model; a separate [sherpa-onnx](https://github.com/k2-fsa/sherpa-onnx)
diarization pass figures out *who* spoke when, and the two are merged by
timestamp. It works in any language, including German.

**1. Install the sherpa-onnx binary.** Either via pip:

```bash
pip install sherpa-onnx
# then set the printed .../bin/sherpa-onnx-offline-speaker-diarization path in Settings
```

or download the prebuilt macOS (Apple Silicon) archive and put the binary on your PATH:

```bash
curl -L -O https://github.com/k2-fsa/sherpa-onnx/releases/download/v1.13.4/sherpa-onnx-v1.13.4-osx-arm64-shared.tar.bz2
tar xf sherpa-onnx-v1.13.4-osx-arm64-shared.tar.bz2
# keep bin/ and lib/ together; point Settings → "sherpa-onnx binary" at bin/sherpa-onnx-offline-speaker-diarization
```

**2. Download the two models** into `~/whisper-models/diarization/`:

```bash
mkdir -p ~/whisper-models/diarization && cd ~/whisper-models/diarization

# Segmentation (pyannote 3.0) — extract to a single .onnx with the expected name
curl -L https://github.com/k2-fsa/sherpa-onnx/releases/download/speaker-segmentation-models/sherpa-onnx-pyannote-segmentation-3-0.tar.bz2 | tar xj
mv sherpa-onnx-pyannote-segmentation-3-0/model.onnx sherpa-onnx-pyannote-segmentation-3-0.onnx

# Speaker embedding (VoxCeleb / English–European)
curl -L -O https://github.com/k2-fsa/sherpa-onnx/releases/download/speaker-recongition-models/wespeaker_en_voxceleb_resnet34_LM.onnx
```

Settings (⌘,) → **Speaker detection** shows "Ready" once the binary and both
models are found. The speaker count is auto-detected; if distinct speakers get
merged (or one person is split across labels), tune `clusterThreshold` in
`SpeakerDiarizer.swift`.

## Build

```bash
cd ~/Repos/scribe-clerk
cp Adapters/MeetingSummariesToNotion/.env.example Adapters/MeetingSummariesToNotion/.env
./scripts/build-app.sh
open dist/Scribe\ Clerk.app
```

## Workflow

1. **Add** audio via drag & drop, file picker, or the inbox folder
2. **Import** from the inbox into your library
3. **Transcribe** with Whisper (auto-detect language by default), optionally identifying speakers
4. **Summarize** into editable markdown (meeting notes or project updates, English or German)

### Inbox

Drop files in the app or point external tools (e.g. Audio Hijack) at:

`~/Library/Application Support/ScribeClerk/inbox/`

Recordings appear in the Inbox section. Click **Import** to move them into the managed library.

### Voice Memos

Drag recordings from Voice Memos into the app window.

## Library layout

`~/Library/Application Support/ScribeClerk/`

- `inbox/` — staging area for new recordings
- `recordings/{id}/` — managed audio, transcript, summaries, and metadata

## Development

```bash
./scripts/open-xcode.sh
```

Press **⌘R** to build and run.

## Settings (⌘,)

- Whisper binary and default model
- sherpa-onnx binary for speaker detection
- Deno binary path
- Adapter `.env` file path
- Default summarizer pipeline
