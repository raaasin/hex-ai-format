# AGENTS

## Purpose

This repo contains a small macOS Swift utility that works alongside Hex.
It captures selected text, waits for a Hex transcript to arrive, sends the original text plus spoken instruction to xAI, and replaces the selected text with the formatted result.

## Architecture Overview

- `main.swift`: composition root, event tap setup, app startup
- `App/`: input/event listener layer
- `UseCases/`: formatting flow orchestration and state machine
- `Domain/`: core models and prompt construction
- `Adapters/`: system integration (clipboard, AX, notifications, Hex history, xAI)

Dependency direction must stay inward:

`App -> UseCases -> Domain`

Adapters support the flow but should not pull business logic into OS-specific code.

## Development Guidelines

- Keep changes lean and localized.
- Do not move business logic into `main.swift` or the event listener.
- Keep prompts in `Domain/PromptBuilder.swift`.
- Keep xAI request/response handling in `Adapters/XAIClient.swift`.
- Keep Hex history access in `Adapters/HexHistoryRepository.swift`.
- Preserve the current user flow: Hex should be configured to use `Fn` directly.

## Build and Run

Build:

```bash
swiftc main.swift App/*.swift Domain/*.swift UseCases/*.swift Adapters/*.swift -o hex_fn_listener
```

Run:

```bash
./hex_fn_listener
```

## Verification

There is no formal test suite yet.

Minimum verification after changes:

1. Build successfully.
2. Start the listener.
3. Select text in an editable field.
4. Hold `Fn`, speak an instruction via Hex, release `Fn`.
5. Confirm a new Hex history entry is detected and the selected text is replaced.

## Do Not Commit

- Local compiled binaries
- Derived build output
- Local logs or machine-specific files
- Temporary formatter state under `~/.hex-formatter/`
