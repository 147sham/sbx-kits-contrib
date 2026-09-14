# claude-sbx-session-sync

A mixin for the built-in `claude` agent that mirrors the sandbox's Claude Code transcripts to
the host, so a usage viewer such as [agentsview](https://github.com/kenn-io/agentsview) can show
sessions, token use and cost across every sandbox in one place.

## Why this exists

Inside a sandbox, `~/.claude/projects` (where Claude Code writes one JSONL transcript per
session) lives on a per-sandbox block volume. The host cannot see it, `sbx` has no bind-mount
flag, and kits can only declare block or tmpfs volumes. So the data has to be pushed out.

`sbx create` does accept extra host paths as additional workspaces, mounted read-write at their
host path. This kit uses that: you hand it `~/.sbx-claude`, and a background loop inside the
sandbox rsyncs the transcripts into it.

## Quick start

1. Create the host directory once:

   ```console
   $ mkdir -p ~/.sbx-claude
   ```

2. Create the sandbox with the kit **and** the directory as an extra workspace (the last path):

   ```console
   $ sbx create --kit "git+https://github.com/147sham/sbx-kits-contrib.git#dir=claude-sbx-session-sync" \
       claude . ~/.sbx-claude
   $ sbx run claude
   ```

   The `cc` helper from the repo README does both steps for you whenever this kit is ticked in
   its kit picker.

3. Transcripts appear on the host within about 20 seconds of activity:

   ```
   ~/.sbx-claude/projects/<mangled-workspace-path>/<session-id>.jsonl
   ```

The extra workspace must be passed at `sbx create` time. Adding the kit to an existing sandbox
with `sbx kit add` will not create the mount, and the loop then exits at startup.

## What gets synced

Only `~/.claude/projects`. That is where the per-session transcripts live, and they carry the
token counts, model names and tool calls that usage viewers read. Credentials, settings and
caches stay inside the sandbox.

Sessions from every sandbox merge into one `projects` tree. The sandbox mounts the workspace at
the same path as the host, so the mangled project directory name matches what Claude Code on the
host would use, and a viewer groups them under the right project. Session files are UUID-named,
so two sandboxes on the same workspace never collide. Nothing is ever deleted on the host side,
which means the history of a sandbox survives `sbx rm`.

## How it works

- **The `install` hook** (run once as root) writes `/usr/local/bin/sbx-session-sync`, a short
  bash loop.
- **The `startup` hook** runs that script as the agent user, in the background, on every
  container start. The script finds the `~/.sbx-claude` mount by reading `/proc/mounts`
  (globbing `/Users/*` from inside the sandbox does not work), creates `<mount>/projects`, and
  then runs `rsync -rt` from `~/.claude/projects` into it every
  `SANDBOX_SESSION_SYNC_INTERVAL` seconds (default 20). If the mount is absent it logs one line
  and exits, so the kit is harmless on sandboxes created without the extra path.
- The loop logs to `/tmp/sbx-session-sync.log` inside the sandbox.

To change the interval, compose a later kit that sets `SANDBOX_SESSION_SYNC_INTERVAL`, or edit
the value in this kit's `environment.variables`.

## Viewing the data with agentsview

See [Tracking sandbox usage with agentsview](../GUIDE.md#tracking-sandbox-usage-with-agentsview)
in the repo guide for install steps and the config that points agentsview at `~/.sbx-claude`.

## Privacy note

Transcripts contain everything Claude read and wrote during a session, including file contents
from the workspace. Syncing them to the host removes that isolation for the transcript data.
That is the purpose of the kit, but it is worth being deliberate about: leave the kit out of
sandboxes whose transcripts should stay contained.

## Requirements

`bash`, `rsync` and `awk`, all present on the `claude-code` base image. No network domains.
Declares `requires.agent: claude`.

## Cleanup

Host state is `~/.sbx-claude`. Delete it to drop the mirrored history; the sandboxes are
unaffected and will repopulate it on their next sync pass.
