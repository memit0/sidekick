# Sidekick

An open-source AI buddy that lives next to your cursor on macOS. Hold **Control + Option**, ask a question out loud, and it looks at your screen, answers out loud, and can point at what you need to click.

It uses **your existing Claude subscription** through the Claude Code CLI, so there's no API key and no extra bill. Everything else is free and built into macOS:

| Piece | How |
|---|---|
| Brain | `claude -p` (Claude Code) on your Pro/Max plan |
| Speech-to-text | Apple Speech framework (on-device when supported) |
| Voice | macOS built-in voices |
| Screen | `screencapture` |

Inspired by Farza's Clicky. This is an independent implementation.

## Requirements

- macOS 14 (Sonoma) or later
- Xcode or Command Line Tools: `xcode-select --install`
- [Claude Code](https://docs.claude.com/en/docs/claude-code), logged in with your Claude account. Run `claude` once in Terminal and use `/login` if needed.

## Install

```bash
git clone <this repo> sidekick && cd sidekick
./build.sh
cp -R build/Sidekick.app /Applications/
open /Applications/Sidekick.app
```

On first launch, allow **Microphone**, **Speech Recognition** and **Screen Recording** (System Settings → Privacy & Security). Relaunch Sidekick after granting Screen Recording.

> Rebuilding re-signs the app, so macOS may ask for permissions again. If screenshots stop working after a rebuild, remove Sidekick from the Screen Recording list and add it back.

## Use

- **Hold ⌃ Control + ⌥ Option**, talk, release. The dot turns red (listening), orange (thinking), then green (speaking).
- Ask things like "what does this error mean?", "where's the export button?" or "how do I make this column wider?"
- Follow-ups remember context for 5 minutes. Use **New Conversation** in the menu bar to start over.
- Pick Haiku (fastest), Sonnet (default) or Opus from the menu bar icon.

### Better voice

Download a Premium or Enhanced voice: System Settings → Accessibility → Spoken Content → System Voice → Manage Voices. Sidekick picks the best one for your language automatically, or set one:

```bash
defaults write dev.sidekick.app voice com.apple.voice.premium.en-US.Zoe
```

### If it can't find Claude Code

```bash
defaults write dev.sidekick.app claudePath "$(which claude)"
```

## How it works

1. Pressing the hotkey grabs a screenshot of the screen under your cursor (the overlay hides itself from captures) and starts speech recognition.
2. On release, it sends the transcript plus the screenshot to `claude -p --input-format stream-json` and resumes the same session for follow-ups.
3. Claude replies in short spoken sentences, optionally ending with `[POINT:x,y:label]`. Sidekick strips that tag, flies the dot to that spot and reads the rest aloud.

`ANTHROPIC_API_KEY` is removed from the environment Sidekick passes to Claude Code, so it always uses your subscription login.

Usage counts toward your plan's normal limits. This drives the official Claude Code CLI on your own machine for personal use. It doesn't extract or reuse your login token.

## License

MIT
