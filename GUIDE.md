# The Guide

Everything the [README](./README.md) leaves out: how the pieces fit together, every helper and kit in depth, using kits with plain `sbx`, and building, testing and shipping your own.

**Contents**

- [How it fits together](#how-it-fits-together)
- [Installation in detail](#installation-in-detail)
- [Shell helpers](#shell-helpers)
- [The kits](#the-kits)
- [Tracking sandbox usage with agentsview](#tracking-sandbox-usage-with-agentsview)
- [Migrating an existing sandbox](#migrating-an-existing-sandbox)
- [Using a kit](#using-a-kit) (with plain `sbx`)
- [Building your own kit](#building-your-own-kit)
- [Declare every domain your kit needs](#declare-every-domain-your-kit-needs)
- [Testing kits](#testing-kits)
- [Repository structure](#repository-structure)
- [Troubleshooting](#troubleshooting)

---

## How it fits together

```
 host                                          sandbox (microVM)
 ─────────────────────────────────────────     ──────────────────────────────────────
 ~/.sbx-kits/            clone of this repo    /home/agent/            the agent user
   scripts/sbx-kits.sh   cc cm cr cs             .claude/              Claude's state
   scripts/sbx-kit-pick  the kit picker            projects/           transcripts (block volume)
   <kit>/spec.yaml       kit definitions           statusline.sh       from claude-sbx-statusline
                                                   skills/             shared skills store (host mount)
 ~/.sbx-claude/projects  session mirror  <──── rsync loop from claude-sbx-session-sync
 ~/.config/sbx-kits/     last kit selection
 ~/code/my-project       your workspace   <───> /Users/you/code/my-project (same path)
```

**Docker Sandboxes** (`sbx`) boots a small Linux VM per sandbox, mounts your project into it at the same path it has on the host, runs the agent as an unprivileged `agent` user, and routes all network traffic through a policy proxy that denies by default.

**Kits** are folders with a `spec.yaml` (and optional `files/`). `sbx create --kit <ref>` reads them and applies what they declare: environment variables, install commands run once at creation, startup commands run on every boot, files dropped into the home directory, network domains to allow, and a paragraph of context for the agent. Kits in this repo are all `kind: mixin`, meaning they layer on top of the built-in `claude` agent rather than replacing it.

**The helpers** turn `sbx create` with eight `--kit` flags into `cc`. They live in this repo and load from a clone in `~/.sbx-kits` that keeps itself up to date.

**Session sync** solves one gap: Claude's transcripts live on a volume inside the VM. The `claude-sbx-session-sync` kit copies them out to `~/.sbx-claude/projects` so host tools like agentsview can read them.

## Installation in detail

The installer is [`install.sh`](./install.sh) at the repo root:

```bash
curl -fsSL https://raw.githubusercontent.com/147sham/sbx-kits-contrib/main/install.sh | bash
```

What each step does, in order:

1. **Platform check.** macOS on Apple silicon, or Linux with `/dev/kvm` accessible. Warns if `/dev/kvm` is missing or not writable (add yourself to the `kvm` group).
2. **Prerequisites.** `git`, `jq`, `rsync`, `curl`. Installs missing ones with Homebrew, apt, or dnf.
3. **`sbx`.** If absent: `brew trust docker/tap && brew install docker/tap/sbx` on macOS, or Docker's apt repository plus the `docker-sbx` package on Ubuntu. Existing installs are left alone.
4. **Docker sign-in** (asks, skipped when already signed in). Runs `sbx login`, which opens a browser.
5. **Kit allowlist.** `sbx` only installs kits from publishers in `kit.allowedSources`. The installer reads the current list and appends `github.com/147sham/` if missing.
6. **Clone.** `git clone` into `~/.sbx-kits`, or `git pull --ff-only` if it exists.
7. **Directories.** `~/.sbx-claude/projects` (session mirror) and `~/.config/sbx-kits` (remembered kit selection).
8. **Shell rc.** Appends a block between `# >>> sbx-kits >>>` and `# <<< sbx-kits <<<` markers to `~/.zshrc` or `~/.bashrc` (by `$SHELL`). Re-runs replace the block in place. If you had added a `source .../scripts/sbx-kits.sh` line by hand, it is left alone.
9. **agentsview** (asks). Installs it via its official script and adds `~/.sbx-claude/projects` to the `dirs` list in `~/.agentsview/config.toml`, editing only that line.

Environment overrides: `SBX_KITS_HOME` (clone location), `SBX_KITS_GIT_URL` (your fork), `SBX_KITS_RC` (rc file), `SBX_KITS_AGENTSVIEW=1|0` and `SBX_KITS_LOGIN=1|0` (answer the prompts up front, useful for scripted installs).

### Manual setup

If you would rather not run a script, the equivalent is:

```bash
sbx settings set kit.allowedSources '["docker.io/","github.com/147sham/"]'   # keep what is already listed
git clone https://github.com/147sham/sbx-kits-contrib.git ~/.sbx-kits
mkdir -p ~/.sbx-claude/projects
cat >> ~/.zshrc <<'EOF'
SBX_KITS_HOME="${SBX_KITS_HOME:-$HOME/.sbx-kits}"
[ -d "$SBX_KITS_HOME/.git" ] || git clone -q https://github.com/147sham/sbx-kits-contrib.git "$SBX_KITS_HOME"
SBX_KITS_AUTO_UPDATE=1
source "$SBX_KITS_HOME/scripts/sbx-kits.sh"
EOF
```

The rc block itself is what makes a fresh machine self-install: the clone happens the first time a shell starts.

## Shell helpers

Defined in [`scripts/sbx-kits.sh`](./scripts/sbx-kits.sh).

### `cc [workspace] [sbx create flags]`

Claude create. Runs the kit picker, then `sbx create --kit ... claude <workspace>`. The workspace defaults to `.`; anything after it is passed to `sbx create`, so `cc . --name demo` or `cc . --memory 8g` work. If `claude-sbx-session-sync` is among the chosen kits, `~/.sbx-claude` is added as an extra workspace, which is what makes the host directory visible inside the sandbox.

### `cr`, `cs`

`cr` is `sbx run claude`: runs Claude in the sandbox for the current directory, creating a default one if none exists. `cs` is `sbx exec -it claude-<dirname> -- bash`: a shell inside it.

### `cm <sandbox>`

Claude migrate. See [Migrating an existing sandbox](#migrating-an-existing-sandbox).

### The kit picker

[`scripts/sbx-kit-pick`](./scripts/sbx-kit-pick) lists every top-level directory that contains a `spec.yaml`, with the first line of its description:

```
Kits to load   ↑/↓ move · space/number toggle · a all · n none · Enter confirm · q quit
> [x]  1) claude-hide-autoupdate-warning   Suppresses Claude Code's "unable to auto-update" warning ...
  [ ]  2) claude-playwright-mcp            Adds the Playwright MCP server (@playwright/mcp) ...
```

Move with the arrow keys (or `j`/`k`), toggle the highlighted kit with space or any kit by its number, `a` for all, `n` for none, Enter to confirm, `q` or Esc to cancel. The choice is saved to `~/.config/sbx-kits/selected` and preselected next time; the first run preselects everything. Without a usable terminal (cron, an agent running `cc`) it uses the saved selection silently.

Standalone flags: `--all`, `--last`, `--kits a,b` (empty means none). It prints the chosen names one per line on stdout, so it is usable from other tooling.

### Environment knobs

| Variable | Effect |
| --- | --- |
| `SBX_KITS=a,b` | Skip the picker and load exactly these kits. `SBX_KITS=` (empty) means a plain Claude sandbox. |
| `SBX_KITS_LOCAL=1` | Load kits from the clone's directories instead of GitHub URLs. Faster, no allowlist needed, and what you want while developing a kit. |
| `SBX_KITS_URL` | The `git+https://...` URL kits are pulled from. Point it at your fork. |
| `SBX_KITS_DRY_RUN=1` | Print the `sbx create` command instead of running it. |
| `SBX_KITS_AUTO_UPDATE=1` | Before `cc`/`cm`, `git pull` the clone if the last pull is over an hour old (five-second stall timeout; offline just uses the cache). If the pull brought changes, the helpers re-source themselves. Set by the installer's rc block. |
| `SBX_KITS_HOME` | Where the clone lives (`~/.sbx-kits`). |

Sourcing `scripts/sbx-kits.sh` from a development checkout instead of the clone works too; auto-update stays off unless you set it.

## The kits

All kits are `kind: mixin` for the built-in `claude` agent. Each folder has a README with the full rationale; this is the short version.

| Kit | What it does | Notes |
| --- | --- | --- |
| [claude-hide-autoupdate-warning](./claude-hide-autoupdate-warning) | Sets `DISABLE_AUTOUPDATER=1` and merges `autoUpdaterStatus: disabled` into `~/.claude/settings.json`. | The binary is baked into the image, so the auto-updater can only ever fail. |
| [claude-playwright-mcp](./claude-playwright-mcp) | Installs `@playwright/mcp` and a matching headless Chromium into `/opt/ms-playwright`, registers it with `claude mcp add --scope user`. | Runs `--headless --no-sandbox --browser=chromium`. Sites must be allowed by network policy; `localhost` always works. |
| [claude-sbx-session-sync](./claude-sbx-session-sync) | Background loop that rsyncs `~/.claude/projects` into the `~/.sbx-claude` host mount every 20 s. | Needs `~/.sbx-claude` passed at `sbx create` time (`cc` does this). No-op otherwise. Nothing deleted on the host. |
| [claude-sbx-statusline](./claude-sbx-statusline) | Ships `~/.claude/statusline.sh` and points `statusLine` at it: whale, sandbox name, path, branch; model, context %, 5h/7d quota, cost. | Unicode separators need a Nerd Font on the host terminal. Quota segments appear for claude.ai subscribers only. |
| [git-ssh-sign](./git-ssh-sign) | System git config for SSH signing with a key command that reads the forwarded agent at signing time. | Run `ssh-add` on the host first. Works with any agent, not just Claude. |
| [github-ssh](./github-ssh) | Fetches GitHub's host keys from `api.github.com/meta` into `known_hosts`. | Avoids the interactive host-key prompt a sandbox cannot answer. |
| [matt-pocock-skills](./matt-pocock-skills) | Installs mattpocock/skills into `~/.claude/skills` with the `skills` CLI. | Run `/setup-matt-pocock-skills` once per repo. |
| [playwright](./playwright) | `playwright` CLI and `@playwright/test` pinned to 1.61.1, Chromium, and the apt libraries it needs. | Headless only. `NODE_PATH` makes zero-config spec files work. |

Kits compose additively: environment variables union (last wins), install and startup commands concatenate in `--kit` order, and allowed domains append. Two kits that both merge keys into `settings.json` (statusline and hide-autoupdate) do so with `jq`, so neither clobbers the other.

## Tracking sandbox usage with agentsview

[agentsview](https://github.com/kenn-io/agentsview) is a local web UI that indexes Claude Code transcripts and shows sessions, full-text search, token use and cost. By default it only sees the host's `~/.claude/projects`; sandboxes keep their transcripts on an internal volume the host cannot read. The `claude-sbx-session-sync` kit closes that gap.

**Install.** Say yes in the installer, or re-run it with `SBX_KITS_AGENTSVIEW=1`, or by hand:

```bash
curl -fsSL https://agentsview.io/install.sh | bash     # or: brew install --cask agentsview
```

**Configure.** `~/.agentsview/config.toml` must list the mirror alongside the host directory. The installer edits only the `dirs` line; by hand it is:

```toml
[agents.claude]
dirs = ["~/.claude/projects", "~/.sbx-claude/projects"]
```

**Run.** `agentsview serve` (foreground) or `agentsview daemon start`, then open <http://127.0.0.1:8080>.

**How the mirror works.** `cc` passes `~/.sbx-claude` to `sbx create` as an extra workspace, so it appears inside the sandbox at its host path. The kit's startup loop finds that mount in `/proc/mounts` and rsyncs `~/.claude/projects` into `<mount>/projects` every 20 seconds (`SANDBOX_SESSION_SYNC_INTERVAL` overrides). Because the sandbox mounts your project at the same path as the host, the mangled project directory name matches what host Claude Code would use, so agentsview groups sandbox sessions under the right project. Session files are UUID-named, so sandboxes never collide, and nothing is deleted on the host, so history outlives `sbx rm`. Delete `~/.sbx-claude/projects` to drop it.

The extra workspace can only be given at `sbx create` time. A sandbox created without it will not sync even if the kit is added later with `sbx kit add`; use `cm` to bring it across.

**Privacy.** Transcripts contain everything Claude read and wrote, including file contents. Mirroring them removes that isolation for the transcript data. Leave the kit unticked for sandboxes whose transcripts should stay inside.

## Migrating an existing sandbox

Sandboxes keep Claude's state (auto-memory, session transcripts, prompt history, plans, `settings.json`, `~/.claude.json`) on internal volumes, so recreating one from scratch loses it. `cm` carries it across:

```bash
cm claude-myproject
```

In order, it:

1. asks which kits to load (before touching anything, so Ctrl-C here is harmless);
2. looks up the workspace with `sbx ls --json`, starting the sandbox if it is stopped;
3. copies `~/.claude` and `~/.claude.json` out with `sbx cp` to `~/.sbx-claude/backup/<name>`, and seeds `~/.sbx-claude/projects` with the transcripts;
4. `sbx rm --force` the old sandbox and `cc` the new one;
5. copies the state back in and fixes ownership as root: transcripts and memory into `projects/`, plans, history, and two `jq` merges. For `settings.json`, kit-managed keys win over old ones (so the status line stays current) and your own keys are kept (model, effort level, permission mode). For `~/.claude.json` (MCP registrations, per-project state) old values win;
6. deletes the backup.

The new sandbox takes the default name `claude-<workspace basename>`. If the create step fails (a missing allowlist entry, say), the backup stays put and re-running the same `cm` resumes from the create step.

## Using a kit

You do not need the helpers to use a kit. Kits are passed to `sbx run` or `sbx create` via `--kit`, which accepts a local path, an OCI registry reference, a ZIP archive, or a `git+...` URL.

The most common form is a git URL targeting this repo:

```console
$ sbx run --kit "git+https://github.com/147sham/sbx-kits-contrib.git#dir=playwright" claude
```

The fragment after `#` accepts two parameters, both optional:

| Parameter | Purpose | Example |
| --- | --- | --- |
| `dir` | Subdirectory inside the repo containing the kit | `#dir=playwright` |
| `ref` | Git ref to check out: branch, tag, or commit SHA | `#ref=v1.0.0` |

Combine them with `&`:

```console
# Pin to a tag, the recommended form for production use
$ sbx run --kit "git+https://github.com/147sham/sbx-kits-contrib.git#ref=v0.2.0&dir=playwright" claude

# Track a branch (less stable; the kit may change under you)
$ sbx run --kit "git+https://github.com/147sham/sbx-kits-contrib.git#ref=main&dir=playwright" claude

# Pin to an exact commit SHA, fully reproducible
$ sbx run --kit "git+https://github.com/147sham/sbx-kits-contrib.git#ref=abc1234&dir=playwright" claude
```

Without `ref`, sbx clones the default branch shallowly. With a branch or tag, it clones at that ref shallowly. With a commit SHA, it clones fully and checks out the commit. SSH works for private repos: `git+ssh://git@github.com/...`.

For local development, point `--kit` at a directory:

```console
$ sbx run --kit ./playwright/ claude
```

Remote sources must be in `kit.allowedSources` (`sbx settings get kit.allowedSources`); local paths do not.

## Building your own kit

A kit is a directory at the repo root (lowercase, alphanumeric and hyphens) with a `spec.yaml` and an optional `files/` tree:

```
my-kit/
├── spec.yaml
├── README.md
└── files/
    └── home/          # copied to /home/agent/ in the container
        └── .config/my-tool/config.json
```

A minimal `spec.yaml`:

```yaml
schemaVersion: "1"
kind: mixin
name: my-kit
displayName: My Kit
description: "Short description of what this kit does (the picker shows the first line)"

requires:
  agent: claude          # optional: refuse to compose onto other agents

network:
  allowedDomains:
    - example.com

environment:
  variables:
    MY_CONFIG: "/home/agent/.config/my-tool/config.json"

commands:
  install:               # runs once at creation, as root by default
    - command: "pip install my-tool"
      user: "1000"       # or as the agent user
      description: Install my-tool
  startup:               # runs on every container start; must be idempotent
    - command: ["my-tool", "serve"]
      user: "1000"
      background: true
      description: Start my-tool

agentContext: |
  ## My tool
  One paragraph the agent reads every session about what this kit added.
```

Things that catch people, distilled from the kits here:

- **Install runs as root, the agent runs as uid 1000.** Anything installed to root's home is invisible to the agent. Install to a system path (see `PLAYWRIGHT_BROWSERS_PATH=/opt/ms-playwright` in the playwright kit) or `chown -R agent:agent` at the end.
- **Merge, do not overwrite, `~/.claude/settings.json`.** Other kits write it too. Use `jq '.key = value' f > tmp && mv tmp f` with the temp file in the same directory, as the statusline and hide-autoupdate kits do.
- **Startup commands run on every boot.** Write them to converge: `mkdir -p`, `|| true`, check-before-create. A background loop should exit cleanly when its precondition is missing (see session-sync).
- **Prefer `files/home` for static files** and reserve install scripts for logic. Executable bits may not survive the copy; invoke scripts via `bash path` rather than relying on `+x`.
- **`files/workspace/` overlays the user's repo** on every start. Rarely what you want.
- **Declare every domain** your install and startup hooks reach. Next section.
- **`sbx kit add` on a running sandbox** applies environment, files and commands but cannot add mounts or ports; those need a recreate.

The `skills/kit-author` folder holds a much deeper reference on the spec format (both the current `schemaVersion: "1"` and the upcoming v2), composition rules, credentials, and pitfalls. Claude Code loads it automatically as a skill when you work on a `spec.yaml` in this repo.

Once it works, add a README (see any kit for the shape: usage, how it works, requirements, cleanup) and it will show up in the picker automatically. Kits meant for everyone go through a PR; see [CONTRIBUTING.md](./CONTRIBUTING.md).

## Declare every domain your kit needs

A kit's `network.allowedDomains` is its **complete** outbound network contract. Sandboxes run with a deny-all default policy, so anything not listed is blocked at request time, and any failed request inside an install hook surfaces as `sbx create` failing.

The non-obvious trap is **package managers refreshing every configured source**, not just the one you added:

- `apt-get update` re-fetches metadata for every file in `/etc/apt/sources.list[.d/]`, including sources the base template added. If *any* of those returns non-2xx, `apt-get` exits non-zero even if the package you want is in a different source. For kits built on `*-docker` templates that means `download.docker.com` needs to be in your `allowedDomains` even if you are only installing something from Ubuntu's main archive.
- Ubuntu hosts amd64 packages on `archive.ubuntu.com` + `security.ubuntu.com` and arm64 packages on `ports.ubuntu.com`. List all three for cross-arch coverage; CI is amd64, your Mac is arm64.
- `npm install`, `pip install`, `cargo`, `go get` each have their own registry and content hosts (`registry.npmjs.org` plus `*.npmjs.org`; `pypi.org` plus `files.pythonhosted.org`; `crates.io` plus `static.crates.io`). The metadata host and the tarball host are usually different.
- Redirects count. Playwright's Chromium download on amd64 is a 302 from `cdn.playwright.dev` to `storage.googleapis.com`.

The fastest way to find out what a kit reaches is to create a sandbox with it and read the proxy log:

```bash
sbx create --kit ./my-kit --name probe claude /tmp/probe
sbx policy log probe
```

Every row under `Blocked requests` is a host your install or startup hook reached for. Add it to `allowedDomains`, `sbx rm --force probe`, and repeat until the list is empty.

## Testing kits

What works in this fork today:

```bash
sbx kit validate ./my-kit/                                  # schema and cross-field checks
SBX_KITS=my-kit SBX_KITS_LOCAL=1 cc /tmp/probe --name probe  # real sandbox from the local kit
sbx exec probe -- which my-tool                             # verify the outcome, not just exit codes
sbx policy log probe                                        # network contract
sbx rm --force probe
```

`Install commands completed` in the create output only means the commands exited 0. Always check the result inside the sandbox.

> **Note.** The upstream repo ships a Go test harness, the TCK (`tck/` package, `scripts/test-kit.sh`, `scripts/test-kit-e2e.sh`, and the `test-kit` / e2e jobs in `.github/workflows/tck.yml`). That package was removed from this fork when the kit set was trimmed, so those scripts and CI jobs currently have nothing to run against. The sections below describe the upstream harness for reference and for whenever it is restored; until then, validate with the commands above.

### TCK test coverage

The TCK validates a kit automatically against a fabricated `testcontainers-go` container: `spec.yaml` parses with required fields; network and credential policy are well-formed; install and startup commands are well-formed; declared environment variables are set in the container; files from `files/` land at the right paths; expected tmpfs mounts are present.

### End-to-end (e2e) tests

The optional e2e layer boots a **real `sbx` sandbox** from the kit, then verifies via `sbx exec` that every environment variable, every file under `files/home` and every `initFiles` entry, every declared tmpfs mount, and the rendered agent-context file actually landed. It catches what the fabricated container cannot: install commands failing under the non-root agent user, `${WORKDIR}` resolving differently than expected, memory blocks the engine never writes.

Prerequisites: `sbx` on `PATH`; a scoped daemon signed in once per machine (`sbx --app-name sbx-kits-contrib-tck login`); on Linux, `/dev/kvm` accessible. Locally:

```bash
cd my-kit && ../scripts/test-kit-e2e.sh        # applies deny-all on the scoped daemon, runs TestE2EKit
```

### Running in CI

Pull requests trigger the TCK automatically: kit changes test only the modified kit, `spec/` changes test every kit, each kit in its own runner. Two e2e legs run via the reusable `e2e.yml`: **`e2e-release`** against the latest tagged `sbx` (gates the PR through the stable `e2e` check) and **`e2e-nightly`** against the rolling nightly build (informational only). Both are skipped on fork PRs because GitHub does not expose the Docker Hub secrets there, so a local e2e run is mandatory before opening a PR from a fork.

## Repository structure

```
sbx-kits-contrib/
├── install.sh            # one-line installer
├── <kit-name>/           # one directory per kit: spec.yaml, README.md, files/
├── scripts/
│   ├── sbx-kits.sh       # cc / cm / cr / cs (sourced from ~/.sbx-kits)
│   ├── sbx-kit-pick      # interactive kit picker
│   ├── migrate-v1-to-v2.go   # spec.yaml v1 → v2 rewriter
│   └── test-kit*.sh      # upstream TCK wrappers (see Testing kits)
├── spec/                 # Go library: kit artifact types, loading, validation (v1 and v2 grammars)
├── skills/kit-author/    # deep reference on the spec format, loaded as a Claude Code skill
├── .github/workflows/    # CI
├── README.md             # the short version
├── GUIDE.md              # this file
└── CONTRIBUTING.md       # conventions for PRs, signing, sign-off
```

The `spec` package is importable (`github.com/docker/sbx-kits-contrib/spec`) for tooling that needs to parse or validate kits. `scripts/migrate-v1-to-v2.go` rewrites a v1 `spec.yaml` into the v2 grammar; see [`scripts/README.md`](./scripts/README.md).

## Troubleshooting

**`kit "..." cannot be installed — its source is not in your allowlist`.** Add the repo owner: `sbx settings set kit.allowedSources '[...existing..., "github.com/147sham/"]'`. The installer does this; re-run it if you skipped that step. `cm` resumes from its backup once fixed.

**`cc` says `sbx-kits: could not update ... (offline?)`.** Harmless. The helpers use the cached clone. `git -C ~/.sbx-kits pull` when you are back online, or just wait for the next `cc`.

**The status line shows boxes instead of separators.** Your terminal has no Nerd Font. Install one, or set `"charset": "text"` per the statusline kit README.

**Sessions do not appear in agentsview.** Check the kit was ticked (`sbx exec <name> -- pgrep -f sbx-session-sync`), that `~/.sbx-claude` is mounted (`sbx exec <name> -- grep sbx-claude /proc/mounts`), and that `~/.agentsview/config.toml` lists `~/.sbx-claude/projects`. A sandbox created without the extra workspace needs `cm`.

**Commit signing fails with "no keys in SSH agent".** `ssh-add ~/.ssh/id_ed25519` on the host, then retry inside the sandbox; `ssh-add -L` there should list the key.

**A kit's install failed with a proxy 403.** A domain is missing from `allowedDomains`. `sbx policy log <sandbox>` lists it. See [Declare every domain your kit needs](#declare-every-domain-your-kit-needs).

**`cm` was interrupted after removing the sandbox.** Nothing is lost: the backup is in `~/.sbx-claude/backup/<name>` with a `workspace` file. Run the same `cm <name>` again and it resumes.

**Something else.** `sbx diagnose` checks the installation. `sbx kit inspect ./kit --output json` shows how a kit is interpreted, including deprecation warnings.
