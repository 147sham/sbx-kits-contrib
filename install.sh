#!/usr/bin/env bash
# sbx-kits-contrib installer
#
#   curl -fsSL https://raw.githubusercontent.com/147sham/sbx-kits-contrib/main/install.sh | bash
#
# Sets up everything needed to run Claude Code in Docker Sandboxes with the
# kits in this repo:
#
#   1. checks the platform and installs missing prerequisites (git, jq, rsync, curl)
#   2. installs the sbx CLI if it is missing (Homebrew on macOS, Docker's apt repo on Linux)
#   3. optionally signs you in to Docker (sbx login)
#   4. allows this repo as a kit source in sbx (kit.allowedSources)
#   5. clones the repo to ~/.sbx-kits, or updates it
#   6. creates ~/.sbx-claude/projects (session mirror) and ~/.config/sbx-kits
#   7. adds the cc / cm / cr / cs helpers to your shell rc file
#   8. optionally installs agentsview and points it at the session mirror
#
# Safe to re-run: every step is idempotent. Environment overrides:
#
#   SBX_KITS_HOME        clone location            (default: ~/.sbx-kits)
#   SBX_KITS_GIT_URL     repo to clone             (default: https://github.com/147sham/sbx-kits-contrib.git)
#   SBX_KITS_RC          shell rc file to edit     (default: ~/.zshrc or ~/.bashrc, by $SHELL)
#   SBX_KITS_AGENTSVIEW  1 = install agentsview, 0 = skip   (default: ask)
#   SBX_KITS_LOGIN       1 = run sbx login,      0 = skip   (default: ask)
#
# The whole script is wrapped in main() so `curl | bash` reads it completely
# before anything runs; prompts read from the terminal, not stdin.
set -euo pipefail

SBX_KITS_HOME=${SBX_KITS_HOME:-$HOME/.sbx-kits}
SBX_KITS_GIT_URL=${SBX_KITS_GIT_URL:-https://github.com/147sham/sbx-kits-contrib.git}
SBX_KITS_MIRROR=$HOME/.sbx-claude
DOCS_INSTALL=https://docs.docker.com/ai/sandboxes/install/

# --- output helpers -----------------------------------------------------------
if [ -t 2 ]; then B=$'\033[1m'; G=$'\033[32m'; Y=$'\033[33m'; R=$'\033[31m'; D=$'\033[2m'; N=$'\033[0m'; else B= G= Y= R= D= N=; fi
step() { printf '\n%s==>%s %s%s%s\n' "$B" "$N" "$B" "$*" "$N" >&2; }
ok()   { printf '  %s✓%s %s\n' "$G" "$N" "$*" >&2; }
info() { printf '  %s→%s %s\n' "$D" "$N" "$*" >&2; }
warn() { printf '  %s!%s %s\n' "$Y" "$N" "$*" >&2; }
die()  { printf '\n%s✗ %s%s\n' "$R" "$*" "$N" >&2; exit 1; }

# ask PROMPT DEFAULT(y|n) -> 0 for yes, 1 for no. Without a terminal, returns the default.
ask() {
  local prompt=$1 default=$2 reply hint
  [ "$default" = y ] && hint='[Y/n]' || hint='[y/N]'
  if ( : </dev/tty ) 2>/dev/null; then
    printf '  %s? %s %s%s ' "$B" "$prompt" "$hint" "$N" >&2
    IFS= read -r reply </dev/tty || reply=
  else
    reply=
  fi
  reply=${reply:-$default}
  case $reply in y|Y|yes|YES) return 0 ;; *) return 1 ;; esac
}

have() { command -v "$1" >/dev/null 2>&1; }

main() {
  printf '%s\n' "${B}sbx-kits-contrib installer${N}" >&2

  # --- 1. platform + prerequisites ------------------------------------------
  step "Checking platform"
  local os arch
  os=$(uname -s); arch=$(uname -m)
  case $os in
    Darwin)
      ok "macOS ($arch)"
      [ "$arch" = arm64 ] || warn "Docker Sandboxes documents Apple silicon only; Intel Macs may not be supported. See $DOCS_INSTALL" ;;
    Linux)
      ok "Linux ($arch)"
      if [ -e /dev/kvm ]; then
        [ -w /dev/kvm ] || warn "/dev/kvm is not writable by you. Add yourself to the kvm group: sudo usermod -aG kvm \$USER (then log out and in)"
      else
        warn "/dev/kvm not found. Docker Sandboxes needs KVM; see $DOCS_INSTALL"
      fi ;;
    *) die "Unsupported platform: $os. See $DOCS_INSTALL" ;;
  esac

  step "Checking prerequisites (git, jq, rsync, curl)"
  local missing="" c
  for c in git jq rsync curl; do have "$c" || missing="$missing $c"; done
  if [ -z "$missing" ]; then
    ok "all present"
  else
    info "missing:$missing"
    if [ "$os" = Darwin ]; then
      have brew || die "Homebrew is needed to install$missing. Install it from https://brew.sh and re-run."
      # shellcheck disable=SC2086
      brew install $missing
    elif have apt-get; then
      # shellcheck disable=SC2086
      sudo apt-get update -qq && sudo apt-get install -y -qq $missing
    elif have dnf; then
      # shellcheck disable=SC2086
      sudo dnf install -y $missing
    else
      die "Please install$missing with your package manager and re-run."
    fi
    ok "installed$missing"
  fi

  # --- 2. sbx ----------------------------------------------------------------
  step "Checking the sbx CLI (Docker Sandboxes)"
  if have sbx; then
    ok "sbx $(sbx version 2>/dev/null | awk '/^sbx version/ {print $3; exit}')"
  else
    info "sbx not found; installing"
    if [ "$os" = Darwin ]; then
      have brew || die "Homebrew is needed to install sbx. Install it from https://brew.sh and re-run, or see $DOCS_INSTALL"
      brew trust docker/tap >/dev/null 2>&1 || true
      brew install docker/tap/sbx
    elif have apt-get; then
      info "adding Docker's apt repository (sudo)"
      curl -fsSL https://get.docker.com | sudo REPO_ONLY=1 sh
      sudo apt-get install -y docker-sbx
    else
      die "No supported installer for this Linux. Install sbx by hand: $DOCS_INSTALL"
    fi
    have sbx || die "sbx still not on PATH after install. Open a new shell and re-run, or see $DOCS_INSTALL"
    ok "sbx $(sbx version 2>/dev/null | awk '/^sbx version/ {print $3; exit}')"
  fi

  # --- 3. sign in (optional) ---------------------------------------------------
  step "Docker sign-in"
  if sbx ls -q >/dev/null 2>&1; then
    ok "already signed in"
  else
    case ${SBX_KITS_LOGIN:-} in
      0) info "skipped; run: sbx login" ;;
      1) sbx login ;;
      *) if ask "Sign in to Docker now (opens a browser)?" y; then sbx login; else info "later: sbx login"; fi ;;
    esac
  fi

  # --- 4. kit source allowlist ------------------------------------------------
  step "Allowing this repo as a kit source"
  local owner current updated
  owner=$(printf '%s' "$SBX_KITS_GIT_URL" | sed -E 's#^(https?://|git@|ssh://git@)##; s#:#/#; s#\.git$##' | awk -F/ '{print $1"/"$2"/"}')
  current=$(sbx settings get kit.allowedSources 2>/dev/null || true)
  printf '%s' "$current" | jq -e 'type == "array"' >/dev/null 2>&1 || current='["docker.io/"]'
  if printf '%s' "$current" | jq -e --arg o "$owner" 'index($o) != null' >/dev/null; then
    ok "$owner already allowed"
  else
    updated=$(printf '%s' "$current" | jq -c --arg o "$owner" '. + [$o]')
    if sbx settings set kit.allowedSources "$updated" >/dev/null 2>&1; then
      ok "added $owner (kit.allowedSources = $updated)"
    else
      warn "could not update kit.allowedSources. Run this yourself: sbx settings set kit.allowedSources '$updated'"
    fi
  fi

  # --- 5. clone / update -------------------------------------------------------
  step "Fetching the kits repo into $SBX_KITS_HOME"
  if [ -d "$SBX_KITS_HOME/.git" ]; then
    if git -C "$SBX_KITS_HOME" pull -q --ff-only 2>/dev/null; then ok "updated ($(git -C "$SBX_KITS_HOME" rev-parse --short HEAD))"
    else warn "could not update (offline?); keeping the existing clone"; fi
  else
    git clone -q "$SBX_KITS_GIT_URL" "$SBX_KITS_HOME"
    ok "cloned ($(git -C "$SBX_KITS_HOME" rev-parse --short HEAD))"
  fi
  [ -f "$SBX_KITS_HOME/scripts/sbx-kits.sh" ] || die "$SBX_KITS_HOME does not contain scripts/sbx-kits.sh; is SBX_KITS_GIT_URL right?"

  # --- 6. directories ----------------------------------------------------------
  step "Creating directories"
  mkdir -p "$SBX_KITS_MIRROR/projects" "$HOME/.config/sbx-kits"
  ok "$SBX_KITS_MIRROR/projects (sandbox session mirror)"
  ok "$HOME/.config/sbx-kits (remembered kit selection)"

  # --- 7. shell rc -------------------------------------------------------------
  step "Adding the cc / cm / cr / cs helpers to your shell"
  local rc home_expr begin end block
  if [ -n "${SBX_KITS_RC:-}" ]; then rc=$SBX_KITS_RC
  else case $(basename "${SHELL:-}") in
    zsh) rc=$HOME/.zshrc ;;
    bash) rc=$HOME/.bashrc ;;
    *) rc=$HOME/.profile; warn "unrecognised \$SHELL; using $rc" ;;
  esac; fi
  case $SBX_KITS_HOME in "$HOME"/*) home_expr="\$HOME${SBX_KITS_HOME#"$HOME"}" ;; *) home_expr=$SBX_KITS_HOME ;; esac
  begin='# >>> sbx-kits >>>'; end='# <<< sbx-kits <<<'
  block="$begin
# cc / cm / cr / cs helpers for Docker Sandboxes, self-updated from $SBX_KITS_GIT_URL
SBX_KITS_HOME=\"\${SBX_KITS_HOME:-$home_expr}\"
[ -d \"\$SBX_KITS_HOME/.git\" ] || git clone -q $SBX_KITS_GIT_URL \"\$SBX_KITS_HOME\"
SBX_KITS_AUTO_UPDATE=1
source \"\$SBX_KITS_HOME/scripts/sbx-kits.sh\"
$end"
  touch "$rc"
  if grep -qF "$begin" "$rc"; then
    awk -v b="$begin" -v e="$end" -v blk="$block" '$0 == b { print blk; skip = 1; next } $0 == e { skip = 0; next } !skip' "$rc" > "$rc.sbx-kits.tmp"
    mv "$rc.sbx-kits.tmp" "$rc"
    ok "refreshed the sbx-kits block in $rc"
  elif grep -q 'scripts/sbx-kits.sh' "$rc"; then
    warn "$rc already sources scripts/sbx-kits.sh outside the installer's markers; left as is"
  else
    printf '\n%s\n' "$block" >> "$rc"
    ok "appended to $rc"
  fi

  # --- 8. agentsview (optional) ------------------------------------------------
  step "Usage dashboard (agentsview)"
  local want_av
  case ${SBX_KITS_AGENTSVIEW:-} in
    1) want_av=1 ;;
    0) want_av=0 ;;
    *) if have agentsview; then want_av=1; ok "agentsview already installed"
       elif ask "Install agentsview to see sessions, tokens and cost across all sandboxes?" n; then want_av=1
       else want_av=0; fi ;;
  esac
  if [ "$want_av" = 1 ]; then
    if ! have agentsview; then
      info "installing agentsview (https://agentsview.io)"
      curl -fsSL https://agentsview.io/install.sh | bash
      have agentsview || warn "agentsview not on PATH yet; open a new shell (it installs to ~/.local/bin)"
    fi
    local cfg=$HOME/.agentsview/config.toml mirror='~/.sbx-claude/projects'
    mkdir -p "$(dirname "$cfg")"
    if [ ! -f "$cfg" ]; then
      printf '[agents.claude]\ndirs = ["~/.claude/projects", "%s"]\n' "$mirror" > "$cfg"
      ok "wrote $cfg"
    elif grep -qF "$mirror" "$cfg"; then
      ok "$cfg already lists $mirror"
    elif grep -qE '^[[:space:]]*dirs[[:space:]]*=[[:space:]]*\[' "$cfg"; then
      # Add the mirror to the existing dirs list; everything else in the file is left alone.
      sed -E -i.sbx-kits.bak "s#^([[:space:]]*dirs[[:space:]]*=[[:space:]]*\[[^]]*)\]#\1, \"$mirror\"]#" "$cfg" && rm -f "$cfg.sbx-kits.bak"
      ok "added $mirror to dirs in $cfg"
    else
      printf '\n[agents.claude]\ndirs = ["~/.claude/projects", "%s"]\n' "$mirror" >> "$cfg"
      ok "appended [agents.claude] to $cfg"
    fi
  else
    info "skipped (re-run with SBX_KITS_AGENTSVIEW=1 to add it later)"
  fi

  # --- done --------------------------------------------------------------------
  printf '\n%s%s✓ All set.%s\n\n' "$B" "$G" "$N" >&2
  printf '  Next:\n' >&2
  printf '    1. reload your shell:        %sexec %s%s\n' "$B" "$(basename "${SHELL:-sh}")" "$N" >&2
  printf '    2. go to a project:          %scd ~/code/my-project%s\n' "$B" "$N" >&2
  printf '    3. create its sandbox:       %scc%s      (pick the kits you want)\n' "$B" "$N" >&2
  printf '    4. run Claude in it:         %scr%s\n\n' "$B" "$N" >&2
  printf '  Docs: %s\n' "${SBX_KITS_GIT_URL%.git}#readme" >&2
}

main "$@"
