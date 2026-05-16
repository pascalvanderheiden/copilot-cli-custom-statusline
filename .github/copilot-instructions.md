# Copilot instructions

This repo provides a custom statusline script for [GitHub Copilot CLI](https://docs.github.com/en/copilot/concepts/agents/about-copilot-cli). It has **two parallel implementations that must stay behaviorally in sync**: a Bash script for macOS/Linux and a PowerShell port for Windows.

## Repository layout

- `statusline.sh` — macOS/Linux Bash implementation (the original).
- `windows/statusline.ps1` — Windows PowerShell port. **Must be saved with a UTF-8 BOM** (`EF BB BF`) or `powershell.exe` 5.1 corrupts glyphs like `█ ░ ↻ ·` at parse time and Copilot CLI renders nothing.
- `windows/statusline.cmd` — required two-line `.cmd` wrapper that invokes `pwsh -File`. Inline `powershell.exe` in `settings.json` is unreliable on Windows.
- `README.md` / `windows/README.md` — user-facing setup docs.
- `assets/` — screenshots for the README. No tests, no build, no CI.

## How the statusline works

Copilot CLI pipes a JSON status payload to the script on stdin and renders a single line of stdout at the bottom of the CLI. The script:

1. Reads stdin (only if not a TTY) and uses `jq` (Bash) / `ConvertFrom-Json` (PS) to extract the project dir (`cwd`, `workingDirectory`, `workspaceFolders[0].path`, etc.).
2. Falls back to `$PWD` if the JSON has no usable path.
3. Calls a series of `*_status` functions, each producing **one segment** (e.g. `azure_status`, `github_status`, `openspec_status`, `speckit_status`, `squad_status`, `token_usage_status`).
4. Joins non-empty segments with ` · ` (dim) and ANSI-colors each segment via the `paint` helper. Color codes (`38;5;NNN`) are defined once at the top of each script — reuse those variables instead of hard-coding.

Each segment function **must return empty (and exit 0)** when its tool is missing or unauthenticated. Missing segments are skipped silently — never print errors to stdout.

## Caching contract (important)

External commands (`az`, `gh`, `ai-engineering-fluency`, `openspec`, `squad`) are slow and can exceed Copilot CLI's ~10 s statusline timeout. Always go through the cache helpers:

- `cached_command <key> <ttl_seconds> <dir> <cmd...>` — caches any output (including failures).
- `cached_success_command <key> <ttl_seconds> <dir> <cmd...>` — only caches and returns when the command exits 0 and produces non-empty output; deletes the cache on failure. Use this for auth-style probes (`az account show`, `gh auth status`).
- Cache dir: `${XDG_CACHE_HOME:-$HOME/.cache}/copilot-statusline` on macOS/Linux, `%LOCALAPPDATA%\copilot-statusline\` on Windows. Bump the cache key suffix (e.g. `azure-account-v4`) when changing the cached command's output shape so stale entries are invalidated.
- `run_with_timeout` wraps every external call (default 5 s, overridable via `STATUSLINE_COMMAND_TIMEOUT_SECONDS`). Don't call external tools without it.

`ai-engineering-fluency usage` is the known offender: ~60 s cold run. The Windows README documents a manual pre-warm — don't try to "fix" this by removing the cache.

## Project-marker segments

`squad_status`, `openspec_status`, `speckit_status` walk up from the resolved project dir looking for marker files/dirs (`.squad`, `openspec`/`.openspec`, `.specify` or `specs/<feature>/{spec,plan,tasks}.md`). Use `find_up` for single-marker lookups. Spec Kit progress comes from counting `- [ ]` / `- [x]` checkboxes in `tasks.md` via `count_tasks` — keep that GFM checkbox regex in both implementations.

## Keeping macOS and Windows in sync

When adding or changing a segment, update **both** `statusline.sh` and `windows/statusline.ps1`. Reuse the same segment label (`az:`, `gh:`, `openspec:`, `spec-kit:`, …) and the same cache key so users see identical output across platforms. Then update the segment tables in both README files.

## Manual verification

There is no test suite. Verify changes by running the script directly:

```bash
# macOS/Linux — empty stdin path
~/.copilot/statusline.sh

# With a simulated Copilot CLI payload
echo '{"cwd":"'"$PWD"'"}' | ./statusline.sh
```

```powershell
# Windows — exercises the .cmd wrapper end-to-end
Get-Content payload.json | & "$env:USERPROFILE\.copilot\statusline.cmd"
```

After editing, restart Copilot CLI (`/restart`) to pick up the new script.

## PowerShell port gotchas (already handled — don't regress them)

- Keep the UTF-8 BOM on `statusline.ps1`.
- No `ConvertFrom-Json -Depth` (PS 6+ only).
- No `if` used as an expression (`$x = if (...) {...}`) — PS 7+ only. Assign inside plain `if` blocks for 5.1 compatibility.
- Force UTF-8 output encoding at the top of the script; the OEM default mangles the box-drawing/`·` glyphs.

## Bash style

Targets `#!/usr/bin/env bash`. Quote all expansions, prefer `printf` over `echo`, use `command -v tool >/dev/null 2>&1 || return 0` to gate every segment on tool availability, and keep `stat -f %m` / `stat -c %Y` fallbacks for BSD vs GNU portability.
