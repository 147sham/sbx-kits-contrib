<h1 align="center">🐳 sbx-kits-contrib</h1>

<p align="center">
  <b>Claude Code in Docker Sandboxes, batteries included.</b><br>
  One command to install. One command per project. Pick the extras you want.
</p>

<p align="center">
  <a href="https://docs.docker.com/ai/sandboxes/"><img alt="Docker Sandboxes" src="https://img.shields.io/badge/Docker-Sandboxes-2496ED?logo=docker&logoColor=white"></a>
  <a href="./LICENSE"><img alt="License" src="https://img.shields.io/badge/license-Apache--2.0-blue"></a>
  <a href="./GUIDE.md"><img alt="Guide" src="https://img.shields.io/badge/docs-GUIDE.md-8A2BE2"></a>
</p>

---

## ✨ What is this?

[Docker Sandboxes](https://docs.docker.com/ai/sandboxes/) run coding agents like Claude Code inside an isolated microVM, with your project mounted in and the network locked down. **Kits** are small, declarative add-ons that customise that sandbox: extra tools, MCP servers, skills, git config, a status line.

This repo is a curated set of kits for **Claude Code**, plus the glue that makes them effortless:

- 🧩 **Kits** you can mix and match: browser automation, Playwright MCP, commit signing, GitHub SSH, community skills, a sandbox-aware status line, and session mirroring.
- 🛠️ **Shell helpers** (`cc`, `cr`, `cs`, `cm`) that create, run, and migrate sandboxes with an interactive kit picker.
- 📊 **Usage tracking** across every sandbox with [agentsview](https://github.com/kenn-io/agentsview).
- ⚡ **A one-line installer** that sets up the whole thing, including `sbx` itself.

## 🚀 Install

```bash
curl -fsSL https://raw.githubusercontent.com/147sham/sbx-kits-contrib/main/install.sh | bash
```

That installs anything missing (`sbx`, `git`, `jq`, `rsync`), allows this repo as a kit source, clones it to `~/.sbx-kits`, creates the directories the kits need, and adds the helpers to your `~/.zshrc` or `~/.bashrc`. It asks before installing agentsview and before signing you in to Docker. Re-running is safe.

Then reload your shell:

```bash
exec zsh   # or: exec bash
```

> **Requirements:** macOS 14+ on Apple silicon, or Ubuntu 24.04+ with KVM. No Docker Desktop needed. Details in the [install guide](https://docs.docker.com/ai/sandboxes/install/).

## 🧰 Daily use

| Command | Does |
| --- | --- |
| `cc` | **create** a sandbox for the current directory, after asking which kits to load |
| `cr` | **run** Claude in that sandbox |
| `cs` | open a **shell** inside it |
| `cm <name>` | **migrate** an existing sandbox onto the current kits, keeping its memory and sessions |

A first project looks like this:

```bash
cd ~/code/my-project
cc          # arrows move, space toggles, Enter
cr          # Claude starts inside the sandbox
```

The picker remembers your last choice, so `cc` in the next project is just Enter:

```
Kits to load
> ✓ claude-hide-autoupdate-warning   Suppresses Claude Code's "unable to auto-update" warning ...
  • claude-playwright-mcp            Adds the Playwright MCP server to Claude Code ...
  ✓ claude-sbx-session-sync          Mirrors the sandbox's Claude Code transcripts to the host ...
  ✓ claude-sbx-statusline            Adds a two-line Claude Code status line ...
  ...
←↓↑→ navigate • x toggle • ctrl+a select all • enter submit
```

Skip the prompt with `SBX_KITS=claude-sbx-statusline,git-ssh-sign cc`. Every knob is in the [guide](./GUIDE.md#shell-helpers).

## 🧩 Kits

| Kit | What you get |
| --- | --- |
| 🔕 [claude-hide-autoupdate-warning](./claude-hide-autoupdate-warning) | Silences the "unable to auto-update" nag; the version is pinned by the image anyway |
| 🎭 [claude-playwright-mcp](./claude-playwright-mcp) | Lets Claude drive a headless Chromium: navigate, click, fill forms, screenshot |
| 📡 [claude-sbx-session-sync](./claude-sbx-session-sync) | Mirrors the sandbox's transcripts to the host so usage tools can see them |
| 📊 [claude-sbx-statusline](./claude-sbx-statusline) | Two-line status bar: sandbox name, path, branch, model, context, quotas, cost |
| ✍️ [git-ssh-sign](./git-ssh-sign) | Signs commits and tags with the SSH key forwarded from your host agent |
| 🐙 [github-ssh](./github-ssh) | Pre-trusts GitHub's host keys so clone and push never prompt |
| 🧠 [matt-pocock-skills](./matt-pocock-skills) | Installs Matt Pocock's Claude Code skills collection |
| 🧪 [playwright](./playwright) | The Playwright CLI and `@playwright/test` with Chromium, for writing and running e2e tests |

Every kit is a folder with a `spec.yaml` and a README explaining how it works. Want your own? See [Building your own kit](./GUIDE.md#building-your-own-kit).

## 📊 See your usage everywhere

Sandboxes keep Claude's transcripts on an internal volume, so tools on the host cannot see them. Tick **claude-sbx-session-sync** in the picker and every sandbox mirrors its sessions into `~/.sbx-claude/projects`. Say yes to agentsview in the installer (or run it again with `SBX_KITS_AGENTSVIEW=1`) and you get one dashboard for all of them:

```bash
agentsview daemon start     # then open http://127.0.0.1:8080
```

Sessions, full-text search, tokens and cost, per project, live. History survives `sbx rm`.

## 💡 Tips

- **Already have sandboxes?** `cm claude-myproject` recreates one with the current kits and carries its auto-memory, sessions, history and settings across. Stopped sandboxes are started automatically.
- **Nerd Font.** The status line uses unicode separators and icons. Install a [Nerd Font](https://www.nerdfonts.com/) in your terminal, or set `"charset": "text"` as described in the [kit README](./claude-sbx-statusline).
- **Offline?** Everything keeps working. The helpers try to update themselves before `cc`/`cm` and fall back to the cached copy if they cannot.
- **Network is deny-by-default.** Sites a sandbox reaches must be allowed by kits or your `sbx policy`. `sbx policy log <sandbox>` shows what was blocked.
- **Signing commits** needs your key loaded on the host: `ssh-add ~/.ssh/id_ed25519`. Then `git log --show-signature -1` inside the sandbox proves it.
- **Something odd?** `sbx diagnose` first, then the [troubleshooting section](./GUIDE.md#troubleshooting).

## 📚 Learn more

- [**GUIDE.md**](./GUIDE.md): how the pieces fit together, every helper and kit in depth, using kits with plain `sbx`, building and testing your own kits, CI.
- [**CONTRIBUTING.md**](./CONTRIBUTING.md): conventions for adding a kit or a fix.
- [Docker Sandboxes docs](https://docs.docker.com/ai/sandboxes/): the platform underneath.

## 🙏 Credits

Forked from [docker/sbx-kits-contrib](https://github.com/docker/sbx-kits-contrib) via [pbexe](https://github.com/pbexe/sbx-kits-contrib). Kits are experimental and the format may change as Docker Sandboxes evolves. Licensed under [Apache 2.0](./LICENSE).
