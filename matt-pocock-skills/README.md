# Matt Pocock Skills

Installs [Matt Pocock's Claude Code skills collection](https://github.com/mattpocock/skills) into `~/.claude/skills` inside a Claude Code sandbox.

## Usage

```bash
sbx run claude --kit ./matt-pocock-skills .
```

Or add to a running sandbox:

```bash
sbx kit add <sandbox-name> ./matt-pocock-skills
```

## What gets installed

The kit clones [`mattpocock/skills`](https://github.com/mattpocock/skills) at sandbox creation and copies the three stable categories into `~/.claude/skills`:

| Category | Skills |
|---|---|
| Engineering | `/ask-matt`, `/code-review`, `/codebase-design`, `/diagnosing-bugs`, `/domain-modeling`, `/grill-with-docs`, `/implement`, `/improve-codebase-architecture`, `/prototype`, `/research`, `/resolving-merge-conflicts`, `/setup-matt-pocock-skills`, `/tdd`, `/to-spec`, `/to-tickets`, `/triage`, `/wayfinder` |
| Productivity | `/grill-me`, `/grilling`, `/handoff`, `/teach`, `/writing-great-skills` |
| Miscellaneous | `/git-guardrails-claude-code`, `/migrate-to-shoehorn`, `/scaffold-exercises`, `/setup-pre-commit` |

The `in-progress` and `deprecated` categories are intentionally excluded.

## First-time setup

After starting the sandbox, run `/setup-matt-pocock-skills` once per repository. It asks which issue tracker you use (GitHub Issues, Linear, or local files) and where to store documentation, then writes a small config file so the other skills know how to file tickets and specs.

## How it works

The install hook runs a pinned `skills` CLI release as the agent user:

```bash
npx --yes skills@1.5.19 add mattpocock/skills \
	--skill '*' \
	--agent claude-code \
	--global \
	--copy \
	--yes
```

That combination matters:

- `--agent claude-code --global` installs directly into `~/.claude/skills` instead of doing a project-scoped multi-agent install.
- `--copy` keeps the sandbox self-contained instead of leaving skill symlinks behind.
- Pinning `skills@1.5.19` avoids build drift from future CLI changes.

This avoids the default `skills add` behavior of writing `.agents/skills/` and `skills-lock.json` into the current working tree, which can interfere with later build steps when the kit is installed during sandbox creation.

The `requires: agent: claude` field restricts composition to Claude Code sandboxes — the skills are Claude Code–specific and won't function in other agent environments.
