# AGENTS

## Purpose

This repo is a small macOS Swift utility that works alongside Hex.

The app lets a user:

1. Select text in another app.
2. Hold right Option.
3. Speak an instruction through Hex.
4. Release right Option.
5. Have the selected text replaced with xAI-formatted output.

The central idea is simple: capture the original selection first, wait for Hex to write the spoken instruction into its transcription history, send both strings to xAI, then paste the formatted result back into the original app.

## Mindmap

```text
hex-fix
|
|-- main.swift
|   |-- process startup
|   |-- Accessibility trust prompt
|   |-- dependency wiring
|   |-- CGEvent tap for right Option flagsChanged events
|   `-- main run loop
|
|-- App/
|   `-- HexTriggerListener.swift
|       |-- listens for right Option key state changes
|       |-- ignores non-trigger flag changes
|       |-- calls FormatterFlow.handleTriggerDown()
|       `-- calls FormatterFlow.handleTriggerUp()
|
|-- UseCases/
|   `-- FormatterFlow.swift
|       |-- owns the formatting state machine
|       |-- captures original text on trigger down
|       |-- stores the Hex history baseline
|       |-- waits for a new Hex transcript on trigger up
|       |-- shows and animates the formatting placeholder
|       |-- calls xAI
|       |-- replaces placeholder with formatted text
|       `-- resets persisted flow state
|
|-- Domain/
|   |-- Models.swift
|   |   |-- constants
|   |   |-- Hex history models
|   |   |-- flow context
|   |   `-- app config models and defaults
|   |
|   `-- PromptBuilder.swift
|       |-- system prompt
|       `-- user prompt construction
|
`-- Adapters/
    |-- SystemAdapter.swift
    |   |-- Accessibility selected-text capture
    |   |-- clipboard fallback capture
    |   |-- safe paste
    |   |-- macOS notifications
    |   `-- System Events automation
    |
    |-- HexHistoryRepository.swift
    |   |-- reads Hex transcription_history.json
    |   `-- finds the first new matching transcript
    |
    |-- XAIClient.swift
    |   |-- loads API key
    |   |-- builds xAI Responses API request
    |   |-- parses response text from known shapes
    |   `-- reports detailed debug output
    |
    |-- ConfigRepository.swift
    |   |-- creates ~/.hex-formatter/config.json when missing
    |   `-- merges partial config with defaults
    |
    `-- StateRepository.swift
        |-- creates ~/.hex-formatter/
        |-- persists original.txt and state.json
        `-- appends debug.log
```

## Architecture Rules

Keep the business flow centered in `UseCases/FormatterFlow.swift`.

Conceptual dependency direction for business logic:

```text
App -> UseCases -> Domain
```

Adapters are edge integrations. `FormatterFlow` calls them for side effects, but they should not decide product behavior.

Important boundaries:

- `main.swift` is only for process startup, event tap setup, and dependency composition.
- `App/` translates OS input events into use-case calls.
- `UseCases/` owns orchestration, timing, state transitions, and the formatting flow.
- `Domain/` owns stable models, constants, and prompt construction.
- `Adapters/` owns macOS, filesystem, Hex history, and xAI integration details.

Do not move prompt text, API payload policy, Hex parsing policy, or flow state into the listener or `main.swift`.

## Runtime Flow

1. App starts from `main.swift`.
2. `AXIsProcessTrustedWithOptions` requests Accessibility permission if needed.
3. `main.swift` constructs:
   - `StateRepository`
   - `ConfigRepository`
   - `SystemAdapter`
   - `HexHistoryRepository`
   - `XAIClient`
   - `FormatterFlow`
   - `HexTriggerListener`
4. A `CGEvent` tap listens for `.flagsChanged`.
5. `HexTriggerListener` checks for `triggerKeyCode == 61` and `.maskAlternate`.
6. On right Option down:
   - `FormatterFlow` captures selected text.
   - It rejects empty selections and selections over `maxOriginalLength`.
   - It records the latest Hex history entry as a baseline.
   - It writes `original.txt` and `state.json`.
   - It notifies the user to speak and release right Option.
7. On right Option up:
   - `FormatterFlow` waits briefly, then polls Hex history.
   - It finds the first new transcript matching the frontmost app bundle when possible.
   - It replaces the visible instruction with an animated placeholder.
   - It sends the original text and instruction to xAI.
8. On xAI success:
   - The placeholder is selected.
   - The formatted text is pasted.
   - Flow state is cleared.
9. On timeout or xAI failure:
   - The user is notified.
   - If needed, the original text is restored.
   - Flow state is cleared.

## Folder Guide

### `main.swift`

Composition root and app entrypoint.

Owns:

- Accessibility trust prompt.
- CGEvent tap callback.
- Re-enabling the tap after timeout or user-input disablement.
- Dependency construction.
- Run loop startup.

Avoid:

- Formatting decisions.
- Prompt changes.
- Hex history parsing.
- API request or response handling.
- Clipboard and Accessibility details beyond event tap setup.

### `App/`

Input/event listener layer.

`HexTriggerListener.swift` owns:

- Tracking whether right Option is currently down.
- Filtering `.flagsChanged` events to the physical right Option key.
- Calling `FormatterFlow.handleTriggerDown()` and `FormatterFlow.handleTriggerUp()`.
- Logging ignored non-trigger flag events.

Keep this layer thin. It should not know how selection capture, Hex history, xAI, or paste replacement works.

### `UseCases/`

Application workflow layer.

`FormatterFlow.swift` owns:

- Serial workflow queue.
- `waitingForInstruction` and `processing` state.
- `ArmedContext`.
- Selection length validation.
- Hex history baseline timing.
- Polling for the spoken instruction.
- Placeholder animation.
- Success, failure, timeout, and cleanup behavior.

This is the right place for changes to the user flow.

Examples:

- Change when the app starts waiting for Hex history here.
- Change timeout behavior here.
- Change placeholder replacement behavior here.
- Change failure recovery here.

### `Domain/`

Core data and prompt layer.

`Models.swift` owns:

- `maxOriginalLength`
- `triggerKeyCode`
- `triggerKeyName`
- persisted listener-state model
- Hex history models
- `ArmedContext`
- `AppConfig`
- `PartialAppConfig`

`PromptBuilder.swift` owns:

- the system prompt
- the final user prompt shape sent to xAI

Keep prompts here. Do not duplicate prompt text in `XAIClient`, `FormatterFlow`, or `main.swift`.

### `Adapters/`

External integration layer.

`SystemAdapter.swift` owns:

- frontmost app bundle lookup
- macOS notifications through `osascript`
- selected-text capture through Accessibility
- clipboard-based copy fallback
- clipboard snapshot and restore
- safe paste
- selecting characters to the left of the cursor
- terminal-specific copy and paste shortcuts

`HexHistoryRepository.swift` owns:

- the Hex history file path
- decoding `transcription_history.json`
- sorting history entries newest-first
- finding a new entry after the saved baseline
- matching the source app bundle when available

`XAIClient.swift` owns:

- loading `XAI_API_KEY` or `OPENAI_API_KEY`
- reading keys from the environment or `~/.zshrc`
- building the xAI Responses API request
- adding xAI tools
- parsing `output_text`, `output`, and chat-style `choices`
- logging raw request and response data

`ConfigRepository.swift` owns:

- creating the default config file
- loading full or partial config
- merging partial config with `AppConfig.defaults`

`StateRepository.swift` owns:

- `~/.hex-formatter/`
- `config.json`
- `original.txt`
- `state.json`
- `debug.log`
- JSON debug formatting

Keep adapters concrete and boring. They should expose capabilities to the flow, not hide new business rules.

## Local Files and External State

The app uses user-local state outside the repo:

```text
~/.hex-formatter/
|-- config.json
|-- original.txt
|-- state.json
`-- debug.log
```

Hex transcript history is read from:

```text
~/Library/Containers/com.kitlangton.Hex/Data/Library/Application Support/com.kitlangton.Hex/transcription_history.json
```

Do not commit generated binaries, local logs, derived output, or anything under `~/.hex-formatter/`.

## Configuration

Default config lives in `Domain/Models.swift` as `AppConfig.defaults`.

The generated config file supports:

- `model`
- `base_url`
- `max_output_tokens`
- `request_timeout_seconds`
- `instruction_wait_timeout_seconds`
- `placeholder_text`
- `formatting_placeholder_frames`
- `formatting_placeholder_frame_interval_seconds`
- `debug_logging_enabled`

`ConfigRepository` accepts partial config files and fills missing fields from defaults.

Debug logging defaults to disabled. Set `debug_logging_enabled` to `true` in `~/.hex-formatter/config.json` only when troubleshooting.

API key lookup order:

1. `XAI_API_KEY` from the process environment.
2. `OPENAI_API_KEY` from the process environment.
3. `XAI_API_KEY` from `~/.zshrc`.
4. `OPENAI_API_KEY` from `~/.zshrc`.

## User Flow Constraints

Preserve the current user flow unless the user explicitly asks to change it:

- Hex should be configured to use right Option directly.
- The app should not require a second press or separate trigger.
- right Option down captures the original selected text.
- right Option up means the spoken instruction should now be available from Hex history.
- The formatted result should replace the selected text in the original editable context.

## Build and Run

Build:

```bash
swiftc main.swift App/*.swift Domain/*.swift UseCases/*.swift Adapters/*.swift -o hex_trigger_listener
```

Run:

```bash
./hex_trigger_listener
```

This is not currently a Swift Package. There is no `Package.swift` and no formal test target.

## Manual Verification

Minimum verification after code changes:

1. Build successfully.
2. Start the listener.
3. Grant Accessibility and Input Monitoring if macOS asks.
4. Select text in an editable field.
5. Hold right Option.
6. Speak an instruction through Hex.
7. Release right Option.
8. Confirm a new Hex history entry is detected.
9. Confirm the selected text is replaced by the formatted result.
10. Check `~/.hex-formatter/debug.log` if anything fails.

For doc-only changes, no build is required.

## Common Change Guide

- Prompt behavior: edit `Domain/PromptBuilder.swift`.
- Model, timeout, or placeholder defaults: edit `Domain/Models.swift`.
- Formatting state machine: edit `UseCases/FormatterFlow.swift`.
- Trigger key handling: edit `App/HexTriggerListener.swift`.
- Event tap setup or dependency wiring: edit `main.swift`.
- xAI request shape or response parsing: edit `Adapters/XAIClient.swift`.
- Hex transcript lookup: edit `Adapters/HexHistoryRepository.swift`.
- Clipboard, paste, AX, notifications, or key automation: edit `Adapters/SystemAdapter.swift`.
- Local config loading: edit `Adapters/ConfigRepository.swift`.
- Local state and debug logs: edit `Adapters/StateRepository.swift`.

## Coding Guidelines

- Keep changes lean and localized.
- Prefer existing simple classes over adding abstractions.
- Keep the serial flow in `FormatterFlow` easy to reason about.
- Do not add business behavior to adapters.
- Do not add OS integration details to `Domain/`.
- Keep prompt text centralized in `PromptBuilder`.
- Keep API logging useful, but do not intentionally log secrets.
- Preserve clipboard contents whenever possible.
- Be careful with timing changes; Hex history writes and paste automation are race-sensitive.
- Keep terminal copy and paste behavior in mind: terminal-like apps use `Cmd+Shift+C` and `Cmd+Shift+V`.

## Repository Hygiene

Do not commit:

- `hex_fn_listener`
- `hex_trigger_listener`
- `hex_fn_listener_review`
- `hex_fn_listener_test_build`
- `hex_trigger_listener_test_build`
- any other compiled local binaries
- derived build output
- local logs
- machine-specific files
- temporary formatter state under `~/.hex-formatter/`

Before handing off code changes, check:

```bash
git status --short
swiftc main.swift App/*.swift Domain/*.swift UseCases/*.swift Adapters/*.swift -o /tmp/hex_trigger_listener_test_build
```

Remove or leave untracked local binaries out of commits.
