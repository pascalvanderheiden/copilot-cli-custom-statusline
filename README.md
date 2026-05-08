# GitHub Copilot CLI custom statusline

This repository shows how to use a custom GitHub Copilot CLI statusline on macOS.

![Example Copilot CLI statusline](assets/statusline-example.png)

## What it shows

The statusline displays useful context at the bottom of Copilot CLI:

```text
option+space to record · ↻ 21:57:15 · az: user@example.com · gh: username · tokens<30d: 898.9K · squad: repo · openspec: change 47%
```

Segments only appear when their related tool or project marker is available.

## Prerequisites

Install the tools and dependencies for the segments you want to see:

| Segment | Tool | Install |
| --- | --- | --- |
| Statusline support | [GitHub Copilot CLI](https://docs.github.com/en/copilot/concepts/agents/about-copilot-cli) | `brew install --cask copilot-cli` |
| Azure account | [Azure CLI](https://learn.microsoft.com/cli/azure/install-azure-cli) | `brew install azure-cli` |
| GitHub account | [GitHub CLI](https://cli.github.com/) | `brew install gh` |
| Token usage | [AI Engineering Fluency CLI](https://github.com/rajbos/ai-engineering-fluency/blob/main/docs/cli/README.md) | `npm install -g @rajbos/ai-engineering-fluency` |
| Spec Kit dependency | [uv](https://docs.astral.sh/uv/) | `brew install uv` |
| OpenSpec progress | [OpenSpec](https://github.com/Fission-AI/OpenSpec/) | `npm install -g @fission-ai/openspec@latest` |
| Spec Kit progress | [Spec Kit](https://github.com/github/spec-kit) | `uv tool install specify-cli --from git+https://github.com/github/spec-kit.git` |
| Squad context | [Squad CLI](https://www.npmjs.com/package/@bradygaster/squad-cli) | `npm install -g @bradygaster/squad-cli` |
| Voice recording hint | [Handy](https://github.com/cjpais/Handy) | `brew install --cask handy` |

You also need `jq` because `statusline.sh` parses Copilot CLI status JSON:

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

## Setup

Download the script file:

```bash
mkdir -p ~/.copilot
curl -fsSL https://raw.githubusercontent.com/pascalvanderheiden/copilot-cli-custom-statusline/main/statusline.sh -o ~/.copilot/statusline.sh
chmod +x ~/.copilot/statusline.sh
```

Edit `~/.copilot/settings.json` and add or merge:

```json
{
  "experimental": true,
  "statusLine": {
    "type": "command",
    "command": "~/.copilot/statusline.sh"
  }
}
```

Verify the script by running it directly:

```bash
~/.copilot/statusline.sh
```

## Segment explanation

| Segment | Meaning |
| --- | --- |
| `option+space to record` | Handy voice-recording shortcut reminder. |
| `↻ HH:MM:SS` | Time when the statusline was generated. |
| `az: ...` | Signed-in Azure CLI account from `az account show`. |
| `gh: ...` | Active GitHub CLI account from `gh auth status`. |
| `tokens<30d: ...` | Last 30 days token usage from `ai-engineering-fluency usage`. |
| `squad: ...` | Active Squad context when `.squad` exists in the project. |
| `openspec: ...` | OpenSpec changes and task completion when `openspec` or `.openspec` exists. |
| `spec-kit: ...` | Spec Kit state or task completion when `.specify` or `specs/` exists. |

## Troubleshooting

- If a segment is missing, install or authenticate the related CLI.
- If the statusline does not load, check `chmod +x ~/.copilot/statusline.sh`.
- If `~` is not expanded in `settings.json`, use the full path, for example `/Users/your-user/.copilot/statusline.sh`.
- If `settings.json` stops loading, validate that commas around the `statusLine` block are correct.
- Restart Copilot CLI after changing the script or settings.
