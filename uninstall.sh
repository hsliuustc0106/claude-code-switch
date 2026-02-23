#!/usr/bin/env bash
set -euo pipefail

# Uninstaller for Claude Switch
# - Removes claude-switch/claude-launch function blocks from shell rc files
# - Removes PATH-installed claude-switch/claude-launch wrappers (when safely identified)
# - Removes installed assets under standard data dirs
# - Cleans up legacy ccm/ccm installations

# New marks
BEGIN_MARK="# >>> claude-switch function begin >>>"
END_MARK="# <<< claude-switch function end <<<"

# Old ccm marks (for legacy cleanup)
OLD_BEGIN_MARK="# >>> ccm function begin >>>"
OLD_END_MARK="# <<< ccm function end <<<"

log_info() {
  echo "==> $*"
}

log_warn() {
  echo "Warning: $*" >&2
}

detect_rc_files() {
  local rc_files=()
  [[ -f "$HOME/.zshrc" ]] && rc_files+=("$HOME/.zshrc")
  [[ -f "$HOME/.zprofile" ]] && rc_files+=("$HOME/.zprofile")
  [[ -f "$HOME/.bashrc" ]] && rc_files+=("$HOME/.bashrc")
  [[ -f "$HOME/.bash_profile" ]] && rc_files+=("$HOME/.bash_profile")
  [[ -f "$HOME/.profile" ]] && rc_files+=("$HOME/.profile")
  echo "${rc_files[*]}"
}

remove_new_block() {
  local rc="$1"
  [[ -f "$rc" ]] || return 0
  if grep -qF "$BEGIN_MARK" "$rc"; then
    local tmp
    tmp="$(mktemp)"
    awk -v b="$BEGIN_MARK" -v e="$END_MARK" '
      $0==b {inblock=1; next}
      $0==e {inblock=0; next}
      !inblock {print}
    ' "$rc" > "$tmp" && mv "$tmp" "$rc"
    echo "🗑️  Removed claude-switch and claude-launch functions from: $rc"
  fi
}

remove_old_block() {
  local rc="$1"
  [[ -f "$rc" ]] || return 0
  if grep -qF "$OLD_BEGIN_MARK" "$rc"; then
    local tmp
    tmp="$(mktemp)"
    awk -v b="$OLD_BEGIN_MARK" -v e="$OLD_END_MARK" '
      $0==b {inblock=1; next}
      $0==e {inblock=0; next}
      !inblock {print}
    ' "$rc" > "$tmp" && mv "$tmp" "$rc"
    echo "🗑️  Removed legacy ccm/ccc functions from: $rc"
  fi
}

needs_sudo() {
  local dir="$1"
  [[ -d "$dir" && ! -w "$dir" ]]
}

run_cmd() {
  local dir="$1"
  shift
  if needs_sudo "$dir"; then
    sudo "$@"
  else
    "$@"
  fi
}

find_candidate_bin_dirs() {
  local bins=()
  if [[ -n "${XDG_BIN_HOME:-}" ]]; then
    bins+=("$XDG_BIN_HOME")
  fi
  bins+=("$HOME/.local/bin" "$HOME/bin" "/usr/local/bin")
  if command -v brew >/dev/null 2>&1; then
    bins+=("$(brew --prefix)/bin")
  fi
  echo "${bins[*]}"
}

is_claude_switch_wrapper() {
  local path="$1"
  [[ -f "$path" ]] || return 1
  if [[ -L "$path" ]]; then
    local target
    target="$(readlink "$path" 2>/dev/null || true)"
    if [[ "$target" == *"/switch-lib.sh" || "$target" == *".claude-switch/switch-lib.sh" ]]; then
      return 0
    fi
  fi
  if grep -q "claude-switch error: missing" "$path" && grep -q "SWITCH_LIB=" "$path"; then
    return 0
  fi
  return 1
}

is_claude_launch_wrapper() {
  local path="$1"
  [[ -f "$path" ]] || return 1
  if grep -q "claude-launch error: cannot find switch CLI" "$path"; then
    return 0
  fi
  return 1
}

# Legacy ccm/ccm wrapper detection
is_ccm_wrapper() {
  local path="$1"
  [[ -f "$path" ]] || return 1
  if [[ -L "$path" ]]; then
    local target
    target="$(readlink "$path" 2>/dev/null || true)"
    if [[ "$target" == *"/ccm.sh" || "$target" == *".ccm/ccm.sh" ]]; then
      return 0
    fi
  fi
  if grep -q "ccm error: missing" "$path" && grep -q "CCM_SH=" "$path"; then
    return 0
  fi
  return 1
}

is_ccc_wrapper() {
  local path="$1"
  [[ -f "$path" ]] || return 1
  if grep -q "ccc error: cannot find ccm CLI" "$path"; then
    return 0
  fi
  return 1
}

remove_wrappers() {
  local removed_any=false
  local bin_dirs
  bin_dirs=( $(find_candidate_bin_dirs) )
  local bin_dir
  for bin_dir in "${bin_dirs[@]:-}"; do
    [[ -d "$bin_dir" ]] || continue

    # New wrappers
    local claude_switch_path="$bin_dir/claude-switch"
    local claude_launch_path="$bin_dir/claude-launch"

    # Legacy wrappers
    local ccm_path="$bin_dir/ccm"
    local ccc_path="$bin_dir/ccc"

    if is_claude_switch_wrapper "$claude_switch_path"; then
      run_cmd "$bin_dir" rm -f "$claude_switch_path"
      echo "🗑️  Removed claude-switch wrapper: $claude_switch_path"
      removed_any=true
    fi
    if is_claude_launch_wrapper "$claude_launch_path"; then
      run_cmd "$bin_dir" rm -f "$claude_launch_path"
      echo "🗑️  Removed claude-launch wrapper: $claude_launch_path"
      removed_any=true
    fi

    # Legacy wrappers
    if is_ccm_wrapper "$ccm_path"; then
      run_cmd "$bin_dir" rm -f "$ccm_path"
      echo "🗑️  Removed legacy ccm wrapper: $ccm_path"
      removed_any=true
    fi
    if is_ccc_wrapper "$ccc_path"; then
      run_cmd "$bin_dir" rm -f "$ccc_path"
      echo "🗑️  Removed legacy ccc wrapper: $ccc_path"
      removed_any=true
    fi
  done

  if ! $removed_any; then
    log_warn "No PATH-installed wrappers detected"
  fi
}

remove_data_dirs() {
  # New data dirs
  local user_dir="${XDG_DATA_HOME:-$HOME/.local/share}/claude-switch"
  local home_dir="$HOME/.claude-switch"
  local system_dir="/usr/local/share/claude-switch"

  # Legacy data dirs
  local legacy_user_dir="${XDG_DATA_HOME:-$HOME/.local/share}/ccm"
  local legacy_home_dir="$HOME/.ccm"
  local legacy_system_dir="/usr/local/share/ccm"

  if [[ -d "$user_dir" ]]; then
    rm -rf "$user_dir"
    echo "🗑️  Removed claude-switch assets at: $user_dir"
  fi

  if [[ -d "$home_dir" ]]; then
    rm -rf "$home_dir"
    echo "🗑️  Removed claude-switch assets at: $home_dir"
  fi

  if [[ -d "$system_dir" ]]; then
    run_cmd "$system_dir" rm -rf "$system_dir"
    echo "🗑️  Removed system claude-switch assets at: $system_dir"
  fi

  # Legacy dirs
  if [[ -d "$legacy_user_dir" ]]; then
    rm -rf "$legacy_user_dir"
    echo "🗑️  Removed legacy ccm assets at: $legacy_user_dir"
  fi

  if [[ -d "$legacy_home_dir" ]]; then
    rm -rf "$legacy_home_dir"
    echo "🗑️  Removed legacy ccm assets at: $legacy_home_dir"
  fi

  if [[ -d "$legacy_system_dir" ]]; then
    run_cmd "$legacy_system_dir" rm -rf "$legacy_system_dir"
    echo "🗑️  Removed legacy system ccm assets at: $legacy_system_dir"
  fi
}

main() {
  local rc_files
  rc_files=( $(detect_rc_files) )
  local rc
  for rc in "${rc_files[@]:-}"; do
    remove_new_block "$rc"
    remove_old_block "$rc"
  done

  remove_wrappers
  remove_data_dirs

  echo "✅ Uninstall complete. Reload your shell if you used rc functions."
}

main "$@"
