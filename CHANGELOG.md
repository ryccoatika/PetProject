# Changelog

Notable changes to this project. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

The heading of the topmost released section is what the release workflow tags
and publishes, so a release is made by bumping `VERSION`, moving entries out of
Unreleased, and merging into `main`.

## [Unreleased]

### Added

- Agent plugins for **Antigravity**, **Cursor** and **pi**. Antigravity's
  synchronous PreToolUse hook is answered with an allow decision so it never
  stalls, Cursor gets flat command hooks in `~/.cursor/hooks.json` (IDE and
  CLI both), and pi gets a generated TypeScript extension (pi 0.83+).
- **Check for Updates** in the menu, plus a quiet once-a-day check that adds
  an "Update available" row when a newer release is out. Nothing downloads
  itself — both link to the releases page.
- The menu bar icon can now be chosen: the app icon, the current skin
  (sprite pets draw their own idle frame), or any SF Symbol.

### Changed

- The default menu bar icon is the app icon rather than the 🐈 emoji.

## [1.0.0] - 2026-09-12

First release.

### Added

- A desktop pet for macOS, drawn entirely in code — a transparent, always-on-top
  window whose pose follows what a coding agent is doing: typing at a laptop
  while a tool runs, thinking between steps, alerting when it needs you,
  celebrating when a turn ends, then idling, wandering and sleeping.
- Agent plugins for **Claude Code**, **Codex**, **Gemini CLI** and **opencode**.
  Each agent's event names, timeout units and async support differ, and are
  translated at install time. Installing never disturbs another tool's hooks.
- Spritesheet pets from [codex-pets.net](https://codex-pets.net), with all
  eleven atlas tracks driven — including Failed, Waiting and Review —
  installable from the menu or the command line.
- Four drawn skins (tabby, dog, panda, dino) in a plain JSON `.petskin` format,
  with import and export.
- The `pet` command, which is the same binary as the app: status, start and
  stop, show and hide, the menu bar icon, skins, packs, config folder, agent
  plugins and size.
- Drag the pet anywhere, double-click it to toggle cursor chasing, resize it
  from 50% to 200%, hide the pet or its menu bar icon.
- An About panel naming the version, the skin in use and which agents are
  driving it.
- A drag-and-drop disk image; the app installs the `pet` command itself on
  first launch.

### Performance

- The loop rate follows what is happening: 2fps hidden, 3 asleep, 6 idle, 20
  while thinking or running a tool, 30 only for movement. About 1.4% of a core
  idle, 0.1% hidden.
- Sprite cells are baked into their own bitmaps, after profiling showed a
  cropped `CGImage` re-locking the whole 1536×2288 sheet on every draw.

### Known limitations

- The app is signed ad-hoc rather than notarised, so the first launch of a
  downloaded build needs System Settings → Privacy & Security → Open Anyway.
- macOS only. A mobile version is planned; skin files are meant to be shared
  between platforms.

[Unreleased]: https://github.com/ryccoatika/PetProject/compare/v1.0.0...HEAD
[1.0.0]: https://github.com/ryccoatika/PetProject/releases/tag/v1.0.0
