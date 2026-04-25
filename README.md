# Hex Fix

Hex Fix is a small macOS menu bar utility that works alongside Hex. It captures selected text, waits for a spoken Hex instruction, sends both to xAI, and pastes the formatted result back into the original app.

## Requirements

- macOS
- Hex installed
- An xAI or OpenAI-compatible API key exported as `XAI_API_KEY` or `OPENAI_API_KEY`

## Build

```bash
./scripts/build_app.sh
```

That creates `build/Hex Fix.app`.

## Install

1. Build the app with `./scripts/build_app.sh`.
2. Move `build/Hex Fix.app` into `/Applications` or `~/Applications`.
3. Launch it once from Finder or with:

```bash
open "/Applications/Hex Fix.app"
```

If you do not want to install it system-wide yet, you can run it directly from the build output:

```bash
open "build/Hex Fix.app"
```

## First Run Setup

1. Grant Accessibility when macOS prompts.
2. Grant Input Monitoring if macOS prompts.
3. Configure Hex to record with `Right Option` directly.
4. Set `XAI_API_KEY` or `OPENAI_API_KEY` in your shell environment or `~/.zshrc`.

## Debugging

- Config: `~/.hex-formatter/config.json`
- Debug log: `~/.hex-formatter/debug.log`

Set `debug_logging_enabled` to `true` in `~/.hex-formatter/config.json` when troubleshooting.
