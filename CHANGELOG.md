# Changelog

Notable changes to this project. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

The heading of the topmost released section is what the release workflow tags
and publishes, so a release is made by bumping `VERSION`, moving entries out of
Unreleased, and merging into `main`.

## [Unreleased]

## [1.0.5] - 2026-09-18

### Added

- **A log file** at `<configDir>/logs/pet.log`: launches, plugin changes,
  skin errors, sprite pack installs and removals, config moves, every update
  step, `pet` command failures and crashes land there, so a bug report can
  come with evidence. Rotates at 512 KB; the animation loop never writes to
  it. **Show Log File in Finder** in the About panel reveals it.
- **Restart Pet** in the menu, above Quit — hands over to a fresh copy of
  the app in place.
- **Hover the pet and it jumps** — whatever it was doing. **Dragging** plays
  the run animation in the direction it is pulled (sprite packs use their
  Run right/left tracks; drawn skins still dangle from the cursor).
- **create-pet** and **create-sprite**, installed with the plugin: ask the
  agent for a new drawn skin or a spritesheet pet and it knows the formats,
  the folders and the CLI. On Claude Code and Codex they land as SKILL.md
  skills (modelled on Codex's curated hatch-pet skill); Gemini CLI, opencode
  and Cursor get command files. On Codex, create-sprite rides the built-in
  **hatch-pet** skill (and its $imagegen system skill), then installs the
  hatched pet straight into the app.

### Changed

- The About panel's buttons are now a vertical list, and the config folder
  moved there from the Skin menu: the path is shown alongside **Open Config
  Folder** and **Change Config Folder…** (with **Use Default Location** when
  a custom folder is active, and a disabled note when `$PET_CONFIG_DIR`
  overrides it).

## [1.0.4] - 2026-09-17

### Added

- **Install updates in place**: when Check for Updates (or the menu's update
  row) finds a newer release, an Install Update button downloads it, verifies
  its published SHA-256 and its reported version, swaps the app bundle and
  relaunches — no browser, no quarantine prompt, settings and skins untouched.
  A failed check or download changes nothing and falls back to the releases
  page. Releases now ship a `.zip` alongside the `.dmg` for this, with the
  checksum in the release notes.

## [1.0.3] - 2026-09-17

### Added

- **Right-click the pet** for a small Behaviour menu: toggle chase cursor,
  antics when bored, and the activity bubbles in place, without a trip to the
  menu bar.

## [1.0.2] - 2026-09-16

### Added

- **Antics when bored** (on by default): a pet left idle acts on its own now
  and then — strolls anywhere across the screen, waves at you, or sulks with
  knitted brows after being ignored long enough. Two new drawn poses (waving,
  angry); sprite packs use their Waving and Failed tracks. Sleep still wins
  in the end, so the idle cost is unchanged. Toggle from the menu (**Antics
  When Bored**) or `pet antics on | off`.

## [1.0.1] - 2026-09-14

### Added

- Agent plugins for **Antigravity**, **Cursor** and **pi**. Antigravity's
  synchronous PreToolUse hook is answered with an allow decision so it never
  stalls, Cursor gets flat command hooks in `~/.cursor/hooks.json` (IDE and
  CLI both), and pi gets a generated TypeScript extension (pi 0.83+).
- **Check for Updates**, from a button in the About dialog, plus a quiet
  once-a-day check that adds an "Update available" row to the menu when a
  newer release is out. Nothing downloads itself — both link to the releases
  page.
- The menu bar icon can now be chosen: the app icon, the current skin, or any
  SF Symbol. With a sprite-pet skin the menu bar icon animates in step with
  the pet, following its current track and frame.
- **Activity bubbles**: a card above the pet's head names the project an
  agent is working in and says what is actually happening — the prompt it
  was given, the command it is running, the file it is editing — and
  concurrent sessions stack their cards. **Click a card** to raise the
  terminal or IDE running that session (falling back to opening its folder).
  Toggle from the menu (**Show Activity Bubbles**) or with `pet bubbles
  show | hide`. Driven by per-session files in `<configDir>/sessions/`,
  written by the same hooks.
- **Chime When an Agent Needs You** (menu, off by default): a sound the
  moment any session starts waiting on a permission. Claude Code's idle
  "waiting for your input" nudge is told apart from a real permission ask by
  its message, so a finished turn reads a calm "Waiting for your reply" rather
  than a lingering "Waiting for you", and does not chime or stand the pet up.
- The **menu bar icon** carries a live session count, red with a `!` when one
  needs you — glanceable from any Space.
- **Follow Session** (menu): pin the pose to one session, or leave it on
  *Most urgent* so the pet reflects whichever session most wants attention
  rather than whichever agent wrote last.
- `pet stats` and a line in About tally today's sessions, tools and active
  time.
- **Streaks**: a longer, bigger celebration after a clean run of tools, and a
  glummer, longer failed pose during a rough patch.
- **Throw the pet**: flick it and it tumbles through the air, squashes as it
  bounces off the screen edges, and flashes how fast you flung it (px/s, with
  a "whee!" that grows with the speed). With chase mode on it still throws,
  then heads back to the cursor.

### Changed

- The default menu bar icon is the app icon rather than the 🐈 emoji.
- The menu is grouped into **Appearance**, **Behaviour** and **Agent Plugin**,
  with SF Symbol icons, so the top level stays short as features grow.

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
