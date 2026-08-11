# claude-playwright-mcp

Adds the **[Playwright MCP](https://github.com/microsoft/playwright-mcp)** server (`@playwright/mcp`) to **Claude Code**. The agent can then drive a headless Chromium — navigate, click, type, fill forms, wait for elements, screenshot/PDF, and read a page's accessibility tree — all inside the sandbox.

## Usage

```console
$ sbx run claude --kit ./claude-playwright-mcp/ .
```

Or from this repository:

```console
$ sbx run --kit "git+https://github.com/docker/sbx-kits-contrib.git#dir=claude-playwright-mcp" claude
```

Confirm it inside the sandbox with `claude mcp list` (or `/mcp` in a session) — the server is named `playwright`. Then just ask the agent to open a page.

## What it does

Two install steps:

1. **Installs the server and its browser.** `npm install -g @playwright/mcp@latest`, then installs Chromium *and its system libraries* into `/opt/ms-playwright`. The browser is installed with the exact Playwright bundled inside `@playwright/mcp`, so the revision matches what the server launches at runtime.
2. **Registers the server**, at user scope, exactly as you would by hand:

   ```console
   $ claude mcp add --scope user playwright -- npx @playwright/mcp@latest --headless --no-sandbox --browser=chromium
   ```

### Why it's more than a one-liner

The bare `claude mcp add playwright npx @playwright/mcp@latest` needs two things a sandbox doesn't give it for free:

- **A browser with system libraries.** Playwright's Chromium needs apt-installed libraries, and `apt` needs **root** — the agent runs as uid 1000 and can't install them at runtime. So the kit installs the browser (and its libs) at build time as root. `PLAYWRIGHT_BROWSERS_PATH=/opt/ms-playwright` puts it where the agent user can see it.
- **`--headless --no-sandbox`.** The sandbox has no display server, and Chromium's own sandbox can't nest inside the container's unprivileged user. Without these flags the browser fails to launch.
- **`--browser=chromium`.** `@playwright/mcp` defaults to the `chrome` channel, which isn't installed — only Chromium is. Without this flag the server fails at launch looking for `/opt/google/chrome/chrome`.

Everything else is just the command you'd run yourself. To pin a version, replace `@latest` in both install steps.

### Network

`caps.network.allow` is the kit's complete outbound contract (CI runs under `deny-all`): the npm registry/CDN, Playwright's browser CDN (`cdn.playwright.dev`, the `prss.microsoft.com` fallback, and the `storage.googleapis.com` bucket it redirects to on amd64), and Ubuntu/Docker apt sources for the `--with-deps` system libraries. This covers installing and running Playwright — not the sites the browser visits, which must be allowed by the sandbox policy (`localhost` always works).

## Relationship to the `playwright` kit

This kit lets Claude **drive a browser via MCP**. The separate [`playwright`](../playwright/) kit installs the `playwright` CLI and `@playwright/test` for **writing and running** test suites. They're independent — add both if you want both.
