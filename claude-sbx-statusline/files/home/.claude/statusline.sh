#!/usr/bin/env bash
# Claude Code status line for Docker Sandboxes (two lines).
#   line 1:  🐳 Docker Sandboxes · SANDBOX · ~/path/to/workspace (branch*)
#   line 2:  MODEL · effort LEVEL · ctx ████░░ NN%/Wk · 5h ████░░ NN% ↻ 2h13m · 7d ████░░ NN% ↻ 3d04h · $COST
# Receives the session JSON on stdin. Runs on every render, so each segment
# stays cheap: one jq pass, one or two git calls, no network.

input=$(cat)

# One jq pass extracts every field (one per line); renders run often, so avoid
# re-forking jq. Line-per-field read preserves empty fields (tab-splitting would
# collapse leading blanks, since tab is IFS whitespace).
{ read -r dir; read -r model; read -r effort; read -r pct; read -r winsz; read -r cost; read -r q5h; read -r q5h_reset; read -r q7d; read -r q7d_reset; } < <(printf '%s' "$input" | jq -r '
  .workspace.current_dir // .cwd // "",
  .model.display_name // "",
  .effort.level // "",
  .context_window.used_percentage // "",
  ((.context_window.context_window_size // 0) / 1000 | floor),
  .cost.total_cost_usd // 0,
  .rate_limits.five_hour.used_percentage // "",
  .rate_limits.five_hour.resets_at // "",
  .rate_limits.seven_day.used_percentage // "",
  .rate_limits.seven_day.resets_at // ""')
[ -z "$dir" ] && dir=$(pwd)

# ANSI colours
RST=$'\033[0m'; BOLD=$'\033[1m'; DIM=$'\033[2m'
CYAN=$'\033[36m'; YELLOW=$'\033[33m'; BLUE=$'\033[34m'
GREEN=$'\033[32m'; RED=$'\033[31m'; MAGENTA=$'\033[35m'
WHITE=$'\033[37m'; SEP=$'\033[90m'

# bar PCT -> ten-cell progress bar (the same block characters Claude Code's own
# /usage view draws), filled part in the current colour, empty part dimmed.
bar() {
  local filled=$(( ($1 + 5) / 10 )) fill="" pad=""
  [ "$filled" -gt 10 ] && filled=10
  [ "$filled" -gt 0 ] && printf -v fill "%${filled}s" && fill=${fill// /█}
  [ "$filled" -lt 10 ] && printf -v pad "%$((10 - filled))s" && pad=${pad// /░}
  printf '%s%s%s%s' "$fill" "$DIM" "$pad" "$RST"
}

# level PCT -> colour by threshold (green < 50, yellow < 80, red)
level() {
  if   [ "$1" -ge 80 ]; then printf '%s' "$RED"
  elif [ "$1" -ge 50 ]; then printf '%s' "$YELLOW"
  else printf '%s' "$GREEN"; fi
}

# until_str EPOCH -> "3d04h" / "2h13m" / "45m" remaining; empty when past or unknown
until_str() {
  local now rem
  case $1 in ''|null) return ;; esac
  now=$(date +%s); rem=$(( ${1%.*} - now ))
  [ "$rem" -gt 0 ] || return
  if   [ "$rem" -ge 86400 ]; then printf '%dd%02dh' $((rem / 86400)) $((rem % 86400 / 3600))
  elif [ "$rem" -ge 3600 ]; then printf '%dh%02dm' $((rem / 3600)) $((rem % 3600 / 60))
  else printf '%dm' $((rem / 60)); fi
}

# join SEGMENTS... -> non-empty segments separated by " · "
join() {
  local out="" s
  for s in "$@"; do
    [ -z "$s" ] && continue
    if [ -z "$out" ]; then out="$s"; else out="${out}${SEP} · ${RST}${s}"; fi
  done
  printf '%s' "$out"
}

# --- Directory with the home prefix collapsed to ~ ---
# The sandbox mounts the workspace at its host path (e.g. /Users/me/proj), so
# $HOME (/home/agent) rarely matches. Collapse the in-container home first,
# then a macOS or Linux host home prefix.
show_dir=$dir
case "$dir" in
  "$HOME"|"$HOME"/*) show_dir="~${dir#"$HOME"}" ;;
  /Users/*/*|/home/*/*)
    rest=${dir#/*/}           # strip "/Users/" or "/home/"
    rest=${rest#*/}           # strip "<user>/"
    show_dir="~/${rest}" ;;
  /Users/*|/home/*) show_dir="~" ;;
esac

# --- Git branch + dirty marker (blank when not a repo) ---
git_seg=""
if branch=$(git -C "$dir" rev-parse --abbrev-ref HEAD 2>/dev/null); then
  if [ -n "$(git -C "$dir" status --porcelain 2>/dev/null)" ]; then
    git_seg=" ${GREEN}(${branch}${RED}*${GREEN})${RST}"
  else
    git_seg=" ${GREEN}(${branch})${RST}"
  fi
fi

# --- Model ---
model_seg=""
[ -n "$model" ] && model_seg="${BOLD}${WHITE}${model}${RST}"

# --- Effort level; absent when the model has no effort parameter ---
effort_seg=""
[ -n "$effort" ] && [ "$effort" != "null" ] && effort_seg="${CYAN}effort ${effort}${RST}"

# --- Context, colour-coded; blank early in a session ---
ctx_seg=""
if [ -n "$pct" ] && [ "$pct" != "null" ]; then
  p=${pct%.*}; c=$(level "$p")
  ctx_seg="${c}ctx $(bar "$p")${c} ${p}%${DIM}/${winsz}k${RST}"
fi

# --- 5h and 7d quota bars (claude.ai subscribers only), each with time to reset ---
q5h_seg=""
if [ -n "$q5h" ] && [ "$q5h" != "null" ]; then
  p5=${q5h%.*}; qc=$(level "$p5")
  q5h_seg="${qc}5h $(bar "$p5")${qc} ${p5}%${RST}"
  left=$(until_str "$q5h_reset")
  [ -n "$left" ] && q5h_seg="${q5h_seg} ${DIM}↻ ${left}${RST}"
fi
q7d_seg=""
if [ -n "$q7d" ] && [ "$q7d" != "null" ]; then
  p7=${q7d%.*}; qc=$(level "$p7")
  q7d_seg="${qc}7d $(bar "$p7")${qc} ${p7}%${RST}"
  left=$(until_str "$q7d_reset")
  [ -n "$left" ] && q7d_seg="${q7d_seg} ${DIM}↻ ${left}${RST}"
fi

# --- Session cost ---
cost_seg="${MAGENTA}$(printf '$%.2f' "$cost")${RST}"

line1=$(join "${BOLD}${CYAN}🐳 Docker Sandboxes${RST}" "${YELLOW}$(hostname)${RST}" "${BLUE}${show_dir}${RST}${git_seg}")
line2=$(join "$model_seg" "$effort_seg" "$ctx_seg" "$q5h_seg" "$q7d_seg" "$cost_seg")

printf '%s\n%s' "$line1" "$line2"
