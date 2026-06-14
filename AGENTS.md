# TSX Deck Codex Workflow

This repository is the active local working copy for TSX Deck:

- Project root: `/Users/a9/Desktop/tsx-deck-reorg`
- Main source: `/Users/a9/Desktop/tsx-deck-reorg/outputs/topstepx_float_panel.swift`
- Build script: `/Users/a9/Desktop/tsx-deck-reorg/outputs/build_app.sh`
- Test app: `/Users/a9/Desktop/tsx-deck-reorg/outputs/TSX Deck.app`

## Default workflow

For code or UI changes:

1. Read the relevant Swift code first.
2. Keep edits narrow and use `apply_patch` for manual source edits.
3. Do not change trading/order/API logic unless the user explicitly asks for that behavior.
4. After each change, build and reopen the desktop app:

```bash
cd /Users/a9/Desktop/tsx-deck-reorg
./outputs/build_app.sh
pkill -f 'TopstepXFloatPanel|TSX Deck' 2>/dev/null || true
sleep 1
open '/Users/a9/Desktop/tsx-deck-reorg/outputs/TSX Deck.app'
```

The recurring Swift warning about a `PillButton` conditional cast is known and not related to most UI edits.

## Trading safety

- Treat TopstepX / ProjectX official API responses as the source of truth.
- Do not fabricate order/account/position fields that are not returned by the API.
- Do not alter `buildOrderPayload`, bracket payloads, cancellation, flatten, account selection, or contract-id validation for visual-only requests.
- Keep `readOnly`, `sendBrackets`, and local config semantics unchanged unless the user explicitly asks.
- Never print real API keys, tokens, or account secrets.

## GitHub and release workflow

- The GitHub remote is `https://github.com/75day/tsx-deck.git`.
- Use the GitHub plugin or `gh` for GitHub tasks; `gh` is installed and authenticated as `75day`.
- Before any commit or push, run `git status --short` and summarize the intended diff.
- Do not push, force-push, or rewrite GitHub history unless the user explicitly asks.

## Plugin usage

- Use the GitHub plugin for PRs, commits, issue/PR inspection, and GitHub state.
- Browser/Chrome plugins are optional and should be used only for web UI/docs checks, not for the native AppKit app itself.
- For this native macOS app, the primary verification is local build + opening `TSX Deck.app`.

## Repository hygiene

- Do not commit `outputs/topstepx_config.json`, app bundles, generated binaries, logs, or local secrets.
- Keep screenshots/docs changes separate from app source changes when practical.
- The project is currently a compact AppKit implementation; avoid broad refactors during small UI iteration.
