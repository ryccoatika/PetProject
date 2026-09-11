# Changelog

Notable changes to this project. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

The heading of the topmost released section is what the release workflow tags
and publishes, so a release is made by bumping `VERSION`, moving entries out of
Unreleased, and merging into `main`.

## [Unreleased]

### Added

- **About Desktop Pet** in the menu, using the standard macOS About panel. It
  shows the version, which skin or sprite pack is in use, and which agents are
  driving the pet.

### Changed

- Source layout and formatting are now decided by `swift-format`, whose config
  lives in `MacApp/.swift-format`. Generated code moved to
  `Sources/Pet/Generated/` and is excluded from it.
- Pull request checks are lint and build, nothing else.

### Fixed

- `pet version` reported a hardcoded `1.0`. The version is now generated from
  `VERSION` into the binary, so the CLI, the About panel and the app bundle
  cannot disagree.

## [1.0.0] - 2026-09-12

First release.

### Added

- A desktop pet for macOS, drawn entirely in code — a transparent, always-on-top
  window whose pose follows what a coding agent is doing: typing at a laptop
  while a tool runs, thinking between steps, alerting when it needs you,
  celebrating when a turn ends, then idling, wandering and sleeping.
- Agent plugins for **Claude Code**, **Codex**, **Gemini CLI** and **opencode**.
  Each agent's event names, timeout units and async support differ and are
  translated at install time.
- Spritesheet pets from [codex-pets.net](https://codex-pets.net), with all
  eleven atlas tracks driven — including Failed, Waiting and Review — installable
  from the menu or the CLI.
- Four drawn skins (tabby, dog, panda, dino) in a JSON `.petskin` format, with
  import and export.
- The `pet` command, which is the same binary as the app: status, start/stop,
  show/hide, tray, skins, packs, config folder, plugins and size.
- Drag the pet anywhere, double-click to toggle cursor chasing, resize from 50%
  to 200%, hide the pet or the menu bar icon.
- A drag-and-drop disk image installer; the app installs the `pet` command
  itself on first launch.

### Performance

- Loop rate follows the state: 2fps hidden, 3 asleep, 6 idle, 20 while working,
  30 only for movement. About 1.4% of a core idle and 0.1% hidden.
- Sprite cells are baked into their own bitmaps, after profiling showed a
  cropped `CGImage` re-locking the whole sheet on every draw.

[Unreleased]: https://github.com/ryccoatika/PetProject/compare/v1.0.0...HEAD
[1.0.0]: https://github.com/ryccoatika/PetProject/releases/tag/v1.0.0
