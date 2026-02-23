#!/bin/bash
############################################################
# Claude Switch - AI Model Switcher
# ---------------------------------------------------------
# Simplified to support GLM and OpenRouter only
# 作者: Peng
# 版本: 3.0.0
############################################################

# 脚本颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# 版本号
CLAUDE_SWITCH_VERSION='3.0.0'

# 颜色控制（用于账号管理命令的输出）
# 自动检测：如果stdout不是终端（被管道或eval捕获），则禁用颜色
# 这修复了 issue #8: (eval):1: bad pattern: ^[[1
if [[ ! -t 1 ]]; then
    NO_COLOR=true
else
    NO_COLOR=false
fi

# 根据NO_COLOR设置颜色（账号管理函数使用）
set_no_color() {
    if [[ "$NO_COLOR" == "true" ]]; then
        RED=''
        GREEN=''
        YELLOW=''
        BLUE=''
        NC=''
    fi
}

# 如果检测到需要禁用颜色，立即应用
if [[ "$NO_COLOR" == "true" ]]; then
    set_no_color
fi

# 检测操作系统
detect_os() {
    case "$(uname -s)" in
        Darwin*)
            echo "macos"
            ;;
        Linux*)
            echo "linux"
            ;;
        *)
            echo "unknown"
            ;;
    esac
}

OS_TYPE=$(detect_os)

# ============================================
# CPU Architecture Detection
# ============================================
detect_arch() {
    case "$(uname -m)" in
        x86_64|amd64)    echo "x64" ;;
        i386|i686)       echo "x86" ;;
        aarch64|arm64)   echo "arm64" ;;
        armv7l)          echo "arm" ;;
        *)               echo "unknown" ;;
    esac
}

ARCH_TYPE=$(detect_arch)

# ============================================
# Platform Abstraction Layer
# Hides platform-specific differences
# ============================================

# Cross-platform base64 encoding (no line breaks)
platform::base64_encode() {
    if [[ "$OS_TYPE" == "macos" ]]; then
        base64
    else
        if base64 --help 2>&1 | grep -q -- '-w'; then
            base64 -w 0
        else
            base64 | tr -d '\n'
        fi
    fi
}

# Cross-platform base64 decoding
platform::base64_decode() {
    base64 -d
}

# Cross-platform sed in-place edit
# Usage: platform::sed_inplace "pattern" file
platform::sed_inplace() {
    local pattern="$1"
    local file="$2"
    if [[ "$OS_TYPE" == "macos" ]]; then
        sed -i '' "$pattern" "$file"
    else
        sed -i "$pattern" "$file"
    fi
}

# Cross-platform epoch to readable date
platform::date_format() {
    local seconds="$1"
    if [[ "$OS_TYPE" == "macos" ]]; then
        date -r "$seconds" "+%Y-%m-%d %H:%M" 2>/dev/null || echo "Unknown"
    else
        date -d "@$seconds" "+%Y-%m-%d %H:%M" 2>/dev/null || echo "Unknown"
    fi
}

# Get credentials from platform-specific storage
platform::credentials_read() {
    case "$OS_TYPE" in
        macos)  read_macos_credentials ;;
        linux)  read_linux_credentials ;;
        *)      return 1 ;;
    esac
}

# Write credentials to platform-specific storage
platform::credentials_write() {
    local credentials="$1"
    case "$OS_TYPE" in
        macos)  write_macos_credentials "$credentials" ;;
        linux)  write_linux_credentials "$credentials" ;;
        *)      return 1 ;;
    esac
}

# Get platform-specific default editor command
platform::get_editor() {
    if command -v cursor >/dev/null 2>&1; then
        echo "cursor"
    elif command -v code >/dev/null 2>&1; then
        echo "code"
    elif [[ "$OS_TYPE" == "macos" ]] && command -v open >/dev/null 2>&1; then
        echo "open"
    elif command -v vim >/dev/null 2>&1; then
        echo "vim"
    elif command -v nano >/dev/null 2>&1; then
        echo "nano"
    else
        echo ""
    fi
}

# 配置文件路径
CONFIG_FILE="$HOME/.claude_switch_config"
ACCOUNTS_FILE="$HOME/.claude_switch_accounts"
CLAUDE_CREDENTIALS_FILE="$HOME/.claude/.credentials.json"

# Keychain service name (override with CLAUDE_SWITCH_KEYCHAIN_SERVICE)
KEYCHAIN_SERVICE="${CLAUDE_SWITCH_KEYCHAIN_SERVICE:-Claude Code-credentials}"

# 多语言支持
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
LANG_DIR="$SCRIPT_DIR/locale"

# 加载翻译
load_translations() {
    local lang_code="${1:-en}"
    local lang_file="$LANG_DIR/${lang_code}.json"

    # 如果语言文件不存在，默认使用英语
    if [[ ! -f "$lang_file" ]]; then
        lang_code="en"
        lang_file="$LANG_DIR/en.json"
    fi

    # 如果英语文件也不存在，使用内置英文
    if [[ ! -f "$lang_file" ]]; then
        return 0
    fi

    # 清理现有翻译变量
    unset $(set | grep '^TRANS_' | LC_ALL=C cut -d= -f1) 2>/dev/null || true

    # 读取JSON文件并解析到变量
    if [[ -f "$lang_file" ]]; then
        local temp_file=$(mktemp)
        # 提取键值对到临时文件，使用更健壮的方法
        grep -o '"[^"]*":[[:space:]]*"[^"]*"' "$lang_file" | sed 's/^"\([^"]*\)":[[:space:]]*"\([^"]*\)"$/\1|\2/' > "$temp_file"

        # 读取临时文件并设置变量（使用TRANS_前缀）
        while IFS='|' read -r key value; do
            if [[ -n "$key" && -n "$value" ]]; then
                # 处理转义字符
                value="${value//\\\"/\"}"
                value="${value//\\\\/\\}"
                # 使用eval设置动态变量名
                eval "TRANS_${key}=\"\$value\""
            fi
        done < "$temp_file"

        rm -f "$temp_file"
    fi
}

# 获取翻译文本
t() {
    local key="$1"
    local default="${2:-$key}"
    local var_name="TRANS_${key}"
    local value
    eval "value=\"\${${var_name}:-}\""
    echo "${value:-$default}"
}

# 检测系统语言
detect_language() {
    # 首先检查环境变量LANG
    local sys_lang="${LANG:-}"
    if [[ "$sys_lang" =~ ^zh ]]; then
        echo "zh"
    else
        echo "en"
    fi
}

# 智能加载配置：环境变量优先，配置文件补充
load_config() {
    # 初始化语言
    local lang_preference="${CLAUDE_SWITCH_LANGUAGE:-$(detect_language)}"
    load_translations "$lang_preference"

    # 创建配置文件（如果不存在）
    if [[ ! -f "$CONFIG_FILE" ]]; then
        cat > "$CONFIG_FILE" << 'EOF'
# Claude Switch 配置文件
# 请替换为你的实际API密钥
# 注意：环境变量中的API密钥优先级高于此文件

# 语言设置 (en: English, zh: 中文)
CLAUDE_SWITCH_LANGUAGE=en

# GLM (智谱清言)
GLM_API_KEY=your-glm-api-key

# OpenRouter
OPENROUTER_API_KEY=your-openrouter-api-key

# —— 可选：模型ID覆盖（不设置则使用下方默认）——
GLM_MODEL=glm-5

EOF
        echo -e "${YELLOW}⚠️  $(t 'config_created'): $CONFIG_FILE${NC}" >&2
        echo -e "${YELLOW}   $(t 'edit_file_to_add_keys')${NC}" >&2
        echo -e "${GREEN}🚀 Using default experience keys for now...${NC}" >&2
        # Don't return 1 - continue with default fallback keys
    fi

    # 首先读取语言设置
    if [[ -f "$CONFIG_FILE" ]]; then
        local config_lang
        config_lang=$(grep -E "^[[:space:]]*CLAUDE_SWITCH_LANGUAGE[[:space:]]*=" "$CONFIG_FILE" 2>/dev/null | head -1 | LC_ALL=C cut -d'=' -f2- | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')
        if [[ -n "$config_lang" && -z "$CLAUDE_SWITCH_LANGUAGE" ]]; then
            export CLAUDE_SWITCH_LANGUAGE="$config_lang"
            lang_preference="$config_lang"
            load_translations "$lang_preference"
        fi
    fi

    # 智能加载：只有环境变量未设置的键才从配置文件读取
    local temp_file=$(mktemp)
    local raw
    while IFS= read -r raw || [[ -n "$raw" ]]; do
        # 去掉回车、去掉行内注释并修剪两端空白
        raw=${raw%$'\r'}
        # 跳过注释和空行
        [[ "$raw" =~ ^[[:space:]]*# ]] && continue
        [[ -z "$raw" ]] && continue
        # 删除行内注释（从第一个 # 起）
        local line="${raw%%#*}"
        # 去掉首尾空白
        line=$(echo "$line" | sed -E 's/^[[:space:]]*//; s/[[:space:]]*$//')
        [[ -z "$line" ]] && continue
        
        # 解析 export KEY=VALUE 或 KEY=VALUE
        if [[ "$line" =~ ^[[:space:]]*(export[[:space:]]+)?([A-Za-z_][A-Za-z0-9_]*)[[:space:]]*=(.*)$ ]]; then
            local key="${BASH_REMATCH[2]}"
            local value="${BASH_REMATCH[3]}"
            # 去掉首尾空白
            value=$(echo "$value" | sed -E 's/^[[:space:]]*//; s/[[:space:]]*$//')
            # 检查配置文件的值是否为占位符
            local lower_value
            lower_value=$(printf '%s' "$value" | tr '[:upper:]' '[:lower:]')
            local is_config_placeholder=false
            if [[ "$lower_value" == *"your"* && "$lower_value" == *"api"* && "$lower_value" == *"key"* ]]; then
                is_config_placeholder=true
            fi
            # 配置文件总是覆盖，除非配置值是占位符
            if [[ -n "$key" && "$is_config_placeholder" == "false" ]]; then
                echo "export $key=$value" >> "$temp_file"
            fi
        fi
    done < "$CONFIG_FILE"
    
    # 执行临时文件中的export语句
    if [[ -s "$temp_file" ]]; then
        source "$temp_file"
    fi
    rm -f "$temp_file"
}

# 创建默认配置文件
create_default_config() {
    cat > "$CONFIG_FILE" << 'EOF'
# Claude Switch 配置文件
# 请替换为你的实际API密钥
# 注意：环境变量中的API密钥优先级高于此文件

# 语言设置 (en: English, zh: 中文)
CLAUDE_SWITCH_LANGUAGE=en

# GLM (智谱清言)
GLM_API_KEY=your-glm-api-key

# OpenRouter
OPENROUTER_API_KEY=your-openrouter-api-key

# —— 可选：模型ID覆盖（不设置则使用下方默认）——
GLM_MODEL=glm-5

EOF
    echo -e "${YELLOW}⚠️  $(t 'config_created'): $CONFIG_FILE${NC}" >&2
    echo -e "${YELLOW}   $(t 'edit_file_to_add_keys')${NC}" >&2
}

# 判断值是否为有效（非空且非占位符）
is_effectively_set() {
    local v="$1"
    if [[ -z "$v" ]]; then
        return 1
    fi
    local lower
    lower=$(printf '%s' "$v" | tr '[:upper:]' '[:lower:]')
    case "$lower" in
        *your-*-api-key)
            return 1
            ;;
        *)
            return 0
            ;;
    esac
}

# ============================================
# Setup Wizard Functions
# ============================================

# Check if wizard should run
should_run_wizard() {
    # Skip if explicitly disabled
    if [[ "${CCM_SKIP_SETUP:-false}" == "true" ]]; then
        return 1
    fi

    # Skip in non-interactive shells
    if [[ ! -t 0 ]]; then
        return 1
    fi

    # Run if config doesn't exist
    if [[ ! -f "$CONFIG_FILE" ]]; then
        return 0
    fi

    # Run if all keys are placeholders (config exists but no valid keys)
    load_config
    if ! is_effectively_set "$GLM_API_KEY" && \
       ! is_effectively_set "$OPENROUTER_API_KEY"; then
        return 0
    fi

    return 1
}

# Validate API key format
validate_api_key() {
    local provider="$1"
    local key="$2"

    case "$provider" in
        glm)
            [[ ${#key} -ge 48 ]]
            ;;
        openrouter)
            [[ "$key" =~ ^sk-or-v1-[a-zA-Z0-9]{50,}$ ]]
            ;;
        *)
            # Accept any non-empty key for unknown providers
            [[ -n "$key" ]]
            ;;
    esac
}

# Show provider selection menu
show_provider_menu() {
    local preselected="$1"
    echo "" >&2
    echo -e "${CYAN}╔═══════════════════════════════════════════════════╗${NC}" >&2
    echo -e "${CYAN}║${NC}  ${BOLD}Claude Switch Setup v${CLAUDE_SWITCH_VERSION}${NC}              ${CYAN}║${NC}" >&2
    echo -e "${CYAN}╠═══════════════════════════════════════════════════╣${NC}" >&2
    echo -e "${CYAN}║${NC}  $(t 'setup_choose_provider')              ${CYAN}║${NC}" >&2
    echo -e "${CYAN}╠═══════════════════════════════════════════════════╣${NC}" >&2
    echo -e "${CYAN}║${NC}                                             ${CYAN}║${NC}" >&2
    echo -e "${CYAN}║${NC}  ${GREEN}1)${NC} GLM          $(t 'setup_opt_glm')  ${CYAN}║${NC}" >&2
    echo -e "${CYAN}║${NC}  ${GREEN}2)${NC} OpenRouter   $(t 'setup_opt_openrouter')  ${CYAN}║${NC}" >&2
    echo -e "${CYAN}║${NC}  ${GREEN}3)${NC} $(t 'setup_opt_manual')  ${CYAN}║${NC}" >&2
    echo -e "${CYAN}║${NC}                                             ${CYAN}║${NC}" >&2
    echo -e "${CYAN}╚═══════════════════════════════════════════════════╝${NC}" >&2
    echo "" >&2
    echo -n "$(t 'setup_your_choice') [1-3, q to quit]: " >&2
}

# Prompt for API key
prompt_api_key() {
    local provider="$1"
    local provider_name="$2"
    local key_url="$3"

    echo "" >&2
    echo -e "${CYAN}─────────────────────────────────────────────────${NC}" >&2
    echo -e "${BOLD}${provider_name} API Key${NC}" >&2
    echo -e "${CYAN}─────────────────────────────────────────────────${NC}" >&2
    echo -e "${YELLOW}$(t 'setup_get_key'): ${key_url}${NC}" >&2
    echo "" >&2

    local max_attempts=3
    local attempt=1

    while (( attempt <= max_attempts )); do
        echo -n "$(t 'setup_enter_key') ${provider_name}: " >&2
        read -rs api_key < /dev/tty 2>/dev/null || {
            # If /dev/tty is not available, fall back to stdin
            read -rs api_key
        }
        echo "" >&2

        if [[ -z "$api_key" ]]; then
            echo -e "${RED}$(t 'setup_cancel')${NC}" >&2
            return 1
        fi

        if validate_api_key "$provider" "$api_key"; then
            echo "$api_key"
            return 0
        else
            (( attempt++ ))
            if (( attempt <= max_attempts )); then
                echo -e "${YELLOW}⚠️  $(t 'setup_invalid_key') (${attempt}/${max_attempts})${NC}" >&2
            else
                echo -e "${RED}❌ $(t 'setup_cancel')${NC}" >&2
                return 1
            fi
        fi
    done

    return 1
}

# Save single provider config
save_single_provider() {
    local provider="$1"
    local api_key="$2"

    # Create config directory if needed
    local config_dir
    config_dir="$(dirname "$CONFIG_FILE")"
    if [[ ! -d "$config_dir" ]]; then
        mkdir -p "$config_dir"
    fi

    # Load existing config if it exists
    if [[ -f "$CONFIG_FILE" ]]; then
        # Source it to get existing values
        source "$CONFIG_FILE" 2>/dev/null || true
    fi

    # Write config with the new key
    {
        echo "# Claude Switch Configuration - Generated by setup wizard"
        echo "# Created: $(date '+%Y-%m-%d %H:%M:%S')"
        echo ""

        case "$provider" in
            glm)
                echo "export GLM_API_KEY='$api_key'"
                echo "${OPENROUTER_API_KEY:+export OPENROUTER_API_KEY='$OPENROUTER_API_KEY'}"
                ;;
            openrouter|open)
                echo "${GLM_API_KEY:+export GLM_API_KEY='$GLM_API_KEY'}"
                echo "export OPENROUTER_API_KEY='$api_key'"
                ;;
        esac
    } > "$CONFIG_FILE"

    chmod 600 "$CONFIG_FILE"
}

# Show setup success message
show_setup_success() {
    local provider="$1"
    local provider_name="$2"

    echo "" >&2
    echo -e "${GREEN}✓ $(t 'setup_saved')${NC}" >&2
    echo "" >&2
    echo -e "${CYAN}$(t 'setup_try_command'):${NC}" >&2
    echo -e "  ${GREEN}claude-launch ${provider}${NC}      # $(t 'switching_to') ${provider_name}" >&2
    echo -e "  ${GREEN}claude-switch status${NC}        # $(t 'show_current_config')" >&2
    echo "" >&2
    echo -e "${YELLOW}$(t 'setup_add_more'): ${GREEN}claude-switch setup${NC}" >&2
    echo "" >&2
}

# Main wizard function
run_wizard() {
    local preselected_provider="$1"

    local provider=""
    local provider_name=""
    local key_url=""

    # Function to get provider info
    get_provider_info() {
        local p="$1"
        case "$p" in
            glm|glm5)
                provider_name="GLM"
                key_url="https://open.bigmodel.cn/usercenter/apikeys"
                ;;
            openrouter|open)
                provider_name="OpenRouter"
                key_url="https://openrouter.ai/keys"
                ;;
            *)
                provider_name="${p^}"
                key_url="(check provider documentation)"
                ;;
        esac
    }

    # Direct setup with --provider flag
    if [[ -n "$preselected_provider" ]]; then
        provider="$preselected_provider"
    else
        # Show menu and get selection
        show_provider_menu
        read -r selection < /dev/tty 2>/dev/null || {
            # If /dev/tty is not available, fall back to stdin
            read -r selection
        }

        case "$selection" in
            1|glm|glm5)
                provider="glm"
                ;;
            2|openrouter|open)
                provider="openrouter"
                ;;
            3|manual)
                echo "" >&2
                echo -e "${YELLOW}$(t 'edit_manually'): ${CONFIG_FILE}${NC}" >&2
                echo "" >&2
                if [[ ! -f "$CONFIG_FILE" ]]; then
                    create_default_config
                fi
                return 0
                ;;
            q|quit|exit)
                echo "" >&2
                echo -e "${YELLOW}Setup cancelled${NC}" >&2
                return 0
                ;;
            *)
                echo -e "${RED}$(t 'invalid_selection'): $selection${NC}" >&2
                return 1
                ;;
        esac
    fi

    # Get provider info
    get_provider_info "$provider"

    # Prompt for API key
    local api_key
    api_key="$(prompt_api_key "$provider" "$provider_name" "$key_url")" || return 1

    # Save config
    save_single_provider "$provider" "$api_key"

    # Show success
    show_setup_success "$provider" "$provider_name"
}

# 安全掩码工具
mask_token() {
    local t="$1"
    local n=${#t}
    if [[ -z "$t" ]]; then
        echo "[$(t 'not_set')]"
        return
    fi
    if (( n <= 8 )); then
        echo "[$(t 'set')] ****"
    else
        echo "[$(t 'set')] ${t:0:4}...${t:n-4:4}"
    fi
}

mask_presence() {
    local v_name="$1"
    local v_val="${!v_name}"
    if is_effectively_set "$v_val"; then
        echo "[$(t 'set')]"
    else
        echo "[$(t 'not_set')]"
    fi
}

# 输出 Claude Code 默认模型环境变量
emit_default_models() {
    local sonnet="$1"
    local opus="$2"
    local haiku="$3"
    echo "export ANTHROPIC_DEFAULT_SONNET_MODEL='${sonnet}'"
    echo "export ANTHROPIC_DEFAULT_OPUS_MODEL='${opus}'"
    echo "export ANTHROPIC_DEFAULT_HAIKU_MODEL='${haiku}'"
}

emit_subagent_model() {
    local model="$1"
    echo "export CLAUDE_CODE_SUBAGENT_MODEL='${model}'"
}

emit_default_models_from_pair() {
    local primary="$1"
    local small="$2"
    local haiku="${small:-$primary}"
    emit_default_models "$primary" "$primary" "$haiku"
}

# ============================================
# Claude Pro 账号管理功能
# ============================================

project_settings_path() {
    echo "$PWD/.claude/settings.local.json"
}

backup_project_settings() {
    local path="$1"
    local ts
    ts="$(date "+%Y%m%d-%H%M%S")"
    cp -f "$path" "${path}.bak.${ts}"
}

project_write_glm_settings() {
    local settings_path
    settings_path="$(project_settings_path)"
    local settings_dir
    settings_dir="$(dirname "$settings_path")"

    if ! is_effectively_set "$GLM_API_KEY"; then
        echo -e "${RED}❌ Please configure GLM_API_KEY before writing project settings${NC}" >&2
        return 1
    fi

    local glm_model="${GLM_MODEL:-glm-5}"
    local base_url="https://api.z.ai/api/anthropic"

    if [[ -f "$settings_path" ]]; then
        if ! grep -q '"claude-switchManaged"[[:space:]]*:[[:space:]]*true' "$settings_path"; then
            backup_project_settings "$settings_path"
        fi
    fi

    mkdir -p "$settings_dir"
  cat > "$settings_path" <<EOF
{
  "claude-switchManaged": true,
  "env": {
    "ANTHROPIC_BASE_URL": "${base_url}",
    "ANTHROPIC_AUTH_TOKEN": "${GLM_API_KEY}",
    "ANTHROPIC_MODEL": "${glm_model}",
    "ANTHROPIC_DEFAULT_SONNET_MODEL": "${glm_model}",
    "ANTHROPIC_DEFAULT_OPUS_MODEL": "${glm_model}",
    "ANTHROPIC_DEFAULT_HAIKU_MODEL": "${glm_model}",
    "CLAUDE_CODE_SUBAGENT_MODEL": "${glm_model}"
  }
}
EOF
    chmod 600 "$settings_path"
    echo -e "${GREEN}✅ Wrote project settings for GLM at:${NC} $settings_path" >&2
    echo -e "${YELLOW}💡 This overrides user settings (e.g. Quotio) for this project only.${NC}" >&2
}

project_reset_settings() {
    local settings_path
    settings_path="$(project_settings_path)"
    if [[ ! -f "$settings_path" ]]; then
        echo -e "${YELLOW}⚠️  No project settings to reset at:${NC} $settings_path" >&2
        return 0
    fi
    if ! grep -q '"claude-switchManaged"[[:space:]]*:[[:space:]]*true' "$settings_path"; then
        backup_project_settings "$settings_path"
    fi
    rm -f "$settings_path"
    echo -e "${GREEN}✅ Removed project settings:${NC} $settings_path" >&2
    echo -e "${YELLOW}💡 Claude Code will fall back to user settings (e.g. Quotio).${NC}" >&2
}

# ============================================
# User-level settings (~/.claude/settings.json)
# ============================================

USER_SETTINGS_PATH="$HOME/.claude/settings.json"

user_settings_path() {
    echo "$USER_SETTINGS_PATH"
}

backup_user_settings() {
    local path="$1"
    local ts
    ts="$(date "+%Y%m%d-%H%M%S")"
    cp -f "$path" "${path}.bak.${ts}"
}

# Get provider config for user-level settings
get_provider_config() {
    local provider="$1"
    local config_base_url=""
    local config_model=""
    local config_token_var=""

    case "$provider" in
        "glm"|"glm5")
            if ! is_effectively_set "$GLM_API_KEY"; then
                echo -e "${RED}❌ Please configure GLM_API_KEY first${NC}" >&2
                return 1
            fi
            config_token_var="GLM_API_KEY"
            config_model="${GLM_MODEL:-glm-5}"
            config_base_url="https://api.z.ai/api/anthropic"
            ;;
        *)
            echo -e "${RED}❌ Unknown provider: $provider${NC}" >&2
            echo -e "${YELLOW}Supported providers: glm${NC}" >&2
            return 1
            ;;
    esac

    echo "${config_base_url}|${config_model}|${config_token_var}"
}

user_write_settings() {
    local provider="$1"

    local config
    config="$(get_provider_config "$provider")" || return 1

    local config_base_url="${config%%|*}"
    local rest="${config#*|}"
    local config_model="${rest%%|*}"
    local config_token_var="${rest##*|}"

    local config_token=""
    if [[ -n "$config_token_var" ]]; then
        config_token="${!config_token_var}"
    fi

    local settings_path
    settings_path="$(user_settings_path)"
    local settings_dir
    settings_dir="$(dirname "$settings_path")"

    # Backup existing settings if not claude-switch-managed
    if [[ -f "$settings_path" ]]; then
        if ! grep -q '"claude-switchManaged"[[:space:]]*:[[:space:]]*true' "$settings_path" 2>/dev/null; then
            backup_user_settings "$settings_path"
        fi
    fi

    mkdir -p "$settings_dir"

    # Use Python or jq to merge settings if available, otherwise use simple approach
    if command -v python3 >/dev/null 2>&1; then
        python3 << PYTHON_EOF
import json
import os

settings_path = "$settings_path"
existing = {}

if os.path.exists(settings_path):
    try:
        with open(settings_path, 'r') as f:
            existing = json.load(f)
    except:
        existing = {}

# Preserve non-claude-switch settings but mark as claude-switch-managed
existing['claude-switchManaged'] = True
existing['claude-switchProvider'] = '$provider'

# Set env
existing['env'] = {
    'ANTHROPIC_BASE_URL': '$config_base_url',
    'ANTHROPIC_MODEL': '$config_model',
    'ANTHROPIC_DEFAULT_SONNET_MODEL': '$config_model',
    'ANTHROPIC_DEFAULT_OPUS_MODEL': '$config_model',
    'ANTHROPIC_DEFAULT_HAIKU_MODEL': '$config_model',
    'CLAUDE_CODE_SUBAGENT_MODEL': '$config_model'
}
$(if [[ -n "$config_token" ]]; then echo "existing['env']['ANTHROPIC_AUTH_TOKEN'] = '$config_token'"; fi)

with open(settings_path, 'w') as f:
    json.dump(existing, f, indent=2)

os.chmod(settings_path, 0o600)
PYTHON_EOF
    else
        # Fallback: write minimal settings (will lose other settings)
        cat > "$settings_path" <<EOF
{
  "claude-switchManaged": true,
  "claude-switchProvider": "$provider",
  "env": {
    "ANTHROPIC_BASE_URL": "$config_base_url",
    "ANTHROPIC_MODEL": "$config_model",
    "ANTHROPIC_DEFAULT_SONNET_MODEL": "$config_model",
    "ANTHROPIC_DEFAULT_OPUS_MODEL": "$config_model",
    "ANTHROPIC_DEFAULT_HAIKU_MODEL": "$config_model",
    "CLAUDE_CODE_SUBAGENT_MODEL": "$config_model"$([[ -n "$config_token" ]] && echo ",
    \"ANTHROPIC_AUTH_TOKEN\": \"$config_token\"")
  }
}
EOF
        chmod 600 "$settings_path"
    fi

    echo -e "${GREEN}✅ Wrote user-level settings for ${provider}${NC}" >&2
    echo -e "${BLUE}   File: $settings_path${NC}" >&2
    echo -e "${YELLOW}💡 This overrides environment variables and takes highest priority.${NC}" >&2
    echo -e "${YELLOW}💡 Use 'claude-switch user reset' to restore environment variable control.${NC}" >&2
}

user_reset_settings() {
    local settings_path
    settings_path="$(user_settings_path)"

    if [[ ! -f "$settings_path" ]]; then
        echo -e "${YELLOW}⚠️  No user settings file at: $settings_path${NC}" >&2
        return 0
    fi

    if ! grep -q '"claude-switchManaged"[[:space:]]*:[[:space:]]*true' "$settings_path" 2>/dev/null; then
        echo -e "${YELLOW}⚠️  Settings file is not managed by claude-switch. Not modifying.${NC}" >&2
        echo -e "${YELLOW}   File: $settings_path${NC}" >&2
        return 0
    fi

    # Backup before reset
    backup_user_settings "$settings_path"

    # Remove env section and claude-switch markers using Python or jq
    if command -v python3 >/dev/null 2>&1; then
        python3 << PYTHON_EOF
import json
import os

settings_path = "$settings_path"

with open(settings_path, 'r') as f:
    data = json.load(f)

# Remove claude-switch-managed keys
data.pop('claude-switchManaged', None)
data.pop('claude-switchProvider', None)
data.pop('env', None)

with open(settings_path, 'w') as f:
    json.dump(data, f, indent=2)
PYTHON_EOF
        echo -e "${GREEN}✅ Removed claude-switch-managed settings from user settings${NC}" >&2
    else
        # Fallback: just remove the file
        rm -f "$settings_path"
        echo -e "${GREEN}✅ Removed user settings file${NC}" >&2
    fi

    echo -e "${YELLOW}💡 Claude Code will now use environment variables.${NC}" >&2
    echo -e "${YELLOW}   Use 'claude-switch <provider>' to set environment variables.${NC}" >&2
}

user_show_usage() {
    echo -e "${BLUE}User-level settings (writes to ~/.claude/settings.json)${NC}" >&2
    echo "" >&2
    echo "Usage:" >&2
    echo "  claude-switch user <provider>   - Write provider settings to user-level" >&2
    echo "  claude-switch user reset        - Remove claude-switch settings, restore env var control" >&2
    echo "" >&2
    echo "Providers:" >&2
    echo "  glm    - GLM" >&2
    echo "" >&2
    echo "Examples:" >&2
    echo "  claude-switch user glm   # Use GLM globally" >&2
    echo "  claude-switch user reset # Remove, use env vars instead" >&2
}

# 从 Linux 文件系统读取 Claude Code 凭证
read_linux_credentials() {
    if [[ ! -f "$CLAUDE_CREDENTIALS_FILE" ]]; then
        echo ""
        return 1
    fi

    # 优先使用 jq 提取 claudeAiOauth 对象
    local credentials
    if command -v jq >/dev/null 2>&1; then
        credentials=$(jq -c '.claudeAiOauth' "$CLAUDE_CREDENTIALS_FILE" 2>/dev/null)
    else
        # 降级方案：使用 Python 或 grep（适用于简单情况）
        if command -v python3 >/dev/null 2>&1; then
            credentials=$(python3 -c "import json; f=open('$CLAUDE_CREDENTIALS_FILE'); d=json.load(f); print(json.dumps(d.get('claudeAiOauth', {})))" 2>/dev/null)
        else
            # 最后降级：简单的 grep（可能不完整）
            credentials=$(cat "$CLAUDE_CREDENTIALS_FILE" | grep -o '"claudeAiOauth":{[^}]*}' | sed 's/"claudeAiOauth"://')
        fi
    fi

    if [[ -z "$credentials" || "$credentials" == "null" || "$credentials" == "{}" ]]; then
        echo ""
        return 1
    fi

    echo "$credentials"
    return 0
}

# 从 macOS Keychain 读取 Claude Code 凭证
read_macos_credentials() {
    local credentials
    local -a services=(
        "$KEYCHAIN_SERVICE"
        "Claude Code - credentials"
        "Claude Code"
        "claude"
        "claude.ai"
    )
    for svc in "${services[@]}"; do
        credentials=$(security find-generic-password -s "$svc" -w 2>/dev/null)
        if [[ $? -eq 0 && -n "$credentials" ]]; then
            KEYCHAIN_SERVICE="$svc"
            echo "$credentials"
            return 0
        fi
    done
    echo ""
    return 1
}

# 写入凭证到 Linux 文件系统
write_linux_credentials() {
    local credentials="$1"

    # 确保 .claude 目录存在
    mkdir -p "$(dirname "$CLAUDE_CREDENTIALS_FILE")"

    # 使用 jq 进行更可靠的 JSON 操作
    if command -v jq >/dev/null 2>&1; then
        if [[ -f "$CLAUDE_CREDENTIALS_FILE" ]]; then
            # 更新现有文件，保留其他字段
            jq --argjson oauth "$credentials" '.claudeAiOauth = $oauth' "$CLAUDE_CREDENTIALS_FILE" > "${CLAUDE_CREDENTIALS_FILE}.tmp"
            mv "${CLAUDE_CREDENTIALS_FILE}.tmp" "$CLAUDE_CREDENTIALS_FILE"
        else
            # 创建新文件
            echo "{\"claudeAiOauth\":$credentials}" | jq '.' > "$CLAUDE_CREDENTIALS_FILE"
        fi
    else
        # 降级方案：使用纯 Bash（可能不完美，但可用）
        local existing_content=""
        local mcp_oauth=""

        if [[ -f "$CLAUDE_CREDENTIALS_FILE" ]]; then
            existing_content=$(cat "$CLAUDE_CREDENTIALS_FILE")
            # 提取 mcpOAuth 部分（如果存在）- 更好的正则表达式
            if command -v python3 >/dev/null 2>&1; then
                mcp_oauth=$(python3 -c "import json; f=open('$CLAUDE_CREDENTIALS_FILE'); d=json.load(f); print(json.dumps(d.get('mcpOAuth', {})) if d.get('mcpOAuth') else '')" 2>/dev/null)
            fi
        fi

        # 构建新的 JSON 文件
        if [[ -n "$mcp_oauth" && "$mcp_oauth" != "{}" ]]; then
            # 保留 mcpOAuth
            cat > "$CLAUDE_CREDENTIALS_FILE" << EOF
{"claudeAiOauth":$credentials,"mcpOAuth":$mcp_oauth}
EOF
        else
            # 只有 claudeAiOauth
            cat > "$CLAUDE_CREDENTIALS_FILE" << EOF
{"claudeAiOauth":$credentials}
EOF
        fi
    fi

    chmod 600 "$CLAUDE_CREDENTIALS_FILE"
    echo -e "${BLUE}🔑 $(t 'credentials_written_to_file')${NC}" >&2
    return 0
}

# 写入凭证到 macOS Keychain
write_macos_credentials() {
    local credentials="$1"
    local username="$USER"

    # 先删除现有的凭证
    security delete-generic-password -s "$KEYCHAIN_SERVICE" >/dev/null 2>&1

    # 添加新凭证
    security add-generic-password -a "$username" -s "$KEYCHAIN_SERVICE" -w "$credentials" >/dev/null 2>&1
    local result=$?

    if [[ $result -eq 0 ]]; then
        echo -e "${BLUE}🔑 凭证已写入 Keychain${NC}" >&2
    else
        echo -e "${RED}❌ 凭证写入 Keychain 失败 (错误码: $result)${NC}" >&2
    fi

    return $result
}

# 调试函数：验证 Keychain 中的凭证
debug_keychain_credentials() {
    # 根据操作系统显示不同标题
    if [[ "$OS_TYPE" == "macos" ]]; then
        echo -e "${BLUE}🔍 $(t 'credentials_source_keychain'): ${OS_TYPE} (${ARCH_TYPE})${NC}"
    else
        echo -e "${BLUE}🔍 $(t 'credentials_source_file'): ${OS_TYPE} (${ARCH_TYPE})${NC}"
    fi

    local credentials=$(platform::credentials_read)
    if [[ -z "$credentials" ]]; then
        if [[ "$OS_TYPE" == "macos" ]]; then
            echo -e "${RED}❌ Keychain 中没有凭证${NC}"
        else
            echo -e "${RED}❌ $(t 'no_credentials_found')${NC}"
            echo -e "${YELLOW}💡 $(t 'please_login_first')${NC}"
        fi
        return 1
    fi

    # 提取凭证信息
    local subscription=$(echo "$credentials" | grep -o '"subscriptionType":"[^"]*"' | cut -d'"' -f4)
    local expires=$(echo "$credentials" | grep -o '"expiresAt":[0-9]*' | cut -d':' -f2)
    local access_token_preview=$(echo "$credentials" | grep -o '"accessToken":"[^"]*"' | cut -d'"' -f4 | head -c 20)

    echo -e "${GREEN}✅ $(t 'credentials_found')：${NC}"
    if [[ "$OS_TYPE" == "macos" ]]; then
        echo "   $(t 'service_name'): $KEYCHAIN_SERVICE"
    else
        echo "   $(t 'file_path'): $CLAUDE_CREDENTIALS_FILE"
    fi
    echo "   $(t 'subscription_type'): ${subscription:-Unknown}"
    if [[ -n "$expires" ]]; then
        local expires_str=$(format_epoch_ms "$expires")
        echo "   $(t 'token_expires'): $expires_str"
    fi
    echo "   $(t 'access_token'): ${access_token_preview}..."

    # 尝试匹配保存的账号
    if [[ -f "$ACCOUNTS_FILE" ]]; then
        echo -e "${BLUE}🔍 $(t 'trying_to_match_accounts')${NC}"
        while IFS=': ' read -r name encoded; do
            name=$(echo "$name" | tr -d '"')
            encoded=$(echo "$encoded" | tr -d '"')
            local saved_creds=$(echo "$encoded" | platform::base64_decode 2>/dev/null)
            if [[ "$saved_creds" == "$credentials" ]]; then
                echo -e "${GREEN}✅ $(t 'matched_account'): $name${NC}"
                return 0
            fi
        done < <(grep --color=never -o '"[^"]*": *"[^"]*"' "$ACCOUNTS_FILE")
        echo -e "${YELLOW}⚠️  $(t 'no_matching_account')${NC}"
    fi
}

# 初始化账号配置文件
init_accounts_file() {
    if [[ ! -f "$ACCOUNTS_FILE" ]]; then
        echo "{}" > "$ACCOUNTS_FILE"
        chmod 600 "$ACCOUNTS_FILE"
    fi
}

# 保存当前账号
save_account() {
    # 检查是否需要禁用颜色（用于 eval）
    if [[ "$NO_COLOR" == "true" ]]; then
        set_no_color
    fi
    local account_name="$1"

    if [[ -z "$account_name" ]]; then
        echo -e "${RED}❌ $(t 'account_name_required')${NC}" >&2
        echo -e "${YELLOW}💡 $(t 'usage'): claude-switch save-account <name>${NC}" >&2
        return 1
    fi

    # 从 Keychain 读取当前凭证
    local credentials
    credentials=$(platform::credentials_read)
    if [[ -z "$credentials" ]]; then
        echo -e "${RED}❌ $(t 'no_credentials_found')${NC}" >&2
        echo -e "${YELLOW}💡 $(t 'please_login_first')${NC}" >&2
        return 1
    fi

    # 初始化账号文件
    init_accounts_file

    # 使用纯 Bash 解析和保存（不依赖 jq）
    local temp_file=$(mktemp)
    local existing_accounts=""

    if [[ -f "$ACCOUNTS_FILE" ]]; then
        existing_accounts=$(cat "$ACCOUNTS_FILE")
    fi

    # 简单的 JSON 更新：如果是空文件或只有 {}，直接写入
    if [[ "$existing_accounts" == "{}" || -z "$existing_accounts" ]]; then
        local encoded_creds=$(echo "$credentials" | platform::base64_encode)
        cat > "$ACCOUNTS_FILE" << EOF
{
  "$account_name": "$encoded_creds"
}
EOF
    else
        # 读取现有账号，添加新账号
        # 检查账号是否已存在
        if grep -q "\"$account_name\":" "$ACCOUNTS_FILE"; then
            # 更新现有账号
            local encoded_creds=$(echo "$credentials" | platform::base64_encode)
            # 使用 sed 替换现有条目（跨平台兼容）
            platform::sed_inplace "s/\"$account_name\": *\"[^\"]*\"/\"$account_name\": \"$encoded_creds\"/" "$ACCOUNTS_FILE"
        else
            # 添加新账号
            local encoded_creds=$(echo "$credentials" | platform::base64_encode)
            # 移除最后的 } 并在上一行末尾添加逗号
            sed '$d' "$ACCOUNTS_FILE" | sed '$s/$/,/' > "$temp_file"
            echo "  \"$account_name\": \"$encoded_creds\"" >> "$temp_file"
            echo "}" >> "$temp_file"
            mv "$temp_file" "$ACCOUNTS_FILE"
        fi
    fi

    chmod 600 "$ACCOUNTS_FILE"

    # 提取订阅类型用于显示
    local subscription_type=$(echo "$credentials" | grep -o '"subscriptionType":"[^"]*"' | cut -d'"' -f4)
    echo -e "${GREEN}✅ $(t 'account_saved'): $account_name${NC}"
    echo -e "   $(t 'subscription_type'): ${subscription_type:-Unknown}"

    rm -f "$temp_file"
}

# 切换到指定账号
switch_account() {
    # 检查是否需要禁用颜色（用于 eval）
    if [[ "$NO_COLOR" == "true" ]]; then
        set_no_color
    fi
    local account_name="$1"

    if [[ -z "$account_name" ]]; then
        echo -e "${RED}❌ $(t 'account_name_required')${NC}" >&2
        echo -e "${YELLOW}💡 $(t 'usage'): claude-switch switch-account <name>${NC}" >&2
        return 1
    fi

    if [[ ! -f "$ACCOUNTS_FILE" ]]; then
        echo -e "${RED}❌ $(t 'no_accounts_found')${NC}" >&2
        echo -e "${YELLOW}💡 $(t 'save_account_first')${NC}" >&2
        return 1
    fi

    # 从文件中读取账号凭证
    local encoded_creds=$(grep -o "\"$account_name\": *\"[^\"]*\"" "$ACCOUNTS_FILE" | cut -d'"' -f4)

    if [[ -z "$encoded_creds" ]]; then
        echo -e "${RED}❌ $(t 'account_not_found'): $account_name${NC}" >&2
        echo -e "${YELLOW}💡 $(t 'use_list_accounts')${NC}" >&2
        return 1
    fi

    # 解码凭证
    local credentials=$(echo "$encoded_creds" | platform::base64_decode)

    # 写入 Keychain
    if platform::credentials_write "$credentials"; then
        echo -e "${GREEN}✅ $(t 'account_switched'): $account_name${NC}"
        echo -e "${YELLOW}⚠️  $(t 'please_restart_claude_code')${NC}"
    else
        echo -e "${RED}❌ $(t 'failed_to_switch_account')${NC}" >&2
        return 1
    fi
}

# 列出所有已保存的账号
list_accounts() {
    if [[ ! -f "$ACCOUNTS_FILE" ]]; then
        echo -e "${YELLOW}$(t 'no_accounts_saved')${NC}"
        echo -e "${YELLOW}💡 $(t 'use_save_account')${NC}"
        return 0
    fi

    echo -e "${BLUE}📋 $(t 'saved_accounts'):${NC}"

    # 读取并解析账号列表
    local current_creds=$(platform::credentials_read)

    # 使用 jq 或 Python 解析 JSON（处理多行 base64 值）
    if command -v jq >/dev/null 2>&1; then
        jq -r 'to_entries[] | "\(.key)|\(.value)"' "$ACCOUNTS_FILE" | while IFS='|' read -r name encoded; do
            # 解码并提取信息
            local creds=$(echo "$encoded" | platform::base64_decode 2>/dev/null)
            local subscription=$(echo "$creds" | grep -o '"subscriptionType":"[^"]*"' | cut -d'"' -f4)
            local expires=$(echo "$creds" | grep -o '"expiresAt":[0-9]*' | cut -d':' -f2)

            # 检查是否是当前账号
            local is_current=""
            if [[ "$creds" == "$current_creds" ]]; then
                is_current=" ${GREEN}✅ ($(t 'active'))${NC}"
            fi

            # 格式化过期时间
            local expires_str=""
            if [[ -n "$expires" ]]; then
                expires_str=$(platform::date_format "$((expires / 1000))")
            fi

            echo -e "   - ${YELLOW}$name${NC} (${subscription:-Unknown}${expires_str:+, expires: $expires_str})$is_current"
        done
    elif command -v python3 >/dev/null 2>&1; then
        python3 -c "
import json
with open('$ACCOUNTS_FILE') as f:
    data = json.load(f)
    for name, encoded in data.items():
        print(f'{name}|{encoded}')
" | while IFS='|' read -r name encoded; do
            # 解码并提取信息
            local creds=$(echo "$encoded" | platform::base64_decode 2>/dev/null)
            local subscription=$(echo "$creds" | grep -o '"subscriptionType":"[^"]*"' | cut -d'"' -f4)
            local expires=$(echo "$creds" | grep -o '"expiresAt":[0-9]*' | cut -d':' -f2)

            # 检查是否是当前账号
            local is_current=""
            if [[ "$creds" == "$current_creds" ]]; then
                is_current=" ${GREEN}✅ ($(t 'active'))${NC}"
            fi

            # 格式化过期时间
            local expires_str=""
            if [[ -n "$expires" ]]; then
                expires_str=$(platform::date_format "$((expires / 1000))")
            fi

            echo -e "   - ${YELLOW}$name${NC} (${subscription:-Unknown}${expires_str:+, expires: $expires_str})$is_current"
        done
    else
        # 降级方案：仅支持单行 base64 值
        echo -e "${YELLOW}⚠️  $(t 'install_jq_or_python')${NC}"
        grep --color=never -o '"[^"]*": *"[^"]*"' "$ACCOUNTS_FILE" | while IFS=': ' read -r name encoded; do
            name=$(echo "$name" | tr -d '"')
            encoded=$(echo "$encoded" | tr -d '"')
            echo -e "   - ${YELLOW}$name${NC}"
        done
    fi
}

# 删除已保存的账号
delete_account() {
    local account_name="$1"

    if [[ -z "$account_name" ]]; then
        echo -e "${RED}❌ $(t 'account_name_required')${NC}" >&2
        echo -e "${YELLOW}💡 $(t 'usage'): claude-switch delete-account <name>${NC}" >&2
        return 1
    fi

    if [[ ! -f "$ACCOUNTS_FILE" ]]; then
        echo -e "${RED}❌ $(t 'no_accounts_found')${NC}" >&2
        return 1
    fi

    # 检查账号是否存在
    if ! grep -q "\"$account_name\":" "$ACCOUNTS_FILE"; then
        echo -e "${RED}❌ $(t 'account_not_found'): $account_name${NC}" >&2
        return 1
    fi

    # 删除账号（使用临时文件）
    local temp_file=$(mktemp)
    grep -v "\"$account_name\":" "$ACCOUNTS_FILE" > "$temp_file"

    # 清理可能的逗号问题（跨平台兼容）
    platform::sed_inplace 's/,\s*}/}/g' "$temp_file"
    platform::sed_inplace 's/}\s*,/}/g' "$temp_file"

    mv "$temp_file" "$ACCOUNTS_FILE"
    chmod 600 "$ACCOUNTS_FILE"

    echo -e "${GREEN}✅ $(t 'account_deleted'): $account_name${NC}"
}

# 显示当前账号信息
get_current_account() {
    local credentials=$(platform::credentials_read)

    if [[ -z "$credentials" ]]; then
        echo -e "${YELLOW}$(t 'no_current_account')${NC}"
        echo -e "${YELLOW}💡 $(t 'please_login_or_switch')${NC}"
        return 1
    fi

    # 提取信息
    local subscription=$(echo "$credentials" | grep -o '"subscriptionType":"[^"]*"' | cut -d'"' -f4)
    local expires=$(echo "$credentials" | grep -o '"expiresAt":[0-9]*' | cut -d':' -f2)
    local access_token=$(echo "$credentials" | grep -o '"accessToken":"[^"]*"' | cut -d'"' -f4)

    # 格式化过期时间
    local expires_str=""
    if [[ -n "$expires" ]]; then
        expires_str=$(platform::date_format "$((expires / 1000))")
    fi

    # 查找账号名称
    local account_name="Unknown"
    if [[ -f "$ACCOUNTS_FILE" ]]; then
        while IFS=': ' read -r name encoded; do
            name=$(echo "$name" | tr -d '"')
            encoded=$(echo "$encoded" | tr -d '"')
            local saved_creds=$(echo "$encoded" | platform::base64_decode 2>/dev/null)
            if [[ "$saved_creds" == "$credentials" ]]; then
                account_name="$name"
                break
            fi
        done < <(grep --color=never -o '"[^"]*": *"[^"]*"' "$ACCOUNTS_FILE")
    fi

    echo -e "${BLUE}📊 $(t 'current_account_info'):${NC}"
    echo "   $(t 'account_name'): ${account_name}"
    echo "   $(t 'subscription_type'): ${subscription:-Unknown}"
    if [[ -n "$expires_str" ]]; then
        echo "   $(t 'token_expires'): ${expires_str}"
    fi
    echo -n "   $(t 'access_token'): "
    mask_token "$access_token"
}

# 显示当前状态（脱敏）
show_status() {
    # 检查用户级配置 (~/.claude/settings.json)
    local user_settings_path="$HOME/.claude/settings.json"
    if [[ -f "$user_settings_path" ]]; then
        # 检查是否有 env 设置
        if grep -q '"env"[[:space:]]*:' "$user_settings_path" 2>/dev/null; then
            local user_base_url=$(grep -o '"ANTHROPIC_BASE_URL"[[:space:]]*:[[:space:]]*"[^"]*"' "$user_settings_path" | cut -d'"' -f4)
            local user_model=$(grep -o '"ANTHROPIC_MODEL"[[:space:]]*:[[:space:]]*"[^"]*"' "$user_settings_path" | cut -d'"' -f4)
            local user_token=$(grep -o '"ANTHROPIC_AUTH_TOKEN"[[:space:]]*:[[:space:]]*"[^"]*"' "$user_settings_path" | cut -d'"' -f4)
            local claude_switch_managed=$(grep -o '"ccmManaged"[[:space:]]*:[[:space:]]*[a-z]*' "$user_settings_path" | grep -o 'true\|false')

            if [[ "$claude_switch_managed" == "true" ]]; then
                echo -e "${GREEN}👤 User config (claude-switch-managed):${NC} $user_settings_path"
            else
                echo -e "${YELLOW}⚠️  User config (external):${NC} $user_settings_path"
                echo -e "${YELLOW}   This overrides environment variables!${NC}"
            fi
            echo "   BASE_URL: ${user_base_url:-'N/A'}"
            echo "   MODEL: ${user_model:-'N/A'}"
            echo -n "   AUTH_TOKEN: "
            mask_token "$user_token"
            echo ""
            if [[ "$claude_switch_managed" != "true" ]]; then
                echo -e "${YELLOW}💡 Use 'claude-switch user <provider>' to take control, or edit the file directly.${NC}"
            else
                echo -e "${YELLOW}💡 Use 'claude-switch user reset' to restore environment variable control.${NC}"
            fi
            echo ""
        fi
    fi

    # 检查项目级配置
    local project_settings=""
    local project_settings_path="$(project_settings_path)"
    if [[ -f "$project_settings_path" ]]; then
        if grep -q '"claude-switchManaged"[[:space:]]*:[[:space:]]*true' "$project_settings_path" 2>/dev/null; then
            echo -e "${GREEN}📁 $(t 'project_config'):${NC} $project_settings_path"
            # 提取项目配置中的关键信息
            local proj_base_url=$(grep -o '"ANTHROPIC_BASE_URL"[[:space:]]*:[[:space:]]*"[^"]*"' "$project_settings_path" | cut -d'"' -f4)
            local proj_model=$(grep -o '"ANTHROPIC_MODEL"[[:space:]]*:[[:space:]]*"[^"]*"' "$project_settings_path" | cut -d'"' -f4)
            local proj_token=$(grep -o '"ANTHROPIC_AUTH_TOKEN"[[:space:]]*:[[:space:]]*"[^"]*"' "$project_settings_path" | cut -d'"' -f4)
            echo "   BASE_URL: ${proj_base_url:-'N/A'}"
            echo "   MODEL: ${proj_model:-'N/A'}"
            echo -n "   AUTH_TOKEN: "
            mask_token "$proj_token"
            echo ""
        fi
    fi

    # OpenRouter Configuration
    if is_effectively_set "$OPENROUTER_API_KEY"; then
        echo -e "${BLUE}🌐 OpenRouter:${NC}"
        if [[ "${ANTHROPIC_BASE_URL:-}" == *"openrouter"* ]]; then
            echo -e "   ${GREEN}Status:${NC} $(t 'openrouter_active')"
            echo "   MODEL: ${ANTHROPIC_MODEL:-'(not set)'}"
            echo "   SUBAGENT_MODEL: ${CLAUDE_CODE_SUBAGENT_MODEL:-'(not set)'}"
            # Detect provider from model name
            if [[ -n "${ANTHROPIC_MODEL:-}" ]]; then
                case "$ANTHROPIC_MODEL" in
                    *glm*) echo "   Provider: $(t 'openrouter_provider_glm')" ;;
                    *) echo "   Provider: $(t 'openrouter_provider_unknown') ${ANTHROPIC_MODEL})" ;;
                esac
            fi
        else
            echo -e "   ${YELLOW}Status:${NC} $(t 'openrouter_configured_not_active')"
            echo -e "${YELLOW}   💡 $(t 'openrouter_use_eval_hint')${NC}"
        fi
        echo ""
    fi

    echo -e "${BLUE}📊 $(t 'current_model_config'):${NC}"
    echo "   BASE_URL: ${ANTHROPIC_BASE_URL:-'Default (Anthropic)'}"
    echo -n "   AUTH_TOKEN: "
    mask_token "${ANTHROPIC_AUTH_TOKEN}"
    echo "   MODEL: ${ANTHROPIC_MODEL:-'$(t "not_set")'}"
    echo "   SUBAGENT_MODEL: ${CLAUDE_CODE_SUBAGENT_MODEL:-'$(t "not_set")'}"
    echo ""
    echo -e "${BLUE}🔧 $(t 'env_vars_status'):${NC}"
    echo "   GLM_API_KEY: $(mask_presence GLM_API_KEY)"
    echo "   OPENROUTER_API_KEY: $(mask_presence OPENROUTER_API_KEY)"
    echo ""
}


# 显示帮助信息
show_help() {
    echo -e "${BLUE}🔧 Claude Switch v${CLAUDE_SWITCH_VERSION}${NC}"
    echo ""
    echo -e "${YELLOW}$(t 'usage'):${NC} $(basename "$0") [options]"
    echo ""
    echo -e "${YELLOW}$(t 'model_options'):${NC}"
    echo "  glm                     - env GLM (Zhipu GLM-5)"
    echo "  open <provider>         - env OpenRouter (run 'claude-switch open' for help)"
    echo ""
    echo -e "${YELLOW}User-level Settings (highest priority):${NC}"
    echo "  user <provider>         - write to ~/.claude/settings.json"
    echo "  user reset               - remove claude-switch settings, restore env var control"
    echo "  Providers: glm"
    echo ""
    echo -e "${YELLOW}Project-level Settings:${NC}"
    echo "  project glm             - write .claude/settings.local.json (project-only)"
    echo "  project reset              - remove project override"
    echo ""
    echo -e "${YELLOW}Claude Pro Account Management:${NC}"
    echo "  save-account <name>     - Save current Claude Pro account"
    echo "  switch-account <name>   - Switch to saved account"
    echo "  list-accounts           - List all saved accounts"
    echo "  delete-account <name>   - Delete saved account"
    echo "  current-account         - Show current account info"
    echo "  glm:account             - Switch account and use GLM"
    echo ""
    echo -e "${YELLOW}$(t 'tool_options'):${NC}"
    echo "  status, st       - $(t 'show_current_config')"
    echo "  env [model]      - $(t 'output_export_only')"
    echo "  config, cfg      - $(t 'edit_config_file')"
    echo "  update-config    - Update model IDs to latest defaults"
    echo "  help, h          - $(t 'show_help')"
    echo ""
    echo -e "${YELLOW}$(t 'examples'):${NC}"
    echo "  eval \"\$(claude-switch glm)\"                   # Apply in current shell (recommended)"
    echo "  eval \"\$(claude-switch open glm)\"               # OpenRouter GLM"
    echo ""
    echo "  claude-switch user glm    # Set GLM as default (highest priority)"
    echo "  claude-switch user reset  # Restore env var control"
    echo "  $(basename "$0") status                      # Check current status (masked)"
    echo "  $(basename "$0") save-account work           # Save current account as 'work'"
    echo ""
    echo -e "${YELLOW}支持的模型:${NC}"
    echo "  🇨🇳 GLM                 - glm-5 (api.z.ai/api/anthropic)"
}

# 将缺失的模型ID覆盖项追加到配置文件（仅追加缺失项，不覆盖已存在的配置）
ensure_model_override_defaults() {
    local -a pairs=(
        "GLM_MODEL=glm-5"
    )
    local added_header=0
    for pair in "${pairs[@]}"; do
        local key="${pair%%=*}"
        local default="${pair#*=}"
        if ! grep -Eq "^[[:space:]]*(export[[:space:]]+)?${key}[[:space:]]*=" "$CONFIG_FILE" 2>/dev/null; then
            if [[ $added_header -eq 0 ]]; then
                {
                    echo ""
                    echo "# ---- Claude Switch model ID overrides (auto-added) ----"
                } >> "$CONFIG_FILE"
                added_header=1
            fi
            printf "%s=%s\n" "$key" "$default" >> "$CONFIG_FILE"
        fi
    done
}

# 编辑配置文件
edit_config() {
    # 确保配置文件存在
    if [[ ! -f "$CONFIG_FILE" ]]; then
        echo -e "${YELLOW}📝 $(t 'config_created'): $CONFIG_FILE${NC}"
        create_default_config
    fi

    # 追加缺失的模型ID覆盖默认值（不触碰已有键）
    ensure_model_override_defaults

    echo -e "${BLUE}🔧 $(t 'opening_config_file')...${NC}"
    echo -e "${YELLOW}$(t 'config_file_path'): $CONFIG_FILE${NC}"

    # 按优先级尝试不同的编辑器
    local editor
    editor=$(platform::get_editor)
    case "$editor" in
        cursor)
            echo -e "${GREEN}✅ $(t 'using_cursor')${NC}"
            cursor "$CONFIG_FILE" &
            echo -e "${YELLOW}💡 $(t 'config_opened') Cursor $(t 'opened_edit_save')${NC}"
            ;;
        code)
            echo -e "${GREEN}✅ $(t 'using_vscode')${NC}"
            code "$CONFIG_FILE" &
            echo -e "${YELLOW}💡 $(t 'config_opened') VS Code $(t 'opened_edit_save')${NC}"
            ;;
        open)
            echo -e "${GREEN}✅ $(t 'using_default_editor')${NC}"
            open "$CONFIG_FILE"
            echo -e "${YELLOW}💡 $(t 'config_opened_default')${NC}"
            ;;
        vim)
            echo -e "${GREEN}✅ $(t 'using_vim')${NC}"
            vim "$CONFIG_FILE"
            ;;
        nano)
            echo -e "${GREEN}✅ $(t 'using_nano')${NC}"
            nano "$CONFIG_FILE"
            ;;
        *)
            echo -e "${RED}❌ $(t 'no_editor_found')${NC}"
            echo -e "${YELLOW}$(t 'edit_manually'): $CONFIG_FILE${NC}"
            echo -e "${YELLOW}$(t 'install_editor'): cursor, code, vim, nano${NC}"
            return 1
            ;;
    esac
}

# 更新配置文件中的模型 ID（当默认值变化时）
update_config() {
    if [[ ! -f "$CONFIG_FILE" ]]; then
        echo -e "${YELLOW}⚠️  Config file not found. Run 'claude-switch config' first.${NC}" >&2
        return 1
    fi

    echo -e "${BLUE}🔄 Checking for outdated model IDs...${NC}" >&2

    # 定义需要更新的键值对映射（旧值 -> 新值）
    # 格式: "KEY|OLD_VALUE|NEW_VALUE"
    local -a updates=(
        "GLM_MODEL|glm-4|glm-5"
        "GLM_MODEL|glm-4.6|glm-5"
        "GLM_MODEL|glm-4.7|glm-5"
    )

    local updated_count=0

    for update in "${updates[@]}"; do
        local key="${update%%|*}"
        local rest="${update#*|}"
        local old_value="${rest%%|*}"
        local new_value="${rest##*|}"

        # 检查配置文件中是否有需要更新的旧值
        if grep -qE "^[[:space:]]*${key}[[:space:]]*=[[:space:]]*${old_value}([[:space:]]*$|[[:space:]]*#)" "$CONFIG_FILE" 2>/dev/null; then
            # 使用 sed 替换
            platform::sed_inplace "s|^\([[:space:]]*${key}[[:space:]]*=[[:space:]]*\)${old_value}|\1${new_value}|" "$CONFIG_FILE"
            echo -e "${GREEN}✅ Updated ${key}: ${old_value} → ${new_value}${NC}" >&2
            ((updated_count++))
        fi
    done

    # 同时确保缺失的键被添加
    ensure_model_override_defaults

    if [[ $updated_count -eq 0 ]]; then
        echo -e "${GREEN}✅ Config is up to date${NC}" >&2
    else
        echo -e "${GREEN}✅ Updated ${updated_count} model ID(s)${NC}" >&2
    fi
}

# 仅输出 export 语句的环境设置（用于 eval）
show_open_help() {
    echo -e "${YELLOW}OpenRouter:${NC}"
    echo "  claude-switch open <provider>"
    echo ""
    echo -e "${YELLOW}Supported providers:${NC}"
    echo "  glm - Zhipu GLM-5"
    echo ""
    echo -e "${YELLOW}Examples:${NC}"
    echo "  eval \"\$(claude-switch open glm)\""
}

emit_openrouter_exports() {
    local provider="${1:-}"
    # 加载配置以便进行存在性判断（环境变量优先，不打印密钥）
    load_config || return 1

    if ! is_effectively_set "$OPENROUTER_API_KEY"; then
        echo -e "${RED}❌ Please configure OPENROUTER_API_KEY${NC}" >&2
        return 1
    fi
    if [[ -z "$provider" ]]; then
        show_open_help >&2
        return 1
    fi

    local model=""
    local small=""
    local default_sonnet=""
    local default_opus=""
    local default_haiku=""

    case "$provider" in
        "glm"|"glm5")
            model="z-ai/glm-5"
            small="z-ai/glm-5"
            default_sonnet="$model"
            default_opus="$model"
            default_haiku="$model"
            ;;
        *)
            echo -e "${RED}❌ $(t 'unknown_option'): open $provider${NC}" >&2
            show_open_help >&2
            return 1
            ;;
    esac

    local prelude="unset ANTHROPIC_BASE_URL ANTHROPIC_API_URL ANTHROPIC_AUTH_TOKEN ANTHROPIC_API_KEY ANTHROPIC_MODEL ANTHROPIC_SMALL_FAST_MODEL ANTHROPIC_DEFAULT_SONNET_MODEL ANTHROPIC_DEFAULT_OPUS_MODEL ANTHROPIC_DEFAULT_HAIKU_MODEL CLAUDE_CODE_SUBAGENT_MODEL API_TIMEOUT_MS CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC"
    echo "$prelude"
    echo "export ANTHROPIC_BASE_URL='https://openrouter.ai/api'"
    echo "export ANTHROPIC_API_URL='https://openrouter.ai/api'"
    echo "if [ -f \"\$HOME/.claude_switch_config\" ]; then . \"\$HOME/.claude_switch_config\" >/dev/null 2>&1; fi"
    echo "export ANTHROPIC_AUTH_TOKEN=\"\${OPENROUTER_API_KEY}\""
    echo "export ANTHROPIC_API_KEY=''"
    echo "export ANTHROPIC_MODEL='${model}'"
    echo "export ANTHROPIC_SMALL_FAST_MODEL='${small}'"
    emit_default_models "$default_sonnet" "$default_opus" "$default_haiku"
    emit_subagent_model "$model"
}

emit_env_exports() {
    local target="$1"
    local arg="${2:-}"
    # 加载配置以便进行存在性判断（环境变量优先，不打印密钥）
    load_config || return 1

    # 通用前导：清理旧变量
    local prelude="unset ANTHROPIC_BASE_URL ANTHROPIC_API_URL ANTHROPIC_AUTH_TOKEN ANTHROPIC_API_KEY ANTHROPIC_MODEL ANTHROPIC_SMALL_FAST_MODEL ANTHROPIC_DEFAULT_SONNET_MODEL ANTHROPIC_DEFAULT_OPUS_MODEL ANTHROPIC_DEFAULT_HAIKU_MODEL CLAUDE_CODE_SUBAGENT_MODEL API_TIMEOUT_MS CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC"

    case "$target" in
        "open")
            emit_openrouter_exports "$arg"
            ;;
        "glm"|"glm5")
            if ! is_effectively_set "$GLM_API_KEY"; then
                echo -e "${RED}❌ Please configure GLM_API_KEY${NC}" >&2
                return 1
            fi
            local glm_model="${GLM_MODEL:-glm-5}"
            echo "$prelude"
            echo "export ANTHROPIC_BASE_URL='https://api.z.ai/api/anthropic'"
            echo "if [ -f \"\$HOME/.claude_switch_config\" ]; then . \"\$HOME/.claude_switch_config\" >/dev/null 2>&1; fi"
            echo "export ANTHROPIC_AUTH_TOKEN=\"\${GLM_API_KEY}\""
            echo "export ANTHROPIC_MODEL='${glm_model}'"
            emit_default_models "$glm_model" "$glm_model" "$glm_model"
            emit_subagent_model "$glm_model"
            ;;
        *)
            echo "# $(t 'usage'): $(basename "$0") env [glm|open <provider>]" 1>&2
            return 1
            ;;
    esac
}


# 主函数
main() {
    # 加载配置（环境变量优先）
    if ! load_config; then
        return 1
    fi

    # 处理参数
    local cmd="${1:-help}"

    # 检查是否是 model:account 格式
    if [[ "$cmd" =~ ^(glm|glm5):(.+)$ ]]; then
        local model_type="${BASH_REMATCH[1]}"
        local account_name="${BASH_REMATCH[2]}"

        # 先切换账号：将输出重定向到stderr，避免污染stdout（stdout仅用于export语句）
        switch_account "$account_name" 1>&2 || return 1

        # 然后仅输出对应模型的 export 语句，供调用方 eval
        case "$model_type" in
            "glm"|"glm5")
                emit_env_exports glm
                ;;
        esac
        return $?
    fi

    case "$cmd" in
        # 账号管理命令
        "save-account")
            shift
            save_account "$1"
            ;;
        "switch-account")
            shift
            switch_account "$1"
            ;;
        "list-accounts")
            list_accounts
            ;;
        "delete-account")
            shift
            delete_account "$1"
            ;;
        "current-account")
            get_current_account
            ;;
        "debug-keychain")
            debug_keychain_credentials
            ;;
        # 模型切换命令
        "glm"|"glm5")
            emit_env_exports glm
            ;;
        "open")
            emit_env_exports open "${2:-}"
            ;;
        "env")
            shift
            emit_env_exports "${1:-}" "${2:-}"
            ;;
        "project")
            shift
            local action="${1:-}"
            case "$action" in
                "glm")
                    project_write_glm_settings
                    ;;
                "reset")
                    project_reset_settings
                    ;;
                *)
                    echo -e "${RED}❌ $(t 'unknown_option'): project $action${NC}" >&2
                    echo -e "${YELLOW}💡 Usage: claude-switch project [glm|reset]${NC}" >&2
                    return 1
                    ;;
            esac
            ;;
        "user")
            shift
            local user_action="${1:-}"
            case "$user_action" in
                "glm"|"glm5")
                    user_write_settings "$user_action"
                    ;;
                "reset")
                    user_reset_settings
                    ;;
                ""|"help"|"-h"|"--help")
                    user_show_usage
                    ;;
                *)
                    echo -e "${RED}❌ $(t 'unknown_option'): user $user_action${NC}" >&2
                    user_show_usage
                    return 1
                    ;;
            esac
            ;;
        "status"|"st")
            show_status
            ;;
        "config"|"cfg")
            edit_config
            ;;
        "setup"|"configure")
            shift
            # Check for --provider= flag
            if [[ "${1:-}" =~ ^--provider=(.+)$ ]]; then
                run_wizard "${BASH_REMATCH[1]}"
            else
                run_wizard
            fi
            ;;
        "update-config"|"update")
            update_config
            ;;
        "help"|"-h"|"--help")
            show_help
            ;;
        *)
            echo -e "${RED}❌ $(t 'unknown_option'): $1${NC}" >&2
            echo "" >&2
            show_help >&2
            return 1
            ;;
    esac
}

# 执行主函数
main "$@"
