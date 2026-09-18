# Architecture

One Swift binary, no dependencies, no package manager. This is how the pieces
fit together and, where a decision was not obvious, why it went the way it did.

## The shape of it

```
        coding agent                      the pet
   ┌────────────────────┐          ┌────────────────────┐
   │ Claude Code        │  hooks   │                    │
   │ Codex              ├─────────▶│  pet event <name>  │
   │ Gemini CLI         │          │         │          │
   │ opencode (JS)      │          │         ▼          │
   └────────────────────┘          │  ~/.config/pet/    │
                                   │       state        │
                                   │         │          │
                                   │         ▼  polled  │
                                   │   AppDelegate      │
                                   │      loop          │
                                   │         │          │
                                   │         ▼          │
                                   │   PetView draws    │
                                   │   a pose, or a     │
                                   │   sprite frame     │
                                   └────────────────────┘
```

The app knows nothing about any agent. It watches one file.

## One binary, three jobs

`Pet.app/Contents/MacOS/Pet` is also the `pet` command, symlinked into
`/usr/local/bin` or `~/.local/bin` on first launch. `main.swift` decides which
job to do:

| Invocation | What runs |
|---|---|
| `pet <command>` | `CLI.run` — the command line tool |
| `pet render \| icon \| dmgbg` | `Renderers` — offscreen PNGs for the build |
| no arguments, invoked as `Pet` | the app (this is how Finder and `open` launch it) |
| no arguments, invoked as `pet` | prints help |

The last two are decided by the name the binary was invoked under, not by
inspecting pipes or terminals: a Finder launch and a piped `pet | head` are
indistinguishable by `isatty`, and guessing got it wrong.

Because they are one binary, the CLI and the app cannot drift apart, and the
CLI can reuse the app's model types — `SkinStore`, `SpriteInstaller`,
`HookPlugin` — instead of reimplementing them.

## The activity contract

Everything an agent reports arrives as one line:

```
~/.config/pet/state          (or $PET_CONFIG_DIR/state)

EVENT|TOOL|EPOCH             e.g.  PreToolUse|Edit|1789137504
```

That is the whole interface. `pet event <name>` writes it, reading the hook
payload on stdin to pull out `tool_name`, and always exits 0 so it can never
fail a turn. Anything able to write a line of text can drive the pet — which is
why the opencode plugin, written in JavaScript, writes the file directly
instead of spawning a process.

The app polls the file ten times a second and maps the event to a pose:

| Event | Pose | Sprite track |
|---|---|---|
| `SessionStart` | wakes | Idle |
| `UserPromptSubmit`, `PostToolUse` | thinking | Review |
| `PreToolUse` | working, tool name in the pill | Running |
| `PostToolUseFailure`, `StopFailure` | failed | Failed |
| `Notification`, `PermissionRequest` | alert | Waiting |
| `Stop` | celebrating, ~2.4s | Jumping |
| nothing recent | sitting → grooming → asleep, with the odd antic | Idle, Look around |

With antics on (the default) a bored pet occasionally strolls, waves or sulks
before sleep takes over; `pet antics off` restores the plain ladder.

An event older than 90 seconds is treated as stale, so a session that dies
without a `Stop` leaves the pet idling rather than typing forever.

## Registering hooks

`HookHost` describes an agent: the config files to edit, its event names, and
whether each takes a matcher. Three of the four use the same JSON shape — a
`hooks` object keyed by event name, each holding matcher groups — so one merge
implementation serves them. They differ in ways that matter:

| | Claude Code | Codex | Gemini CLI | opencode |
|---|---|---|---|---|
| config | `~/.claude/settings.json` | `~/.codex/hooks.json` | `~/.gemini/settings.json` | a JS plugin file |
| `timeout` unit | seconds | seconds | **milliseconds** | n/a |
| async | yes | yes | **no** | yes |
| "needs you" | `Notification` | `PermissionRequest` | `Notification` | `permission.asked` |

Each agent's vocabulary is translated at install time: the registered command
always passes the *pet's* event name, so the app never learns four dialects.

Two rules keep this safe to run against a file full of somebody else's hooks:

- **Ownership is matched strictly.** An entry is ours only if the command's
  executable is named `pet` and its first argument is `event`. Matching loosely
  once deleted a third-party hook whose program merely ended in "pet".
- **Reconcile, don't skip.** Installing removes our entries that point
  somewhere else — an older install, a moved binary — then adds the correct
  one. Skipping when any entry exists would strand people on a stale path.

Every config file is copied to `*.bak-pet` before editing, and one that cannot
be parsed is reported and left untouched.

Claude Code carries one exception. Hooks never receive Anthropic's own
rate-limit numbers — only the separate `statusLine` command does — so
installing the Claude plugin also claims that slot: `statusLine.command`
becomes `pet statusline --claude-dir <dir>`, which reads the JSON Claude Code
sends it, writes the two numbers to `<configDir>/usage/<account>` — one file
per Claude account, so several running at once (`~/.claude`,
`~/.claude-account1`, …) never clobber each other — for the app to poll, and
prints its own line. Unlike hooks, each config's `statusLine` holds exactly one
command, so a pre-existing one is saved next to `settings.json`
(`.pet-statusline-previous.json`) and `pet statusline` runs it first,
appending the usage line to whatever it printed; uninstalling reads the same
file to hand the slot back. The same ownership and reconcile rules apply —
a `statusLine` we do not recognise as ours is never touched, coming or going.

Codex has no equivalent slot to claim — its only external hook carries turn
metadata, never usage — so nothing is installed into its config at all.
Instead `CodexUsage.pollAll()` runs on a 30-second timer, reading the tail of
whichever rollout file under `~/.codex/sessions` (or a sibling `~/.codex-*`)
was modified most recently, and writes into the same `<configDir>/usage/`
store Claude's statusline feeds. The shape it looks for (`rate_limits`
holding `primary`/`secondary` windows with `used_percent`/`resets_at`) comes
from reading Codex's own source rather than a published contract — there
isn't one — so the search is bounded-depth rather than a fixed path, more
likely to survive a small wrapper change than an exact one would, but this
is unofficial and can break outright on a bigger one. Uninstalling a Codex
account still clears its recorded reading, the same as Claude's.

## Drawing

`PetView` draws in a fixed design space — 170×165 for the drawn art, 210×240
for a sprite — and the window is sized to that times the user's scale. The
view's *bounds* stay at the design size, so AppKit scales everything: art,
bubbles, hit testing. No drawing code knows the pet can be resized.

**Drawn skins** are vector paths built from a `Skin`: five colours plus
silhouette traits (`crest`, `stripes`, `whiskers`, `snout`, `eyePatches`,
`darkLimbs`). A new creature is a JSON file, not code.

**Sprite packs** are a codex-pets.net atlas: 8 columns of 192×208 cells, 9 rows
in v1 and 11 in v2. Frame counts per row are measured from the image rather
than assumed, because published packs do not always match the documented
counts. Packs draw no pill or bubbles — the atlas already animates the state.

## Keeping it cheap

An always-on desktop toy that burns a core is a bug. Three things keep it near
idle, each found by measuring rather than guessing:

1. **The loop rate follows the state** — 2fps hidden, 3 asleep, 6 idle, 20 while
   thinking or running a tool, 30 only for movement and dragging. Per-tick
   animation is scaled by the rate, so nothing looks slower.
2. **Sprite cells are baked into their own bitmaps.** A cropped `CGImage` is
   only a window onto its parent's data provider, so every draw re-locked the
   whole 1536×2288 sheet — `sample` put most of the frame in `CGSImageDataLock`.
3. **Nothing redundant reaches the window server.** A sprite redraws only when
   its frame changes, and the window is moved only when the pet has moved.

Measured: 1.4% of a core idle, 0.7% asleep, 0.1% hidden, 1.6–3.8% working.

> Measuring this needs care: running any shell command fires the hooks, so the
> pet is in its *working* state while you measure. Idle numbers need a stale
> event written to the state file first.

## Preferences and live changes

Both halves of the binary address one preference domain explicitly
(`UserDefaults(suiteName: "local.desktop.pet")`) rather than `.standard`,
because the CLI runs through a symlink and may not resolve to the app bundle.

When the CLI changes something it posts a distributed notification; the running
app re-reads and applies it without restarting. The app writes
`<configDir>/runtime` — pid, skin, hidden, chase, tray, cli, size — so
`pet status` reports what the live process is doing rather than what is merely
stored.

## Code layout

```
MacApp/
  Package.swift               so Xcode and `swift build` work
  Sources/Pet/
    main.swift                entry point: CLI, a render, or the app
    Pose, Preferences         small shared types
    Log                       <configDir>/logs/pet.log — launches, plugin and
                              config changes, update steps, errors; rotates
                              at 512 KB, never written from the loop
    Skin, SkinStore           drawn skins: the format, finding and seeding them
    SpritePet, SpriteStore, SpriteInstaller    codex-pets packs
    HookHost, HookPlugin, OpencodePlugin, AgentCommands   agent integration
    UsageStore, UsageBadge   Claude's and Codex's own rate-limit numbers
    CodexUsage               polls Codex's session files for its own usage
    ActivityBubbles          per-session cards above the pet
    PetView, PetView+Art      view state and dragging / how each pose is drawn
    Renderers                 icon, disk image background, contact sheets
    AppDelegate               lifecycle, window, shared state
      +Menu +Art +Plugins +Tools +Loop +Updates +About
    CLI +App +Skins +Plugin +Usage   the command line tool
  Skins/                      the four shipped skins, compiled in at build time
  build.sh                    compile, bundle, install locally
  dmg.sh                      build the disk image to share
```

`build.sh` compiles `Sources/Pet/*.swift`, so a new file needs no build change.
It also regenerates `Sources/Pet/DefaultSkins.swift` from `Skins/*.petskin` —
committed, so the Swift package builds without a code generation step, and why
an app with no skins folder still has its four.
