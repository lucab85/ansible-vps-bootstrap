# claude-bridge (compose service)

Runs [lucab85/claude-bridge](https://github.com/lucab85/claude-bridge) —
a FastAPI wrapper that exposes a local Claude Code CLI as an
OpenAI-compatible `/v1/chat/completions` API — as a container in this
stack, reachable by other services (n8n) at `http://claude-bridge:8000`.

`claude_openai_bridge.py` and `Dockerfile` here are a synced copy of that
repo — same review applies (subprocess called with an argument list, not
a shell, so no injection risk from message content; tools and MCP
explicitly disabled on every invocation).

## Why a copied binary instead of installing at build time

The image doesn't run the official installer script during `docker build`
— it `COPY`s an already-extracted `claude` binary in instead
(`claude-bin`, gitignored, ~215MB, not committed here). That binary only
depends on glibc/libpthread/libm/librt/libdl (checked with `ldd`), so any
recent glibc-based image works without reinstalling anything.

**To (re)build this image, first extract the binary from an authenticated
host running Claude Code:**

```bash
# on the host where `claude` is already installed and logged in
cp "$(readlink -f "$(which claude)")" compose/claude-bridge/claude-bin
chmod +x compose/claude-bridge/claude-bin
```

Then `docker compose build claude-bridge`.

## Authentication

The container mounts the **same OAuth session** as the interactive
Claude Code session on the host (`~/.claude.json`,
`~/.claude/.credentials.json`, `~/.claude/settings.json`, all read-only)
— see the `claude-bridge` service block in `../docker-compose.yml`. It
does not have a separate identity or API key: every request through the
bridge draws on that same account's usage/rate limits. The bridge's own
`--no-session-persistence` flag means it never needs to write back to
those files.

If the host's Claude Code session ever re-authenticates (new OAuth
token), the container picks it up automatically on its next request —
no rebuild needed, since the files are mounted, not copied in.

## Config

`CLAUDE_BRIDGE_KEY` in `compose/.env` is the bearer token the bridge
itself expects on incoming requests — unrelated to the Claude account
auth above. Callers (e.g. an n8n HTTP Request node) send
`Authorization: Bearer <CLAUDE_BRIDGE_KEY>` to
`http://claude-bridge:8000/v1/chat/completions`.
