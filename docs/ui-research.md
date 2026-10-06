# Dictum: UI research brief (2026-10-06)

## Sources
- superwhisper docs, `superwhisper.com/docs/`: get-started/{quickstart, essential-settings, settings-advanced, interface-rec-window, interface-menu-bar, interface-history, choose-your-model}, modes/{modes, built-in, switching-modes}, common-issues/{no-voice-found, llm-processing-error, crashes, pasting-issues, performance-tips}; https://superwhisper.com/changelog
- Wispr Flow help, `docs.wisprflow.ai/articles/`: 3152211871 (setup), 5096240724 (navigating), 6409258247 (first dictation), 6391241694 (hands-free), 2612050838 (shortcuts), 5002934560 + 1790396454 (Flow Bar), 4351452717 (mic), 3155947051 (startup errors); https://wisprflow.ai/whats-new
- VoiceInk: https://github.com/Beingpax/VoiceInk (README plus the views ContentView, SettingsView, MenuBarView, Onboarding/*, History/*). Read for information architecture only; no code copied.
- https://docs.macwhisper.com/article/14-how-to-use-the-dictation-feature · https://aquavoice.com/guide/history · https://spokenly.app/docs, /docs/local-only-mode · https://www.monologue.to/docs/getting-started/mac · https://matthewcassinelli.com/recommended-apps-monologue-mac-ios/ · https://www.getvoibe.com/help/how-on-device-works/ · https://www.getvoibe.com/resources/willow-voice-review/ (the only Willow source, written by a competitor) · https://betterdictation.com

## Onboarding
- **Common order:** permissions, mic test, shortcut, model, practice run. superwhisper asks only for language, model and mic ("defaults work well"). Wispr skips permissions already granted, makes practice skippable, and resumes after quitting.
- **VoiceInk permission rows:** each has a number, a title, and one purpose line ("uses Accessibility to type transcriptions directly into any app"). The status reads *Granted / Needs access / Denied*, and the button changes from **Allow** to **Open Settings** after a denial, deep-linking to the exact Privacy pane. Monologue marks each permission Required or Optional.
- **Model card (VoiceInk):** name, description, a "Local" pill, a progress bar with %, **Download Model / Cancel / Resume Download**, then "Downloaded". superwhisper's download screen has **Skip** and shows the size first.
- **Until setup finishes**, VoiceInk's menu shows only "Complete Onboarding" and Quit.

## Settings structure
**What the apps use:**
- **superwhisper:** Home, Modes, Models library, Configuration (shortcuts, retention), Sound (input, silence removal, sounds), Advanced (Dock, clipboard restore, model active duration), History, Vocabulary.
- **Wispr:** General (shortcuts, mic, languages), System (login, Flow Bar, Dock), Account.
- **VoiceInk:** Shortcuts, Pasting (restore delay 250 ms–5 s), Interface (appearance, recorder style), General, Diagnostics.

**Proposed for Dictum** (SwiftUI `Settings` scene, toolbar tabs):
1. **General:** launch at login, keycap recorders (Dictate ⌥Space, Dictate with Cleanup, Paste Last ⌃⌘V), Pasting (paste or copy only, clipboard restore delay).
2. **Recording:** mic picker with a live meter, window style Mini/Classic/None, "Always show indicator", sounds, pause media.
3. **Modes:** default mode, per-mode shortcut, Cleanup instructions/tone.
4. **Models:** speech and LLM cards (size, state, download/delete), "Keep loaded for".
5. **History:** retention, keep audio, clear all.
6. **About:** version, live permission checklist, logs, reset onboarding.

## Menu bar menu
- **superwhisper:** Toggle Recording, History…, Settings…, input device, Select Mode, Check for Updates, Quit. A dot on the icon shows state: yellow while the model loads, red while recording, blue while processing, green when done.
- **VoiceInk adds:** Retry Last, Copy Last ⇧⌘C, Quick History ⇧⌘H, Launch at Login.
- **Dictum:** a disabled status line ("Ready, hold ⌥Space" / "Downloading model, 42 %"), then Mode submenu, Microphone submenu, Paste Last, Copy Last, History…, Settings… ⌘,, Quit.

## History
- **superwhisper:** stores audio, raw text and AI result, with search and reprocessing in another mode. Retention runs from Forever to 1 day, with a warning before deleting.
- **Wispr:** entries are grouped by date. Hovering gives copy and audio play (14 days), and ↑/↓ moves through entries. Failed rows turn orange with "Retry your X:XX transcript", and "Undo AI edit" restores the raw text.
- **VoiceInk:** each row shows date · duration · preview. The Quick History panel offers ↵ Paste Text, and text and audio retention are set separately.
- **Aqua:** keeps audio for 3 days, with replay, re-run and copy.

## Modes
- **superwhisper:** a mode is a voice model plus an optional AI step. Voice to Text skips the AI step for speed. Message mode strips fillers and fixes grammar, with a Casual↔Formal Tone slider. You switch from the menu, per-mode shortcuts, per-app rules, or by holding ⌥⇧K in the window.
- **Monologue:** shows the active mode in its mini window.
- **Voibe:** keeps AI formatting as a toggle separate from the engine.

## Feedback
- **Sounds:** superwhisper gives start/stop sounds separate volumes, plus an empty-result sound. Monologue beeps on release.
- **Media:** superwhisper can Pause / Lower / Mute playback while recording.
- **Indicator:** superwhisper's mini window can stay visible while idle, with hover controls and right-click Settings / History. Wispr's Flow Bar shows resting, recording and processing, has "Show at all times" and "Hide for 1 hour", and lets clicks through.
- **Cancel:** superwhisper's Esc confirms only after 30 s. In Wispr, the cancel toast offers Undo and a too-short tap returns to idle.
- **Theme:** superwhisper and VoiceInk offer Light/Dark/System. Dictum's black capsule works in both, so following the system is enough.

## Error states
- **Model missing:** the pill reads "Model downloading, 42 %". Never fail silently.
- **Helper crash:** superwhisper saves audio while recording, so crashes can be reprocessed. Wispr offers "Restart Flow" and Recover.
- **Mic denied:** Wispr shows "Microphone Permission Required" with Grant Permission or Open Settings.
- **No speech:** superwhisper shows "No voice found in recording". Paste nothing and leave the clipboard alone.
- **AI step fails:** paste the raw transcript (superwhisper).

## Recommendations for Dictum
1. **Never lose a dictation.** Save the audio while recording, keep it until transcription succeeds, and offer Retry after a helper crash.
2. **Permission checklist** with a live status per row. Allow becomes Open System Settings. Re-check when the app becomes active, not on a timer.
3. **Background model download** with size, %, Cancel/Resume and "Download later". Every surface shows the missing-model state.
4. **Keep models loaded for** 30 s / 5 min / 1 h / Always, with the speech model and the LLM unloaded separately.
5. **Cleanup fallback:** if the LLM fails or times out, paste the raw text. Store both texts and add "Show original".
6. **Paste Last ⌃⌘V and Copy Last,** with the clipboard restored about 0.5 s after pasting.
7. **Menu-bar icon** shows loading, recording, processing and attention, plus a status line in the menu.
8. **Two modes:** a ✓ submenu, a hotkey per mode, and the mode name in the Classic footer. Dictation skips the LLM.
9. **History:** rows show time · duration · mode · preview, hover gives Copy/Paste/Retry, ↵ pastes, and there is search. Load pages lazily.
10. **Quiet feedback:** preloaded sounds with one volume slider, optional media pause, and an optional static idle capsule (off by default). Short taps cancel silently.
