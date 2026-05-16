# Windows support

This folder contains a Windows port of `statusline.sh` for [GitHub Copilot CLI](https://docs.github.com/en/copilot/concepts/agents/about-copilot-cli) on Windows 10/11.

It produces the same kind of output as the macOS version, for example:

```text
↻ 16:17:11 · ctx: 42.1k/200k ██░░░░░░░░ 21% · az: @example.com · gh: username · squad · spec-kit: active
```

## Why a separate Windows port?

`statusline.sh` depends on `sh`, `jq`, `stat`, `shasum`, `find`, `sed`, `grep`, `cksum`, and `perl` — none of which ship with stock Windows. This folder ships a PowerShell port plus a tiny `.cmd` wrapper.

## Files

| File | Purpose |
| --- | --- |
| `statusline.cmd` | Two-line wrapper that invokes `pwsh` with the script. **Required** — see *The hidden Windows blocker* below. |
| `statusline.ps1` | Same segments as `statusline.sh`, written in PowerShell (5.1- and 7-compatible). |

## Prerequisites

- **GitHub Copilot CLI** (any recent version, tested on `1.0.44`).
- **PowerShell 7 (`pwsh`)** is recommended for clean UTF-8 handling. Install with `winget install Microsoft.PowerShell`. If you only have Windows PowerShell 5.1, edit `statusline.cmd` and replace `pwsh` with `powershell.exe`.
- The same per-segment tools as the macOS version (Azure CLI, GitHub CLI, Squad CLI, Spec Kit, etc.). On Windows they install via `winget`, `npm`, `uv`, or their MSI installers — segments are skipped automatically when their tool is missing or unauthenticated.

`jq` is **not** required on Windows: `statusline.ps1` parses the JSON natively with `ConvertFrom-Json`.

## Setup

1. Copy both files into `%USERPROFILE%\.copilot\`:

   ```powershell
   $dest = "$env:USERPROFILE\.copilot"
   New-Item -ItemType Directory -Force -Path $dest | Out-Null
   $base = "https://raw.githubusercontent.com/pascalvanderheiden/copilot-cli-custom-statusline/main/windows"
   Invoke-WebRequest "$base/statusline.cmd" -OutFile "$dest\statusline.cmd"
   Invoke-WebRequest "$base/statusline.ps1" -OutFile "$dest\statusline.ps1"
   ```

2. Edit `%USERPROFILE%\.copilot\settings.json` and add (or merge) the following. **All three blocks are required** — see the next section:

   ```json
   {
     "experimental": true,
     "statusLine": {
       "type": "command",
       "command": "C:\\Users\\<your-user>\\.copilot\\statusline.cmd",
       "padding": 1
     },
     "feature_flags": {
       "enabled": ["STATUS_LINE"]
     }
   }
   ```

3. In Copilot CLI, run `/statusline` and pick **Custom**, then `/restart`.

## What made the spawn work on Windows

On Windows + Copilot CLI 1.0.44, a clean PowerShell port that ran perfectly in standalone tests produced **no output at all** in the CLI — no error, no entry in `~/.copilot/logs/`, just a blank statusline. Two changes together fixed it. We did not isolate which one is strictly required, so both are documented here:

### 1. Add `feature_flags.enabled: ["STATUS_LINE"]` to `settings.json`

`experimental: true` alone was not enough in our setup. Adding the explicit feature flag was part of the change that made `statusLine.type: "command"` start spawning. As a quick sanity check, `type: "static"` always renders regardless: if a literal static string shows but a command does not, the spawn path itself is the problem.

### 2. Use a `.cmd` wrapper instead of an inline `powershell.exe -File ...`

A two-line `.cmd` wrapper that calls `pwsh -File ...` is more reliable on Windows than putting the interpreter, flags, and script path directly in the JSON `command` field — argument parsing and stdin redirection both behave better. This recommendation also matches Scott Hanselman's [Copilot CLI Oh My Posh statusline gist](https://gist.github.com/shanselman/9623ac74888a07ba82f63f5310fda11b).

## PowerShell port traps that bite

For anyone porting their own `.sh` script to PowerShell, watch out for these (the included `statusline.ps1` already handles all of them):

1. **Save the `.ps1` file with a UTF-8 BOM** (`EF BB BF`). `powershell.exe` reads `.ps1` as ANSI/CP1252 unless the BOM is present, which corrupts Unicode glyphs (`█ ░ ↻ ·`) at parse time and produces "Unexpected token" errors. Copilot CLI then sees empty stdout and renders nothing.
2. **`ConvertFrom-Json -Depth`** was added in PowerShell 6 — it throws in 5.1 and silently nulls the parsed status object. Omit `-Depth`.
3. **`$x = if (...) { ... } else { ... }`** (using `if` as an expression) was added in PowerShell 7 — fails to parse in 5.1. Use plain `if` blocks that assign inside.
4. **Force UTF-8 output encoding** explicitly at the top of the script:

   ```powershell
   $utf8 = New-Object System.Text.UTF8Encoding $false
   [Console]::OutputEncoding = $utf8
   $OutputEncoding           = $utf8
   ```

   Otherwise Windows defaults to OEM (CP437/850), which mangles UTF-8 between the script and the CLI.
5. **Cold `az account show` and `gh auth status`** can each take 1–3 seconds. Combined with PowerShell startup that easily exceeds the ~10 s statusline timeout. Cache results or run lookups in `Start-Job` and read from the cache on the hot path.

## Troubleshooting

- **Nothing renders, no error.** Confirm `feature_flags.enabled: ["STATUS_LINE"]` is present in `settings.json` and `experimental: true` is set. Then `/restart`.
- **Quick sanity check.** Temporarily set `"statusLine": { "type": "static", "value": "HELLO" }`. If `HELLO` renders, the config is being read and you have the *spawning* problem above. If `HELLO` does not render, fix `experimental`/`feature_flags` first.
- **Test the script standalone.**

  ```powershell
  Get-Content payload.json | & "$env:USERPROFILE\.copilot\statusline.cmd"
  ```

  where `payload.json` is anything Copilot CLI would pipe in, for example:

  ```json
  {"cwd":"C:\\Users\\you","context_window":{"current_context_tokens":42137,"displayed_context_limit":200000,"current_context_used_percentage":21.07},"cost":{"total_duration_ms":125300,"total_lines_added":17,"total_lines_removed":4}}
  ```

- **Garbled glyphs.** Verify the `.ps1` has a UTF-8 BOM (`(Get-Content ... -Encoding Byte -TotalCount 3)` should print `239 187 191`).
- **`pwsh: command not found`** in the wrapper. Either install PowerShell 7 (`winget install Microsoft.PowerShell`) or change `pwsh` to `powershell.exe` in `statusline.cmd`.
- **`tokens<30d:` segment never appears.** `ai-engineering-fluency usage` takes ~60 s on a cold run, which exceeds Copilot CLI's ~10 s statusline timeout, so the cache is never auto-populated. Pre-warm it once by running the command directly and copying the output into the cache file:

  ```powershell
  $cache = Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'copilot-statusline\ai-fluency-usage-v1'
  New-Item -ItemType Directory -Force (Split-Path $cache) | Out-Null
  ai-engineering-fluency usage | Out-String |
      ForEach-Object { [System.IO.File]::WriteAllText($cache, $_, [System.Text.UTF8Encoding]::new($false)) }
  ```

  After that, the script refreshes the cache transparently every 30 minutes. Note the cache directory is `%LOCALAPPDATA%\copilot-statusline\` (not `~/.cache/...` like on macOS) — that is what `[Environment]::GetFolderPath('LocalApplicationData')` resolves to on Windows.
- **Logs.** Copilot CLI writes to `%USERPROFILE%\.copilot\logs\`. Statusline-spawning failures do **not** appear there on Windows — they are silent. Use the static-statusline trick above to bisect.

## Credits

- [@Remc0000](https://github.com/Remc0000) — Windows port (this folder). Without his fight with `pwsh`, `cmd.exe`, `%LOCALAPPDATA%`, UTF-8 BOMs, hidden feature flags, and silent spawn failures, nobody could ever use this on Windows.
- [@shanselman](https://github.com/shanselman) — the [`.cmd` wrapper / `feature_flags` tip](https://gist.github.com/shanselman/9623ac74888a07ba82f63f5310fda11b) that unblocked the spawn path.
- [@pascalvanderheiden](https://github.com/pascalvanderheiden) — the original macOS `statusline.sh` this port is based on.
