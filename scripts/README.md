# Scripts

Standalone utilities for kit authors and maintainers. Each script is self-contained — the Go ones have no module dependencies outside the standard library, so they run directly via `go run` without pulling in the rest of `sbx-kits-contrib`; the shell ones need only `bash`, `jq` and `rsync`.

## `sbx-kits.sh` — `cc` / `cm` / `cr` / `cs` shell helpers

Source it from `~/.zshrc` or `~/.bashrc`. Defines `cc` (pick kits, create a Claude sandbox), `cm` (recreate an existing sandbox with the current kits while keeping its Claude state), `cr` (run Claude in the current directory's sandbox) and `cs` (shell into it). Usage, the kit picker, and every `SBX_KITS*` environment knob are documented in the repo guide under [Quick start: shell helpers](../GUIDE.md#shell-helpers).

## `sbx-kit-pick` — interactive kit picker

Used by `cc` and `cm`, but standalone: lists every kit directory in the repo as a checklist (drawn with [gum](https://github.com/charmbracelet/gum) when installed, a bash menu otherwise; `SBX_KIT_PICK_UI=basic` forces the latter), remembers the last choice in `~/.config/sbx-kits/selected`, and prints the chosen kit names one per line on stdout (prompting goes to stderr and reads the terminal). `--all`, `--last` and `--kits a,b` skip the prompt; with no usable terminal it silently uses the default selection. `SBX_KITS_STATE` overrides the state file, which the tests use.

## `migrate-v1-to-v2.go` — v1 → v2 spec.yaml migration

Mechanical converter for kit authors moving from schemaVersion 1 to schemaVersion 2 of the unified kit spec. The script reads a kit's `spec.yaml`, applies the renames and shape changes that landed across the v2 migration's phases, writes the result back in place, and leaves a `.bak` of the original.

### Usage

```bash
go run scripts/migrate-v1-to-v2.go <path-to-kit-directory>
```

For a kit at `~/work/my-kit/`:

```bash
go run scripts/migrate-v1-to-v2.go ~/work/my-kit
```

The script writes:

- `~/work/my-kit/spec.yaml` — rewritten in place
- `~/work/my-kit/spec.yaml.bak` — copy of the original

If the spec is already v2 (no transforms apply), the script prints `no changes needed in <path>` and exits cleanly without writing a `.bak`. Running on a directory where `spec.yaml.bak` already exists is refused — clean the previous backup before re-running.

### What it migrates

The script grows with the migration. Today's transforms cover **Phase 1**:

| v1 spelling | v2 spelling | Notes |
|---|---|---|
| `kind: agent` | `kind: sandbox` | Top-level kind value |
| `agent:` block | `sandbox:` block | Top-level YAML key |
| `memory:` field | `agentContext:` field | Top-level YAML key |

Later phases extend the script as their PRs land. See [`docs/specs/2026-05-27-unified-kit-spec-v2.md`](https://github.com/docker/sandboxes/blob/main/docs/specs/2026-05-27-unified-kit-spec-v2.md) on docker/sandboxes for the migration roadmap and which transforms each phase adds.

### What it doesn't migrate

- **Engine-side workspace state** — sandboxes you've already created will have a `kits-memory/` directory in their workspace. The sandboxes engine handles that rename transparently on the next kit add/run; no need to migrate it manually.
- **The `settings:` block** — in v2 the per-kit container-settings behavior is lifted into the kit's own `initFiles`/`commands.startup` entries, not a spec-level field. The script can't auto-translate it (the v2 replacement is kit-side setup, not spec data), so it prints the settings deprecation/lift notice when it encounters a `settings:` block and leaves the rest of the spec transformed. Lift it yourself using the built-in kits (e.g. `sandboxlib/kit/agents/{claude,codex}/spec.yaml`) as templates; see the v2 spec doc's Phase 4 plan for the recipe.

### Tests

```bash
go test ./scripts/...
```

Golden-file tests live under `scripts/testdata/` — one v1 input fixture and one v2 expected fixture per scenario. To add a new transform: drop the v1 form into the input fixture, the expected output into the expected fixture, and the test compares byte-for-byte. The fixture format preserves comments, blank lines, and block-scalar formatting so the migration's whitespace fidelity is part of the contract.
