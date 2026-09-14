# claude-sbx-statusline

A two-line [Claude Code status line](https://docs.claude.com/en/docs/claude-code/statusline)
for Docker Sandboxes. Compose this mixin onto the built-in `claude` agent and every session
renders where you are and what the session is costing:

```
🐳 Docker Sandboxes · claude-ava · ~/Documents/projs/ava (main*)
Fable 5 · effort xhigh · ctx ████████░░ 82%/1000k · 5h ████░░░░░░ 39% ↻ 2h13m · 7d ██░░░░░░░░ 23% · $307.72
```

## What you get

| Line | Segment | Shows |
| --- | --- | --- |
| 1 | whale + label | `🐳 Docker Sandboxes`, so a sandbox session is unmistakable |
| 1 | sandbox | the sandbox name, read from the container hostname |
| 1 | directory | the workspace path, with the host home prefix collapsed to `~` |
| 1 | git | the branch, with a red `*` when the working tree is dirty; blank outside a repo |
| 2 | model | the active model's display name |
| 2 | effort | the reasoning effort level (`low` to `max`); hidden when the model has no effort setting |
| 2 | context | ten-cell bar and percentage of the context window used, plus the window size in k tokens |
| 2 | 5h / 7d | bars and percentages of the 5-hour and 7-day quota used (claude.ai subscribers only; blank on API-key auth). The 5h segment adds `↻ 2h13m`, the time until that window resets |
| 2 | cost | session cost so far in USD |

Context and quota bars turn yellow at 50% and red at 80%, with the unused part dimmed. They use the same block characters as Claude Code's own `/usage` view.

The permission-mode line Claude Code draws below the status line (`bypass permissions on`,
background agent count) is Claude Code's own UI and needs no configuration here.

## Quick start

Pair the mixin with the `claude` agent via `--kit`:

```console
$ sbx run claude --kit ./claude-sbx-statusline .
```

Or pull it straight from this repo:

```console
$ sbx run claude --kit "git+https://github.com/147sham/sbx-kits-contrib.git#dir=claude-sbx-statusline" .
```

## Configuration

Everything lives in **`~/.claude/statusline.sh`** inside the sandbox. It is a plain bash script:
edit the `join` calls at the bottom to reorder or drop segments, or the colour variables near
the top to restyle. The next render picks the change up, no restart needed.

## How it works

- **`files/home/.claude/statusline.sh`** is copied to `~/.claude/statusline.sh` at sandbox start.
  It reads the session JSON Claude Code pipes to the status line command, pulls every field in
  a single `jq` pass, runs two `git` commands for the branch and dirty state, and prints two
  lines. No npm packages, no network calls.
- **The `install` hook** (run as root) merges the `statusLine` block into `~/.claude/settings.json`
  with `jq`:

  ```json
  {
    "statusLine": { "type": "command", "command": "bash /home/agent/.claude/statusline.sh" }
  }
  ```

  The script is invoked via `bash` so it works even if the copy loses its executable bit. The
  hook creates `settings.json` if missing and leaves every other key untouched (only
  `statusLine` is set, replacing a prior one if present), then `chown`s `~/.claude` back to
  the `agent` user. Re-running is idempotent. The temp file is created inside `~/.claude` so the
  final `mv` is an atomic same-filesystem rename rather than a cross-device copy.

## Requirements

`bash`, `jq` and `git`, all present on the `claude-code` base image. The kit declares no network
domains because nothing is downloaded. It declares `requires.agent: claude` and will error if
composed onto any other base agent.
