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
Claude Code session on the host (`~/.claude.json` as a single file,
plus the whole `~/.claude` directory, all read-only) — see the
`claude-bridge` service block in `../docker-compose.yml`. It does not
have a separate identity or API key: every request through the bridge
draws on that same account's usage/rate limits. The bridge's own
`--no-session-persistence` flag means it never needs to write back to
those files.

**`~/.claude` is mounted as a directory, not as individual files
inside it — this matters.** A single-file bind mount pins the
container to the inode that existed at mount/start time. The host's
OAuth refresh replaces `.credentials.json` atomically (unlink+rename),
which a single-file bind mount can't see: the container keeps reading
the old, now-dead token forever, and `claude` reports `API Error: 401
OAuth access token has been revoked` even though the host's real
session is perfectly fine. Mounting the parent directory avoids this —
a file replaced inside a mounted directory is visible immediately, no
container restart needed. (This bit us in production: `docker exec`
into the container and diffing its `.credentials.json` against the
host's showed two different tokens with different `expiresAt` values —
proof it was a stale mount, not an actual revocation. A container
restart alone fixed it temporarily; mounting the directory instead of
the two individual files inside it fixed it for good.)

If you ever see that exact "access token has been revoked" error and
`claude auth status` / a direct host-side `claude -p` call both work
fine, suspect this class of bug before suspecting real revocation —
diff the container's credential file against the host's.

## Config

`CLAUDE_BRIDGE_KEY` in `compose/.env` is the bearer token the bridge
itself expects on incoming requests — unrelated to the Claude account
auth above. Callers (e.g. an n8n HTTP Request node) send
`Authorization: Bearer <CLAUDE_BRIDGE_KEY>` to
`http://claude-bridge:8000/v1/chat/completions`.
