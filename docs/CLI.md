# CLI reference

The `pet` command is the app binary, symlinked on first launch.

The app symlinks its own binary as `pet` on first launch — into
`/usr/local/bin` if that is writable, otherwise `~/.local/bin` — so the CLI and
the app are the same binary and never drift apart. `./build.sh` refreshes the
link too, pointing it at the copy in `~/Applications`.

    pet status              app state, config folder, skin, last activity
    pet start | stop | restart
    pet show | hide         the pet itself
    pet tray show | hide    the menu bar icon
    pet skins               list skins, current one marked
    pet skin <id>           switch skin
    pet skins dir           print the skins folder
    pet config              config folder and where the setting came from
    pet config set <path>   move it
    pet config reset        back to ~/.config/pet
    pet plugin install [agent]   claude | codex | gemini | opencode
    pet plugin uninstall [agent] | pet plugin status
    pet plugin install claude --path <dir>   a non-default config folder
    pet uninstall [--all]   remove app + CLI (--all also removes the config)
    pet render <file>       skin x pose sheet
    pet icon [size] <file>  the app icon

Hiding the menu bar icon leaves the pet running with no visible controls, so
`pet tray hide` prints how to undo it and the menu item shows an alert saying
the same — `pet tray show` is the way back. The setting persists across
restarts.

Changes apply to a running pet immediately: the CLI writes the preference and
posts a distributed notification, and the app re-reads and redraws — no
restart. The app also keeps `<configDir>/runtime` up to date so `pet status`
reports what the live process is doing rather than just what is stored.

`pet` with no arguments prints this help; `pet -h`, `--help` and `--version`
work as expected. The pet itself only starts when the bundle's own executable
is run — `Contents/MacOS/Pet`, which is how Finder, `open` and `pet start`
launch it — so the decision never depends on guessing at pipes or terminals.

`pet render`/`pet icon` and the older `--render`/`--icon` flags both work.

## Preview the artwork

    ./build/pet --render sheet.png

Renders every skin against every pose to one sheet — useful for checking
drawing changes without running the app.

## Reacting to activity

The pet polls a single file and maps what it finds to a pose:

    ~/.config/pet/state        (or $PET_CONFIG_DIR/state)

    EVENT|TOOL|EPOCH           e.g.  PreToolUse|Edit|1789137504

| Event | Pose |
|-------|------|
| `UserPromptSubmit`, `PostToolUse` | thinking, thought bubble |
| `PreToolUse` | typing at a laptop, `TOOL` in the pill |
| `Notification` | alert, `!` bubble, "needs you" |
| `Stop` | celebrating for ~2.4s, then idle |
| nothing recent | sitting → grooming → asleep |

`pet event <name>` is what writes that line: agent hooks call the CLI
directly, so there is no generated shell script anywhere. The app itself knows
nothing about any particular agent — anything that writes that line can drive
it. Claude Code, Codex, Gemini CLI and opencode are supported out of the box;
see [Agent plugins](PLUGINS.md). Without a plugin the pet simply idles, wanders and
sleeps.

## Interaction

- **Drag** the pet anywhere; the drop position is remembered.
- **Double-click** toggles chase mode (follow the cursor while Claude is idle).
- **Menu bar 🐈**: live status, skin picker, chase toggle, quit.
- Clicks only register on the creature itself; everywhere else in its window
  they pass through to the app underneath.
