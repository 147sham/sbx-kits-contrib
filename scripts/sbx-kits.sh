# Shell helpers for sbx-kits-contrib. The recommended way to load them is a
# self-maintaining clone: put this in ~/.zshrc or ~/.bashrc and the helpers
# install themselves on first use and pull updates before each cc / cm.
#
#   SBX_KITS_HOME="${SBX_KITS_HOME:-$HOME/.sbx-kits}"
#   [ -d "$SBX_KITS_HOME/.git" ] || git clone -q https://github.com/147sham/sbx-kits-contrib.git "$SBX_KITS_HOME"
#   SBX_KITS_AUTO_UPDATE=1
#   source "$SBX_KITS_HOME/scripts/sbx-kits.sh"
#
# Sourcing from a development checkout works too (auto-update stays off unless
# SBX_KITS_AUTO_UPDATE=1 is set).
#
# Defines:
#   cc [workspace] [sbx create flags...]   claude create: pick kits, create a sandbox
#   cm <sandbox>                           claude migrate: recreate with current kits, keep Claude state
#   cr                                     claude run: run Claude in the sandbox for the current dir
#   cs                                     claude shell: bash inside the sandbox for the current dir
#
# Environment:
#   SBX_KITS=a,b        skip the picker and load exactly these kits ("" = none)
#   SBX_KITS_LOCAL=1    load kits from this clone instead of GitHub (no allowlist needed)
#   SBX_KITS_URL=...    git+ URL of the kits repo (default: this repo on GitHub)
#   SBX_KITS_DRY_RUN=1  print the sbx create command instead of running it
#   SBX_KITS_AUTO_UPDATE=1  git pull the clone (at most hourly) before cc / cm

if [ -n "${ZSH_VERSION:-}" ]; then
  SBX_KITS_REPO=${SBX_KITS_REPO:-$(cd "$(dirname "$(eval 'echo ${(%):-%x}')")/.." && pwd)}
else
  SBX_KITS_REPO=${SBX_KITS_REPO:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}
fi
SBX_KITS_URL=${SBX_KITS_URL:-git+https://github.com/147sham/sbx-kits-contrib.git}

# Pull the clone if auto-update is on and the last pull is over an hour old.
# Offline or slow: give up after a few seconds and use the cached copy. If the
# pull brought changes, re-source this file so the new helpers take effect.
_sbx_kits_update() {
  [ -n "${SBX_KITS_AUTO_UPDATE:-}" ] && [ -d "$SBX_KITS_REPO/.git" ] || return 0
  local stamp=$SBX_KITS_REPO/.git/sbx-kits-updated before after
  [ -z "$(find "$stamp" -mmin -60 2>/dev/null)" ] || return 0
  before=$(git -C "$SBX_KITS_REPO" rev-parse HEAD 2>/dev/null)
  if git -c http.lowSpeedLimit=1000 -c http.lowSpeedTime=5 -C "$SBX_KITS_REPO" pull -q --ff-only >/dev/null 2>&1; then
    touch "$stamp"
    after=$(git -C "$SBX_KITS_REPO" rev-parse HEAD 2>/dev/null)
    if [ "$before" != "$after" ]; then
      echo "sbx-kits: updated $SBX_KITS_REPO (${before:0:7} -> ${after:0:7})" >&2
      source "$SBX_KITS_REPO/scripts/sbx-kits.sh"
    fi
  else
    echo "sbx-kits: could not update $SBX_KITS_REPO (offline?); using the cached copy" >&2
  fi
}

# cc — claude create. First arg is the workspace (default .); any further args
# are passed to `sbx create` (e.g. --name foo). Runs the kit picker unless
# SBX_KITS is set. If claude-sbx-session-sync is among the chosen kits,
# ~/.sbx-claude is passed as an extra workspace so it can mirror transcripts.
cc() {
  local ws=. k picked extra=
  _sbx_kits_update
  [ $# -gt 0 ] && { ws=$1; shift; }
  if [ -n "${SBX_KITS+x}" ]; then
    picked=$("$SBX_KITS_REPO/scripts/sbx-kit-pick" --kits "$SBX_KITS") || return 1
  else
    picked=$("$SBX_KITS_REPO/scripts/sbx-kit-pick") || return 1
  fi
  local -a args
  args=()
  while IFS= read -r k; do
    [ -n "$k" ] || continue
    if [ -n "${SBX_KITS_LOCAL:-}" ]; then
      args+=(--kit "$SBX_KITS_REPO/$k")
    else
      args+=(--kit "$SBX_KITS_URL#dir=$k")
    fi
    [ "$k" = claude-sbx-session-sync ] && extra=$HOME/.sbx-claude
  done <<EOF
$picked
EOF
  [ -n "$extra" ] && mkdir -p "$extra"
  if [ -n "${SBX_KITS_DRY_RUN:-}" ]; then
    printf '%q ' sbx create "${args[@]}" "$@" claude "$ws" ${extra:+"$extra"}; echo
    return 0
  fi
  sbx create "${args[@]}" "$@" claude "$ws" ${extra:+"$extra"}
}

# cm — claude migrate: recreate an existing sandbox with the current kits while
# keeping its Claude state (auto-memory, sessions, prompt history, plans,
# settings.json keys, ~/.claude.json). The new sandbox gets the default name
# claude-<workspace basename>. Kits are chosen before anything is touched. If
# the create or restore step fails, the backup stays in
# ~/.sbx-claude/backup/<name>; fix the cause and re-run the same `cm` to resume.
cm() {
  local old=$1 ws bk new kits
  [ -n "$old" ] || { echo "usage: cm <sandbox-name>" >&2; return 1; }
  _sbx_kits_update
  bk=$HOME/.sbx-claude/backup/$old
  ws=$(sbx ls --json | jq -r --arg n "$old" '.sandboxes[] | select(.name == $n) | .workspaces[0]')
  if [ -z "$ws" ] || [ "$ws" = null ]; then
    if [ -f "$bk/workspace" ]; then
      ws=$(cat "$bk/workspace")
      echo "cm: '$old' is already removed; resuming from backup in $bk"
    else
      echo "cm: sandbox '$old' not found and no backup in $bk" >&2; return 1
    fi
  fi
  if [ -n "${SBX_KITS+x}" ]; then
    kits=$SBX_KITS
  else
    kits=$("$SBX_KITS_REPO/scripts/sbx-kit-pick" | paste -sd, -) || return 1
  fi
  if [ ! -f "$bk/workspace" ]; then
    rm -rf "$bk" && mkdir -p "$bk/restore" "$HOME/.sbx-claude/projects" &&
      sbx cp "$old:/home/agent/.claude" "$bk/claude" &&
      { sbx cp "$old:/home/agent/.claude.json" "$bk/restore/claude.json" 2>/dev/null || true; } &&
      rsync -rt --exclude=lost+found "$bk/claude/projects/" "$bk/restore/projects/" &&
      rsync -rt "$bk/restore/projects/" "$HOME/.sbx-claude/projects/" &&
      { for f in history.jsonl plans settings.json; do
          [ -e "$bk/claude/$f" ] && cp -R "$bk/claude/$f" "$bk/restore/"; done; true; } &&
      printf '%s' "$ws" > "$bk/workspace" &&
      sbx rm --force "$old" || { echo "cm: backup failed; '$old' was not removed" >&2; return 1; }
  fi
  local SBX_KITS=$kits
  cc "$ws" || { echo "cm: create failed; backup kept in $bk — fix the cause and re-run: cm $old" >&2; return 1; }
  new=claude-$(basename "$ws")
  sbx cp "$bk/restore" "$new:/tmp/sbx-restore" &&
    sbx exec -u 0 "$new" -- sh -c '
      set -e
      r=/tmp/sbx-restore; h=/home/agent/.claude; mkdir -p "$h"
      [ -d "$r/projects" ] && cp -a "$r/projects/." "$h/projects/"
      [ -d "$r/plans" ] && { mkdir -p "$h/plans"; cp -a "$r/plans/." "$h/plans/"; }
      [ -f "$r/history.jsonl" ] && cp -a "$r/history.jsonl" "$h/"
      # settings.json: keep old keys, but let the kits win on the keys they set.
      [ -f "$r/settings.json" ] && { [ -f "$h/settings.json" ] || echo "{}" > "$h/settings.json";
        jq -s ".[0] * .[1]" "$r/settings.json" "$h/settings.json" > "$h/settings.json.tmp" && mv "$h/settings.json.tmp" "$h/settings.json"; }
      # ~/.claude.json (MCP registrations, per-project state): old values win.
      [ -f "$r/claude.json" ] && { [ -f /home/agent/.claude.json ] || echo "{}" > /home/agent/.claude.json;
        jq -s ".[1] * .[0]" "$r/claude.json" /home/agent/.claude.json > /tmp/claude.json.tmp && mv /tmp/claude.json.tmp /home/agent/.claude.json; }
      chown -R agent:agent "$h" /home/agent/.claude.json
      rm -rf "$r"' &&
    rm -rf "$bk" &&
    echo "cm: $old recreated as $new with Claude state restored"
}

# cr — claude run: run Claude in the sandbox for the current directory
alias cr="sbx run claude"

# cs — claude shell: open a bash shell inside the sandbox for the current directory
alias cs='sbx exec -it claude-$(basename "$PWD") -- bash'
