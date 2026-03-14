#!/usr/bin/env bash
# Claude Code status line — context bar + session duration + rate limit bars + effort + extra usage
set -f  # disable globbing

input=$(cat)
if [ -z "$input" ]; then printf "Claude"; exit 0; fi

# Ensure jq is in PATH (Homebrew locations)
export PATH="$PATH:/opt/homebrew/bin:/usr/local/bin"

# --- Extract fields ---
model=$(echo "$input" | jq -r '.model.display_name // "Claude"')
cwd=$(echo "$input" | jq -r '.cwd // .workspace.current_dir // ""')
dir=$(basename "$cwd")
vim_mode=$(echo "$input" | jq -r '.vim.mode // empty')
agent_name=$(echo "$input" | jq -r '.agent.name // empty')
session_id=$(echo "$input" | jq -r '.session_id // empty')
cost_usd=$(echo "$input" | jq -r '.cost.total_cost_usd // empty')

# Context window — real token counts (from reference project)
window_size=$(echo "$input" | jq -r '.context_window.context_window_size // empty')
used_pct=$(echo "$input" | jq -r '.context_window.used_percentage // empty')
input_tokens=$(echo "$input" | jq -r '.context_window.current_usage.input_tokens // 0')
cache_create=$(echo "$input" | jq -r '.context_window.current_usage.cache_creation_input_tokens // 0')
cache_read=$(echo "$input" | jq -r '.context_window.current_usage.cache_read_input_tokens // 0')
current_tokens=$(( input_tokens + cache_create + cache_read ))

# Compute percentage from real tokens if used_pct is missing
if [ -z "$used_pct" ] && [ -n "$window_size" ] && [ "$window_size" -gt 0 ] 2>/dev/null; then
  used_pct=$(awk "BEGIN {printf \"%.1f\", ($current_tokens / $window_size) * 100}")
fi

# Reasoning effort
effort_level=""
if [ -n "$CLAUDE_CODE_EFFORT_LEVEL" ]; then
  effort_level="$CLAUDE_CODE_EFFORT_LEVEL"
else
  settings_path="$HOME/.claude/settings.json"
  if [ -f "$settings_path" ]; then
    effort_val=$(jq -r '.effortLevel // empty' "$settings_path" 2>/dev/null)
    [ -n "$effort_val" ] && effort_level="$effort_val"
  fi
fi

# --- ANSI colors ---
RESET=$'\033[0m'
BOLD=$'\033[1m'
DIM=$'\033[2m'
FG_WHITE=$'\033[97m'
FG_CYAN=$'\033[96m'
FG_YELLOW=$'\033[93m'
FG_GREEN=$'\033[92m'
FG_RED=$'\033[91m'
FG_BLUE=$'\033[94m'
FG_MAGENTA=$'\033[95m'
FG_GRAY=$'\033[90m'
FG_ORANGE=$'\033[38;2;255;176;85m'

# --- Session duration tracking ---
SESSION_DIR="$HOME/.claude/statusline-sessions"
mkdir -p "$SESSION_DIR"
now_epoch=$(date +%s)
session_elapsed_secs=0

if [ -n "$session_id" ]; then
  safe_id=$(echo "$session_id" | tr -cd 'a-zA-Z0-9_-' | cut -c1-64)
  session_start_file="${SESSION_DIR}/start_${safe_id}"
  if [ ! -f "$session_start_file" ]; then
    echo "$now_epoch" > "$session_start_file"
  fi
  start_epoch=$(cat "$session_start_file" 2>/dev/null || echo "$now_epoch")
  session_elapsed_secs=$(( now_epoch - start_epoch ))
fi

fmt_duration() {
  local secs="$1"
  if [ -z "$secs" ] || [ "$secs" -le 0 ]; then printf "0m"; return; fi
  local mins=$(( secs / 60 ))
  local hrs=$(( mins / 60 ))
  local rem_mins=$(( mins % 60 ))
  if [ "$hrs" -gt 0 ]; then
    printf "%dh %dm" "$hrs" "$rem_mins"
  else
    printf "%dm" "$mins"
  fi
}

# --- Progress bar builder ---
build_bar() {
  local pct="$1"
  local bar_width="${2:-12}"
  local filled=0 empty=0

  if [ -n "$pct" ]; then
    filled=$(echo "$pct $bar_width" | awk '{v=int(($1/100)*$2+0.5); if(v>'"$bar_width"') v='"$bar_width"'; print v}')
    empty=$(( bar_width - filled ))
    [ $filled -lt 0 ] && filled=0
    [ $empty -lt 0 ] && empty=0
  else
    empty=$bar_width
  fi

  local bar_color="$FG_GREEN"
  if [ -n "$pct" ]; then
    local pct_int
    pct_int=$(echo "$pct" | awk '{printf "%.0f", $1}' 2>/dev/null || echo "0")
    if [ "$pct_int" -ge 90 ]; then bar_color="$FG_RED"
    elif [ "$pct_int" -ge 70 ]; then bar_color="$FG_ORANGE"
    elif [ "$pct_int" -ge 50 ]; then bar_color="$FG_YELLOW"
    fi
  fi

  local bar=""
  if [ "$filled" -gt 0 ]; then for i in $(seq 1 $filled); do bar="${bar}█"; done; fi
  if [ "$empty" -gt 0 ];  then for i in $(seq 1 $empty);  do bar="${bar}░"; done; fi
  printf "%s" "${bar_color}${bar}${RESET}"
}

fmt_tokens() {
  local n="$1"
  if [ -z "$n" ] || [ "$n" = "0" ]; then echo "-"; return; fi
  echo "$n" | awk '{
    if ($1 >= 1000000) printf "%.1fM", $1/1000000
    else if ($1 >= 1000) printf "%.0fk", $1/1000
    else printf "%s", $1
  }'
}

fmt_cost() {
  local n="$1"
  if [ -z "$n" ]; then return; fi
  echo "$n" | LC_NUMERIC=C awk '{printf "$%.2f", $1}'
}

# --- Cross-platform OAuth token resolution (from reference project) ---
get_oauth_token() {
  # 1. Env var override
  if [ -n "$CLAUDE_CODE_OAUTH_TOKEN" ]; then
    echo "$CLAUDE_CODE_OAUTH_TOKEN"; return 0
  fi
  # 2. macOS Keychain
  if command -v security >/dev/null 2>&1; then
    local blob
    blob=$(security find-generic-password -s "Claude Code-credentials" -w 2>/dev/null)
    if [ -n "$blob" ]; then
      local token
      token=$(echo "$blob" | jq -r '.claudeAiOauth.accessToken // empty' 2>/dev/null)
      if [ -n "$token" ] && [ "$token" != "null" ]; then echo "$token"; return 0; fi
    fi
  fi
  # 3. Credentials file
  local creds_file="${HOME}/.claude/.credentials.json"
  if [ -f "$creds_file" ]; then
    local token
    token=$(jq -r '.claudeAiOauth.accessToken // empty' "$creds_file" 2>/dev/null)
    if [ -n "$token" ] && [ "$token" != "null" ]; then echo "$token"; return 0; fi
  fi
  echo ""
}

# --- Cross-platform ISO to epoch ---
iso_to_epoch() {
  local iso_str="$1"
  # Try GNU date first
  local epoch
  epoch=$(date -d "${iso_str}" +%s 2>/dev/null)
  if [ -n "$epoch" ]; then echo "$epoch"; return 0; fi
  # BSD date (macOS)
  local stripped="${iso_str%%.*}"
  stripped="${stripped%%Z}"
  stripped="${stripped%%+*}"
  if [[ "$iso_str" == *"Z"* ]] || [[ "$iso_str" == *"+00:00"* ]]; then
    epoch=$(env TZ=UTC date -j -f "%Y-%m-%dT%H:%M:%S" "$stripped" +%s 2>/dev/null)
  else
    epoch=$(date -j -f "%Y-%m-%dT%H:%M:%S" "$stripped" +%s 2>/dev/null)
  fi
  [ -n "$epoch" ] && echo "$epoch"
}

fmt_countdown() {
  local iso="$1"
  [ -z "$iso" ] || [ "$iso" = "null" ] && return
  local target_epoch
  target_epoch=$(iso_to_epoch "$iso")
  [ -z "$target_epoch" ] && return
  local diff=$(( target_epoch - $(date +%s) ))
  [ "$diff" -le 0 ] && printf "now" && return
  local mins=$(( diff / 60 ))
  local hrs=$(( mins / 60 ))
  local rem_mins=$(( mins % 60 ))
  if [ "$hrs" -gt 0 ]; then
    printf "%dh%02dm" "$hrs" "$rem_mins"
  else
    printf "%dm" "$mins"
  fi
}

# --- Fetch rate limit data (cached) ---
USAGE_CACHE="/tmp/claude/statusline-usage-cache.json"
mkdir -p /tmp/claude

fetch_usage() {
  local COOLDOWN_FILE="/tmp/claude/statusline-usage-cooldown"
  local now_ts
  now_ts=$(date +%s)

  # Check cache freshness
  if [ -f "$USAGE_CACHE" ]; then
    local cache_mtime
    cache_mtime=$(stat -f %m "$USAGE_CACHE" 2>/dev/null || stat -c %Y "$USAGE_CACHE" 2>/dev/null)
    local cache_age=$(( now_ts - cache_mtime ))
    if [ "$cache_age" -lt 300 ]; then
      cat "$USAGE_CACHE"
      return
    fi
  fi

  # If in cooldown after rate limit, use stale cache
  if [ -f "$COOLDOWN_FILE" ]; then
    local cd_ts
    cd_ts=$(cat "$COOLDOWN_FILE" 2>/dev/null || echo "0")
    if [ $(( now_ts - cd_ts )) -lt 600 ]; then
      [ -f "$USAGE_CACHE" ] && cat "$USAGE_CACHE"
      return
    fi
    rm -f "$COOLDOWN_FILE"
  fi

  local token
  token=$(get_oauth_token)
  if [ -n "$token" ] && [ "$token" != "null" ]; then
    local response
    response=$(curl -s --max-time 5 \
      -H "Accept: application/json" \
      -H "Authorization: Bearer $token" \
      -H "anthropic-beta: oauth-2025-04-20" \
      "https://api.anthropic.com/api/oauth/usage" 2>/dev/null)
    if [ -n "$response" ] && echo "$response" | jq -e '.five_hour' >/dev/null 2>&1; then
      printf "%s" "$response" > "$USAGE_CACHE"
      printf "%s" "$response"
      return
    fi
    # Rate limited or error — enter 10min cooldown
    printf "%s" "$now_ts" > "$COOLDOWN_FILE"
  fi
  # Fallback to stale cache
  [ -f "$USAGE_CACHE" ] && cat "$USAGE_CACHE"
}

# --- Git branch + stats ---
git_branch=""
git_stats=""
if [ -n "$cwd" ] && [ -d "$cwd/.git" ]; then
  git_branch=$(GIT_OPTIONAL_LOCKS=0 git -C "$cwd" symbolic-ref --short HEAD 2>/dev/null)
  git_stats=$(GIT_OPTIONAL_LOCKS=0 git -C "$cwd" diff --numstat 2>/dev/null | awk '{a+=$1; d+=$2} END {if (a+d>0) printf "+%d -%d", a, d}')
fi

# --- Visible width (strip ANSI codes) ---
visible_len() {
  printf "%s" "$1" | sed $'s/\033\[[0-9;]*m//g' | wc -m | tr -d ' '
}

# --- Terminal width ---
term_cols=$(tput cols 2>/dev/null || echo 200)

# --- Build output in two parts ---
SEP="${FG_GRAY}│${RESET}"
line1=""
line2=""

# === LINE 1: session info ===

# 1. Directory
line1="${FG_CYAN}${BOLD} ${dir}${RESET}"

# 2. Git branch + stats
if [ -n "$git_branch" ]; then
  line1="${line1} ${SEP} ${FG_MAGENTA} ${git_branch}${RESET}"
  if [ -n "$git_stats" ]; then
    line1="${line1} ${DIM}(${RESET}${FG_GREEN}${git_stats%% *}${RESET} ${FG_RED}${git_stats##* }${RESET}${DIM})${RESET}"
  fi
fi

# 3. Model
line1="${line1} ${SEP} ${FG_BLUE}${model}${RESET}"

# 4. Effort level
if [ -n "$effort_level" ]; then
  case "$effort_level" in
    low)    line1="${line1} ${SEP} ${DIM}effort:low${RESET}" ;;
    medium) line1="${line1} ${SEP} ${FG_ORANGE}effort:med${RESET}" ;;
    high)   line1="${line1} ${SEP} ${FG_GREEN}effort:high${RESET}" ;;
  esac
fi

# 5. Agent name
if [ -n "$agent_name" ]; then
  line1="${line1} ${SEP} ${FG_YELLOW}agent:${agent_name}${RESET}"
fi

# 6. Vim mode
if [ -n "$vim_mode" ]; then
  if [ "$vim_mode" = "INSERT" ]; then
    line1="${line1} ${SEP} ${FG_GREEN}-- INSERT --${RESET}"
  else
    line1="${line1} ${SEP} ${FG_YELLOW}-- NORMAL --${RESET}"
  fi
fi

# 7. Context progress bar + tokens
if [ -n "$used_pct" ]; then
  pct_int=$(echo "$used_pct" | awk '{printf "%.0f", $1}' 2>/dev/null || echo "0")
  bar=$(build_bar "$used_pct" 20)
  if [ -n "$window_size" ] && [ "$window_size" -gt 0 ] 2>/dev/null; then
    if [ "$current_tokens" -gt 0 ] 2>/dev/null; then
      tokens_fmt=$(fmt_tokens "$current_tokens")
    else
      used_tokens=$(echo "$used_pct $window_size" | awk '{printf "%.0f", ($1/100)*$2}')
      tokens_fmt=$(fmt_tokens "$used_tokens")
    fi
    window_fmt=$(fmt_tokens "$window_size")
    line1="${line1} ${SEP} ctx ${bar} ${BOLD}${pct_int}%${RESET} ${FG_GRAY}(${tokens_fmt}/${window_fmt})${RESET}"
  else
    line1="${line1} ${SEP} ctx ${bar} ${BOLD}${pct_int}%${RESET}"
  fi
else
  line1="${line1} ${SEP} ${FG_GRAY}ctx ░░░░░░░░░░░░░░░░░░░░${RESET}"
fi

# 8. Session duration
if [ -n "$session_id" ] && [ "$session_elapsed_secs" -ge 0 ]; then
  duration_fmt=$(fmt_duration "$session_elapsed_secs")
  line1="${line1} ${SEP} ${FG_GRAY} ${duration_fmt}${RESET}"
fi

# === LINE 2: rate limits + cost ===

# 9. Rate limits from API
usage_json=$(fetch_usage)
if [ -n "$usage_json" ] && echo "$usage_json" | jq -e '.' >/dev/null 2>&1; then
  # 5-hour
  fh_pct=$(echo "$usage_json" | jq -r '.five_hour.utilization // empty')
  fh_reset=$(echo "$usage_json" | jq -r '.five_hour.resets_at // empty')
  if [ -n "$fh_pct" ]; then
    fh_int=$(echo "$fh_pct" | awk '{printf "%.0f", $1}' 2>/dev/null || echo "0")
    [ "$fh_int" -gt 100 ] && fh_int=100
    fh_bar=$(build_bar "$fh_int" 10)
    fh_countdown=""
    if [ -n "$fh_reset" ] && [ "$fh_reset" != "null" ]; then
      fh_countdown=" $(fmt_countdown "$fh_reset")"
    fi
    line2="${line2}${FG_GRAY}5h${RESET} ${fh_bar} ${BOLD}${fh_int}%${RESET}${FG_GRAY}${fh_countdown}${RESET}"
  fi

  # 7-day
  sd_pct=$(echo "$usage_json" | jq -r '.seven_day.utilization // empty')
  sd_reset=$(echo "$usage_json" | jq -r '.seven_day.resets_at // empty')
  if [ -n "$sd_pct" ]; then
    sd_int=$(echo "$sd_pct" | awk '{printf "%.0f", $1}' 2>/dev/null || echo "0")
    [ "$sd_int" -gt 100 ] && sd_int=100
    sd_bar=$(build_bar "$sd_int" 10)
    sd_countdown=""
    if [ -n "$sd_reset" ] && [ "$sd_reset" != "null" ]; then
      sd_countdown=" $(fmt_countdown "$sd_reset")"
    fi
    [ -n "$line2" ] && line2="${line2} ${SEP} "
    line2="${line2}${FG_GRAY}7d${RESET} ${sd_bar} ${BOLD}${sd_int}%${RESET}${FG_GRAY}${sd_countdown}${RESET}"
  fi

  # Sonnet 7-day limit
  sonnet_pct=$(echo "$usage_json" | jq -r '.seven_day_sonnet.utilization // empty')
  if [ -n "$sonnet_pct" ]; then
    sonnet_int=$(echo "$sonnet_pct" | awk '{printf "%.0f", $1}' 2>/dev/null || echo "0")
    [ "$sonnet_int" -gt 100 ] && sonnet_int=100
    sonnet_bar=$(build_bar "$sonnet_int" 10)
    [ -n "$line2" ] && line2="${line2} ${SEP} "
    line2="${line2}${FG_GRAY}sonnet${RESET} ${sonnet_bar} ${BOLD}${sonnet_int}%${RESET}"
  fi
fi

# 10. Session cost
cost_fmt=$(fmt_cost "$cost_usd")
if [ -n "$cost_fmt" ]; then
  [ -n "$line2" ] && line2="${line2} ${SEP} "
  line2="${line2}${FG_GRAY}${cost_fmt}${RESET}"
fi

# --- Combine: single line or two lines based on terminal width ---
if [ -n "$line2" ]; then
  combined="${line1} ${SEP} ${line2}"
  combined_len=$(visible_len "$combined")
  if [ "$combined_len" -gt "$term_cols" ]; then
    printf "%s\n %s\n" "${line1}" "${line2}"
  else
    printf "%s\n" "${combined}"
  fi
else
  printf "%s\n" "${line1}"
fi
