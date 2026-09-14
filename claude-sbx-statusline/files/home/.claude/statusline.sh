#!/usr/bin/env bash
# Claude Code status line for Docker Sandboxes (two lines).
#   line 1:  🐳 Docker Sandboxes · SANDBOX · ~/path/to/workspace (branch*)
#   line 2:  MODEL · ctx NN%/Wk · 5h NN% · 7d NN% · $COST
# Receives the session JSON on stdin. Runs on every render, so each segment
# stays cheap: one jq pass, one or two git calls, no network.

input=$(cat)

# One jq pass extracts every field (one per line); renders run often, so avoid
# re-forking jq. Line-per-field read preserves empty fields (tab-splitting would
# collapse leading blanks, since tab is IFS whitespace).
{ read -r dir; read -r model; read -r pct; read -r winsz; read -r cost; read -r q5h; read -r q7d; } < <(printf '%s' "$input" | jq -r '
  .workspace.current_dir // .cwd // "",
  .model.display_name // "",
  .context_window.used_percentage // "",
  ((.context_window.context_window_size // 0) / 1000 | floor),
  .cost.total_cost_usd // 0,
  .rate_limits.five_hour.used_percentage // "",
  .rate_limits.seven_day.used_percentage // ""')
[ -z "$dir" ] && dir=$(pwd)

# ANSI colours
RST=$'\033[0m'; BOLD=$'\033[1m'; DIM=$'\033[2m'
CYAN=$'\033[36m'; YELLOW=$'\033[33m'; BLUE=$'\033[34m'
GREEN=$'\033[32m'; RED=$'\033[31m'; MAGENTA=$'\033[35m'
WHITE=$'\033[37m'; SEP=$'\033[90m'

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

# --- Context, colour-coded; blank early in a session ---
ctx_seg=""
if [ -n "$pct" ] && [ "$pct" != "null" ]; then
  p=${pct%.*}
  if   [ "$p" -ge 80 ]; then c=$RED
  elif [ "$p" -ge 50 ]; then c=$YELLOW
  else c=$GREEN; fi
  ctx_seg="${c}ctx ${p}%${DIM}/${winsz}k${RST}"
fi

# --- 5h and 7d quota percentages (claude.ai subscribers only) ---
q5h_seg=""
if [ -n "$q5h" ] && [ "$q5h" != "null" ]; then
  p5=${q5h%.*}
  if   [ "$p5" -ge 80 ]; then qc=$RED
  elif [ "$p5" -ge 50 ]; then qc=$YELLOW
  else qc=$GREEN; fi
  q5h_seg="${qc}5h ${p5}%${RST}"
fi
q7d_seg=""
if [ -n "$q7d" ] && [ "$q7d" != "null" ]; then
  p7=${q7d%.*}
  if   [ "$p7" -ge 80 ]; then qc=$RED
  elif [ "$p7" -ge 50 ]; then qc=$YELLOW
  else qc=$GREEN; fi
  q7d_seg="${qc}7d ${p7}%${RST}"
fi

# --- Session cost ---
cost_seg="${MAGENTA}$(printf '$%.2f' "$cost")${RST}"

line1=$(join "${BOLD}${CYAN}🐳 Docker Sandboxes${RST}" "${YELLOW}$(hostname)${RST}" "${BLUE}${show_dir}${RST}${git_seg}")
line2=$(join "$model_seg" "$ctx_seg" "$q5h_seg" "$q7d_seg" "$cost_seg")

printf '%s\n%s' "$line1" "$line2"
