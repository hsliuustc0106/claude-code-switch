# Claude Switch

[![License](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![GitHub stars](https://img.shields.io/github/stars/foreveryh/claude-code-switch.svg)](https://github.com/foreveryh/claude-code-switch/stargazers)
[![GitHub issues](https://img.shields.io/github/issues/foreveryh/claude-code-switch.svg)](https://github.com/foreveryh/claude-code-switch/issues)

Switch Claude Code between AI providers with one command.

**中文文档 | [English Documentation](#english-documentation)**

---

## English Documentation

### Quick Start

```bash
# 1. Install
curl -fsSL https://raw.githubusercontent.com/foreveryh/claude-code-switch/main/install.sh | bash

# 2. Reload shell
source ~/.zshrc  # or ~/.bashrc

# 3. Run the setup wizard (interactive)
claude-switch setup

# 4. Start using Claude Code
claude-launch glm        # launch with GLM
claude-launch open glm   # launch with GLM via OpenRouter

# Add more providers anytime
claude-switch setup
```

### What the Wizard Does

The `claude-switch setup` wizard walks you through:
1. **Provider selection** - Choose from GLM, OpenRouter, or manual config
2. **API key input** - Enter your key with format validation
3. **Save & confirm** - Configuration saved, ready to use

Run `claude-switch setup` again to add more providers.

---

### Installation

#### Quick Install (Recommended)
```bash
curl -fsSL https://raw.githubusercontent.com/foreveryh/claude-code-switch/main/install.sh | bash
source ~/.zshrc  # or ~/.bashrc
```

#### Local Install
```bash
git clone https://github.com/foreveryh/claude-code-switch.git
cd claude-code-switch
./install.sh
source ~/.zshrc
```

#### Install Modes

| Mode | Command | Use Case |
|------|---------|----------|
| **User** (default) | `./install.sh` | Personal use, available everywhere |
| **System** | `./install.sh --system` | Shared machine, all users |
| **Project** | `./install.sh --project` | Project-specific, isolated setup |

#### Install Options
```bash
./install.sh --no-rc           # Skip shell rc injection
./install.sh --cleanup-legacy  # Remove old installation
./install.sh --help            # Show all options
```

#### Uninstall
```bash
./uninstall.sh
```

---

### First-Time Setup

#### Method 1: Interactive Wizard (Recommended)

```bash
claude-switch setup
```

The wizard guides you through:
1. Select your primary AI provider (GLM, OpenRouter, or manual)
2. Enter your API key (with format validation)
3. Configuration saved automatically

**Direct setup** (skip menu):
```bash
claude-switch setup --provider=glm
```

#### Method 2: Manual Configuration

```bash
claude-switch config    # Opens ~/.claude_switch_config in your editor
```

Add your API keys:

```bash
# GLM (Zhipu)
GLM_API_KEY=your-glm-api-key

# OpenRouter
OPENROUTER_API_KEY=your-openrouter-api-key
```

#### Verify Setup

```bash
claude-switch status    # Check current configuration (keys are masked)
```

---

### Basic Usage

#### Switch Provider (in current shell)
```bash
eval "$(claude-switch glm)"        # GLM (direct)
eval "$(claude-switch open glm)"   # GLM via OpenRouter
```

#### Switch + Launch Claude Code
```bash
claude-launch glm        # Switch to GLM, then launch
claude-launch open glm   # Via OpenRouter
```

#### Check Status
```bash
claude-switch status             # Show current model and API key status
claude-switch current-account    # Show current Claude Pro account
```

#### Update Config
When model IDs change in new versions, update your config:
```bash
claude-switch update-config      # Update outdated model IDs to latest defaults
```

#### Get Help
```bash
claude-switch help               # Show all commands
claude-launch                    # Show claude-launch usage (no args)
```

---

### Providers Reference

#### Direct Providers (API Key Required)

| Provider | Command | Base URL |
|----------|---------|----------|
| GLM | `claude-switch glm` | `api.z.ai/api/anthropic` |

> **GLM Coding Plan**: [bigmodel.cn/glm-coding](https://www.bigmodel.cn/glm-coding?ic=5XMIOZPPXB)

#### OpenRouter

Access GLM via OpenRouter:

```bash
claude-switch open              # Show help
claude-switch open glm          # GLM via OpenRouter
```

---

### Advanced Features

#### Claude Pro Account Management
Switch between multiple Claude Pro subscriptions:

```bash
# Save current logged-in account
claude-switch save-account work

# Switch to saved account
claude-switch switch-account work

# List all saved accounts
claude-switch list-accounts

# Show current account
claude-switch current-account

# Delete saved account
claude-switch delete-account work
```

#### User-Level Settings (Highest Priority)
Write settings directly to `~/.claude/settings.json`. This overrides everything including environment variables.

```bash
# Set provider at user level
claude-switch user glm      # GLM for all projects

# Reset to environment variable control
claude-switch user reset     # Remove settings, use env vars instead
```

**When to use:**
- You want a persistent default that survives shell restarts
- Environment variables are being overridden by something else

#### Project-Only Override
Override settings for a specific project (keeps global settings intact):

```bash
# In your project directory
claude-switch project glm    # Use GLM for this project only
claude-switch project reset  # Remove project override
```

This creates/removes `.claude/settings.local.json` in the current project.

#### Launch with Account
```bash
claude-launch work           # Switch to 'work' account, then launch
claude-launch glm:work       # Switch to 'work' account + use GLM
```

---

### Configuration

#### Priority Order (highest to lowest)
1. `~/.claude/settings.json` (env section) - User-level settings
2. `.claude/settings.local.json` - Project-level settings
3. `~/.claude_switch_config` file - **Always reloads on each command**
4. Environment variables (only used if config value is a placeholder)

#### Config File Location
```
~/.claude_switch_config
```

#### Full Config Example
```bash
# Language (en or zh)
CLAUDE_SWITCH_LANGUAGE=en

# API Keys
GLM_API_KEY=your-glm-api-key
OPENROUTER_API_KEY=your-openrouter-api-key

# Model ID Override (optional)
GLM_MODEL=glm-5
```

---

### Without RC Injection

If you installed with `--no-rc` or want to use from cloned repo:

```bash
# Switch model (apply env vars to current shell)
eval "$(claude-switch glm)"
eval "$(./switch-lib.sh glm)"

# Or use the wrapper scripts directly
./claude-switch glm         # Just prints exports
./claude-launch glm         # Switch + launch
```

---

### Notes

- **7 env vars exported per provider**: `ANTHROPIC_BASE_URL`, `ANTHROPIC_AUTH_TOKEN`, `ANTHROPIC_MODEL`, `ANTHROPIC_DEFAULT_OPUS_MODEL`, `ANTHROPIC_DEFAULT_SONNET_MODEL`, `ANTHROPIC_DEFAULT_HAIKU_MODEL`, `CLAUDE_CODE_SUBAGENT_MODEL`
- **OpenRouter**: Requires explicit `claude-switch open <provider>` command
- **Project override**: Only affects the current project via `.claude/settings.local.json`

---

### Troubleshooting

For common issues and solutions, see [docs/troubleshooting.md](docs/troubleshooting.md).

---

### Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

---

### License

MIT License - see [LICENSE](LICENSE) for details.

---

## 中文文档

### 快速开始

```bash
# 1. 安装
curl -fsSL https://raw.githubusercontent.com/foreveryh/claude-code-switch/main/install.sh | bash

# 2. 重新加载 shell
source ~/.zshrc  # 或 ~/.bashrc

# 3. 运行设置向导（交互式）
claude-switch setup

# 4. 开始使用 Claude Code
claude-launch glm        # 使用 GLM 启动
claude-launch open glm   # 通过 OpenRouter 使用 GLM 启动

# 随时添加更多提供商
claude-switch setup
```

### 安装

#### 快速安装（推荐）
```bash
curl -fsSL https://raw.githubusercontent.com/foreveryh/claude-code-switch/main/install.sh | bash
source ~/.zshrc  # 或 ~/.bashrc
```

#### 本地安装
```bash
git clone https://github.com/foreveryh/claude-code-switch.git
cd claude-code-switch
./install.sh
source ~/.zshrc
```

### 基本用法

#### 切换提供商（在当前 shell）
```bash
eval "$(claude-switch glm)"        # GLM（直接）
eval "$(claude-switch open glm)"   # GLM（通过 OpenRouter）
```

#### 切换并启动 Claude Code
```bash
claude-launch glm        # 切换到 GLM，然后启动
claude-launch open glm   # 通过 OpenRouter
```

#### 查看状态
```bash
claude-switch status             # 显示当前模型和 API 密钥状态
claude-switch current-account    # 显示当前 Claude Pro 账号
```

### 提供商参考

#### 直接提供商（需要 API 密钥）

| 提供商 | 命令 | 基础 URL |
|----------|---------|----------|
| GLM | `claude-switch glm` | `api.z.ai/api/anthropic` |

#### OpenRouter

通过 OpenRouter 访问 GLM：

```bash
claude-switch open              # 显示帮助
claude-switch open glm          # GLM 通过 OpenRouter
```

### 配置

#### 配置文件位置
```
~/.claude_switch_config
```

#### 配置示例
```bash
# 语言（en 或 zh）
CLAUDE_SWITCH_LANGUAGE=zh

# API 密钥
GLM_API_KEY=your-glm-api-key
OPENROUTER_API_KEY=your-openrouter-api-key

# 模型 ID 覆盖（可选）
GLM_MODEL=glm-5
```

---

### License

MIT License - 详见 [LICENSE](LICENSE)
