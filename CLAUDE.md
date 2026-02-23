# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Conversation Style

**Roleplay Setting:**
- **User (主公/Lord)**: The master who gives commands and makes decisions
- **Claude (臣子/Subject)**: The loyal assistant who serves and advises

When interacting, maintain this relationship dynamics:
- Be respectful and attentive
- Provide clear, actionable advice
- Wait for the lord's decisions
- Use polite, formal tone when appropriate
- Be ready to step back when dismissed

## Project Overview

**Claude Switch** is a simplified Bash-based CLI that switches Claude Code between AI providers by exporting Anthropic-compatible environment variables.

**Supported Providers:**
- **GLM (direct)**: Zhipu GLM-5 (`glm` command)
- **OpenRouter**: Access GLM via OpenRouter (`open <provider>` command)

## Repository Structure

```
claude-switch/
├── README.md                     # Unified user documentation
├── CHANGELOG.md                  # Version history
├── LICENSE
├── CLAUDE.md                     # This file - AI assistant instructions
├── claude-switch                 # Main command wrapper
├── claude-launch                 # Launcher command
├── switch-lib.sh                 # Core library
├── install.sh                    # Unified installer
├── uninstall.sh                  # Uninstaller
├── locale/                       # i18n (was lang/)
│   ├── en.json
│   └── zh.json
└── docs/                         # User-facing documentation
    └── troubleshooting.md        # Troubleshooting guide
```

## Key Architecture & Design Patterns

### 1) Two usage modes
- **Direct execution:** `./claude-switch ...` / `./claude-launch ...` (no install)
- **Installed functions:** `claude-switch ...` / `claude-launch ...` (after `./install.sh`)
  - Installer copies `switch-lib.sh` + `locale/` into `${XDG_DATA_HOME:-$HOME/.local/share}/claude-switch`
  - Optional rc injection for `claude-switch()` / `claude-launch()` functions

### 2) Configuration hierarchy
Priority order:
1. Environment variables
2. `~/.claude_switch_config` (created on first run)
3. Built-in defaults

Key function: `is_effectively_set()` treats placeholder values as unset.

### 3) Environment export pattern
`emit_env_exports()` prints export statements which are `eval`'d by the caller:
```bash
export ANTHROPIC_BASE_URL=...
export ANTHROPIC_AUTH_TOKEN=...
export ANTHROPIC_MODEL=...
export ANTHROPIC_DEFAULT_SONNET_MODEL=...
export ANTHROPIC_DEFAULT_OPUS_MODEL=...
export ANTHROPIC_DEFAULT_HAIKU_MODEL=...
export CLAUDE_CODE_SUBAGENT_MODEL=...
```

### 4) OpenRouter (explicit)
OpenRouter is not a fallback. Use:
- `claude-switch open <provider>`

`emit_openrouter_exports()` sets:
- Base URL: `https://openrouter.ai/api`
- `ANTHROPIC_AUTH_TOKEN=$OPENROUTER_API_KEY`
- `ANTHROPIC_API_KEY=""` (avoid conflicts)

### 5) Project-only override (Quotio-friendly)
`claude-switch project glm` writes `.claude/settings.local.json` so GLM applies only to the current project.

## Common Commands & Workflows

### Installation
```bash
./install.sh
source ~/.zshrc
```

### Switch in current shell
```bash
eval "$(claude-switch glm)"
```

### Launch Claude Code
```bash
claude-launch glm
claude-launch open glm
```

### Account management (Claude Pro)
```bash
claude-switch save-account work
claude-switch switch-account work
claude-switch list-accounts
claude-switch delete-account work
claude-switch current-account
```

## Code Organization in switch-lib.sh

Key functions:
- `load_translations()` / `load_config()` / `is_effectively_set()`
- `emit_env_exports()` (provider switching - only GLM)
- `emit_openrouter_exports()` (OpenRouter - only GLM)
- `project_write_glm_settings()` / `project_reset_settings()`
- `show_status()` / `show_help()`
- `main()` (command routing)

## Adding a New Provider

Since this project is simplified to only GLM and OpenRouter, adding new providers requires:
1. Add provider branch to `emit_env_exports()` in switch-lib.sh
2. Add provider branch to `emit_openrouter_exports()` for OpenRouter access
3. Add to help text and README
4. Add defaults to config template (`load_config()`)
5. Update `get_provider_config()` function
6. Update `show_status()` provider detection
7. Update setup wizard (`show_provider_menu()`, `validate_api_key()`, etc.)

## Security Notes

- Token masking in `claude-switch status`
- Recommend `chmod 600 ~/.claude_switch_config`
- Environment vars override config file (good for CI)
