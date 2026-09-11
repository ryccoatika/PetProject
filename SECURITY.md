# Security

## What this app touches

Worth knowing, because a desktop pet writing to config files deserves scrutiny:

- **`~/.config/pet/`** — its own skins, sprite packs, preferences and the
  activity file.
- **Your agent's config** — only when you run `pet plugin install`. It adds
  hook entries that call `pet event <name>`, backs the file up to `*.bak-pet`
  first, and removes only entries whose program is the pet itself.
- **`/usr/local/bin/pet` or `~/.local/bin/pet`** — a symlink to the app binary,
  created on first launch. It never replaces another program called `pet`.
- **The network**, only when you install a sprite pack: a download from
  `codex-pets.net`, or a URL you pass explicitly.

It reads the hook payload your agent sends on stdin to learn which tool is
running. Nothing is sent anywhere, and there is no telemetry.

## The app is not notarised

Builds are signed ad-hoc, not with an Apple Developer ID. macOS will warn on
first launch and you may need right-click → Open. If that matters to you, build
it yourself from source — it takes one command.

## Reporting something

Open an issue if it is not sensitive. If it is, say so in the issue without the
details and we will find a private channel.
