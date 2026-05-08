# GitHub Copilot CLI custom statusline

This repository shows how to use a custom GitHub Copilot CLI statusline on macOS and Windows.

![Example Copilot CLI statusline](assets/statusline-example.png)

## What it shows

The statusline displays useful context at the bottom of Copilot CLI:

```text
option+space to record · ↻ 21:57:15 · az: user@example.com · gh: username · tokens<30d: 898.9K · squad: repo · openspec: change 47%
```

Segments only appear when their related tool or project marker is available.

## Prerequisites

Install the tools and dependencies for the segments you want to see:

| Segment | Tool | Windows | Mac |
| --- | --- | --- | --- |
| Azure account | [Azure CLI](https://learn.microsoft.com/cli/azure/install-azure-cli) | `winget install --id Microsoft.AzureCLI` | `brew install azure-cli` |
| GitHub account | [GitHub CLI](https://cli.github.com/) | `winget install --id GitHub.cli` | `brew install gh` |
| Token usage | [AI Engineering Fluency CLI](https://github.com/rajbos/ai-engineering-fluency/blob/main/docs/cli/README.md) | `npm install -g @rajbos/ai-engineering-fluency` | `npm install -g @rajbos/ai-engineering-fluency` |
| Spec Kit dependency | [uv](https://docs.astral.sh/uv/) | `winget install --id astral-sh.uv` | `brew install uv` |
| OpenSpec progress | [OpenSpec](https://github.com/Fission-AI/OpenSpec/) | `npm install -g @fission-ai/openspec@latest` | `npm install -g @fission-ai/openspec@latest` |
| Spec Kit progress | [Spec Kit](https://github.com/github/spec-kit) | `uv tool install specify-cli --from git+https://github.com/github/spec-kit.git` | `uv tool install specify-cli --from git+https://github.com/github/spec-kit.git` |
| Squad context | [Squad CLI](https://www.npmjs.com/package/@bradygaster/squad-cli) | `npm install -g @bradygaster/squad-cli` | `npm install -g @bradygaster/squad-cli` |
| Voice recording hint | [Handy](https://github.com/cjpais/Handy) | `winget install --id cjpais.Handy` | `brew install --cask handy` |

macOS users also need `jq` because `statusline.sh` parses Copilot CLI status JSON:

```bash
brew install jq
```

Authenticate the CLIs you want to use:

```bash
az login
gh auth login
```

## Step 1: enable the statusline

In GitHub Copilot CLI, run:

```text
/statusline
```

Enable the custom statusline when prompted.

## macOS setup

Download the script file:

```bash
mkdir -p ~/.copilot
curl -fsSL https://raw.githubusercontent.com/pascalvanderheiden/copilot-cli-custom-statusline/main/statusline.sh -o ~/.copilot/statusline.sh
chmod +x ~/.copilot/statusline.sh
```

Edit `~/.copilot/settings.json` and add:

```json
"statusLine": {
  "type": "command",
  "command": "~/.copilot/statusline.sh"
}
```

Verify the script by running it directly:

```bash
~/.copilot/statusline.sh
```

## Windows setup

Download the script files:

```powershell
$copilotDir = Join-Path $HOME '.copilot'
New-Item -ItemType Directory -Force $copilotDir
Invoke-WebRequest `
  -Uri 'https://raw.githubusercontent.com/pascalvanderheiden/copilot-cli-custom-statusline/main/statusline.ps1' `
  -OutFile (Join-Path $copilotDir 'statusline.ps1')
Invoke-WebRequest `
  -Uri 'https://raw.githubusercontent.com/pascalvanderheiden/copilot-cli-custom-statusline/main/statusline.cmd' `
  -OutFile (Join-Path $copilotDir 'statusline.cmd')
```

The `statusline.cmd` wrapper is included in this repository. Why the wrapper? In testing, Copilot's `statusLine.command` setting was most reliable when it pointed at a command/script path. Putting `pwsh -File ...` directly in the JSON setting can be less reliable on Windows. The wrapper also preserves stdin, which is how Copilot sends the payload.

Edit:

```text
%USERPROFILE%\.copilot\settings.json
```

Add or merge this:

```json
{
  "statusLine": {
    "type": "command",
    "command": "%USERPROFILE%\\.copilot\\statusline.cmd",
    "padding": 1
  },
  "feature_flags": {
    "enabled": [
      "STATUS_LINE"
    ]
  },
  "experimental": true
}
```

Verify the script by running it directly:

```cmd
%USERPROFILE%\.copilot\statusline.cmd
```

## Segment explanation

| Segment | Meaning |
| --- | --- |
| `option+space to record` / `ctrl+space to record` | Handy voice-recording shortcut reminder (macOS / Windows defaults). |
| `↻ HH:MM:SS` | Time when the statusline was generated. |
| `az: ...` | Signed-in Azure CLI account from `az account show`. |
| `gh: ...` | Active GitHub CLI account from `gh auth status`. |
| `tokens<30d: ...` | Last 30 days token usage from `ai-engineering-fluency usage`. |
| `squad: ...` | Active Squad context when `.squad` exists in the project. |
| `openspec: ...` | OpenSpec changes and task completion when `openspec` or `.openspec` exists. |
| `spec-kit: ...` | Spec Kit state or task completion when `.specify` or `specs/` exists. |

## Troubleshooting

- If a segment is missing, install or authenticate the related CLI.
- If the statusline does not load on macOS, check `chmod +x ~/.copilot/statusline.sh`.
- If Windows blocks the script, keep the documented `-ExecutionPolicy Bypass` command or allow local scripts in PowerShell.
- If `settings.json` stops loading, validate that commas around the `statusLine` block are correct.
- Restart Copilot CLI after changing the script or settings.

### Windows: the line does not show up

Check:

- `STATUS_LINE` is enabled in `feature_flags.enabled`.
- `statusLine.command` points to the `.cmd` wrapper.
- You restarted Copilot CLI after changing settings.
- The command works with the sample payload.

If it works manually but not in Copilot, use the wrapper path in `settings.json`:

```json
"command": "%USERPROFILE%\\.copilot\\statusline.cmd"
```

Avoid putting a full command with arguments directly in the setting.
