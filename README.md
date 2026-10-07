<p align="center"><img src="App/Assets.xcassets/AppIcon.appiconset/icon_256x256.png" width="128" alt=""></p>

<h1 align="center">Dictum</h1>

<p align="center">Hold a shortcut, speak, let go — your words are typed into whatever app you're in.<br>
On-device dictation for Apple Silicon Macs, powered by Cohere Transcribe and Tiny Aya.</p>

<p align="center"><img src="docs/images/mini-sleep.png" height="36" alt="Sleeping pill"> &nbsp; <img src="docs/images/mini-toolbar.png" height="96" alt="Hover toolbar"> &nbsp; <img src="docs/images/mini.png" height="54" alt="Recording"> &nbsp; <img src="docs/images/classic.png" height="150" alt="Classic recording window"></p>

## Features

- **Hold ⌥Space, speak, release.** Text is pasted into the frontmost app and your clipboard is restored. Esc cancels.
- **Fully on-device.** Cohere Transcribe (4-bit, 14 languages) runs locally with MLX. Nothing leaves your Mac.
- **Rewrite mode.** Hold ⌥⇧Space, or make Rewrite the default, and Tiny Aya removes fillers, false starts and self-corrections. If its rewrite drifts from what you said, Dictum pastes your plain transcript instead.
- **Light on resources.** 0 % CPU and no wakeups between dictations. See [Resource use](#resource-use).
- **Recording window:**
  - **Small window:** sleeps as a thin translucent pill when idle. Hover it for ✦ Rewrite, Settings and ⤢ Expand. Drag it to snap to the top or bottom of the screen, centred or in a corner.
  - **Large window (Classic):** moves freely and resizes from its edges. Its ↘↖ button returns to the pill.
  - Both are fully opaque while recording.
- **Home window** in the style of superwhisper. A sidebar holds Home, Modes, Vocabulary, Configuration, Sound, Models library and History. Home shows your average WPM, words, apps used and time saved.
- **Vocabulary:** teach Dictum how to write names and terms, with optional "heard as" spellings. It's applied to every transcript.
- **History** keeps both the rewrite and the original. Failed dictations keep their audio so you can retry them. **Paste Last** is on ⌃⌥V.
- Mic picker, language hint, sounds, launch at login, and "keep models loaded for" to trade memory against first-use speed.

<p align="center"><img src="docs/images/onboarding.png" width="420" alt="Welcome window"> <img src="docs/images/settings-recording.png" width="400" alt="Recording settings"></p>

## Requirements

- An Apple Silicon Mac running macOS 14 or later
- [uv](https://docs.astral.sh/uv/) (`brew install uv`) or Python 3.13+. Dictum uses it once to create a private Python runtime.
- About 2 GB of disk for the speech model, plus 2 GB for Rewrite. The first setup downloads 2.4 GB (+ 3.6 GB for Rewrite).

## Install

1. Download `Dictum.zip` from [Releases](../../releases), unzip it, and move **Dictum.app** to Applications.
2. Open it. Dictum isn't notarized yet, so the first time macOS will refuse. Go to **System Settings → Privacy & Security** and click **Open Anyway**.
3. The welcome window walks you through Microphone and Accessibility access, then installs the speech engine with one click.

Dictum lives in the menu bar (the waveform icon). It has no Dock icon.

## Build from source

```sh
brew install xcodegen uv
make install      # Release build → /Applications/Dictum.app, then launch it
make run          # Debug build, run from build/
```

The Makefile signs with your Apple Development certificate when it finds one, so macOS privacy grants survive rebuilds. Without one, it signs ad-hoc.

## How it works

```
Dictum.app (Swift)                              dictum_helper.py (Python, MLX)
 ├ hotkeys (KeyboardShortcuts)                   ├ Cohere Transcribe, 4-bit, kept loaded
 ├ AVAudioEngine → 16 kHz mono WAV  ── Unix ──▶  ├ Tiny Aya Global, 4-bit, loaded on demand
 ├ Core Animation recording window    socket     └ downloads + converts models on first run
 └ clipboard + ⌘V, then restore     ◀── text ──
```

- **The app** handles the UI, hotkeys, audio and pasting. The microphone is open only while you hold the shortcut.
- **The helper** runs from `~/Library/Application Support/Dictum/runtime`, a private virtualenv with `mlx-speech` and `mlx-lm`. It answers JSON lines on a Unix socket, does nothing between requests, and exits when the app quits.
- **Models** are downloaded from Hugging Face and re-quantized locally to 4-bit:
  - Cohere Transcribe: int8 → 4-bit. Same accuracy in English/French tests, 0.9 GB less RAM.
  - Tiny Aya: 8-bit → 4-bit.

## Resource use

Measured on an M4 Pro (Release build):

| | CPU | Memory |
|---|---|---|
| App, idle | 0.0 %, no wakeups | ~20–30 MB |
| App, recording (Classic window, 105 bars at 30 Hz) | ~1 % | ~19 MB |
| Speech model loaded (default "Always") | 0.0 % idle | ~1.6 GB |
| + Rewrite model, while loaded (unloads after 1 min) | — | +1.9 GB |
| Transcribing ~9 s of speech | — | ~0.25 s |
| Rewriting a sentence | — | ~0.8 s (first use ~2.5 s) |

The recording window is drawn with Core Animation layers. A SwiftUI version cost 4–8 % CPU and 153 MB.

## Privacy

Audio, transcripts and history stay on your Mac. Recordings are deleted as soon as they're transcribed, unless transcription fails, in which case the audio is kept so you can retry. History is a JSON file in `~/Library/Application Support/Dictum`, and you can turn it off. The only network access is the one-time model download from Hugging Face.

## Limitations

- **Language.** Cohere Transcribe has no language detection, so the language setting is a hint. In testing, French speech still came out in French with English selected.
- **Rewrite.** Tiny Aya is small. It occasionally misses a self-correction, and the faithfulness check falls back to the plain transcript when a rewrite strays.
- **Distribution.** The app isn't notarized yet; see [Install](#install).

## Licenses

- **Dictum's code:** MIT (see [LICENSE](LICENSE)).
- **Models,** downloaded at runtime and not redistributed here:
  - [Cohere Transcribe](https://huggingface.co/CohereLabs/cohere-transcribe-03-2026): Apache 2.0.
  - [Tiny Aya Global](https://huggingface.co/CohereLabs/tiny-aya-global): **CC-BY-NC 4.0, personal, non-commercial use only.** Rewrite mode is optional for that reason.
- **Libraries:** [mlx-speech](https://github.com/appautomaton/mlx-speech) and [mlx-lm](https://github.com/ml-explore/mlx-lm) (MIT), [KeyboardShortcuts](https://github.com/sindresorhus/KeyboardShortcuts) (MIT).
