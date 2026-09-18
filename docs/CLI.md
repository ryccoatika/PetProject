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
    pet bubbles show | hide the activity bubbles above the pet
    pet antics on | off     wander, wave or sulk when bored (on by default)
    pet usage [show | hide] Claude's session/week rate-limit badge, or its numbers
    pet stats               today's sessions, tools and active time
    pet skins               list skins, current one marked
    pet skin <id>           switch skin
    pet skins dir           print the skins folder
    pet config              config folder and where the setting came from
    pet config set <path>   move it
    pet config reset        back to ~/.config/pet
    pet plugin install [agent]   claude | codex | gemini | opencode
                                 | antigravity | cursor | pi
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
| nothing recent | sitting → grooming → asleep, with the odd antic |

With **antics** on (the default), a pet left alone for a while acts on its
own now and then: it strolls anywhere across the screen, waves at you, or —
after being ignored long enough — sits and sulks. Sleep still wins in the end, so the
overnight cost stays at the sleeping rate. `pet antics off` (or the menu's
**Antics When Bored**) turns it off, restoring the plain sit → groom → sleep
ladder.

Alongside the single state line, `pet event` keeps one small file per agent
session in `<configDir>/sessions/<session-id>`, holding
`EVENT|TOOL|EPOCH|PROJECT|DETAIL|CWD` (the last base64-encoded). Those drive
the activity bubbles above the pet's head — one card per session naming the
project and what is actually happening (the prompt, the command, the file),
so two projects running at once stack two bubbles. **Click a card** to raise
the terminal or IDE running that session — bringing its window, and its
Space, to the front (it falls back to opening the folder in Finder when the
app cannot be found). `SessionEnd` retires a session's file; stale ones age
out. The menu has **Show Activity Bubbles**, and `pet bubbles
show | hide` is the same switch.

A few things follow from having every session in view:

- **Chime When an Agent Needs You** (menu, off by default) plays a sound the
  moment any session starts waiting on a permission — the one time you have
  to look.
- The **menu bar icon** shows a live session count, turning red with a `!`
  when one needs you, so a glance works even with the pet on another Space.
- **Follow Session** (menu) pins the pose to one session; left on *Most
  urgent* the pet shows whichever session most wants attention rather than
  whichever agent wrote last.
- `pet stats` (and a line in About) tallies today's sessions, tools run and
  active time.

## Claude usage badge

With the Claude Code plugin installed, a small badge below the pet shows the
two numbers `/usage` does — the rolling 5-hour session limit and the 7-day
week limit across every Claude model — as a pair of concentric rings: outer
for the week, inner for the session, the more urgent of the two as the
number in the middle. Running several Claude accounts at once
(`~/.claude`, `~/.claude-account1`, …) shows one ring pair per account,
side by side, up to 6; `pet usage` prints every account with no cap.
`pet usage show | hide` (or **Show Claude Usage Below Pet** in the menu or
the pet's right-click menu) toggles the badge. Needs a Pro or Max plan, and
only appears after a session's first response — see [Agent
plugins](PLUGINS.md#claude-usage-badge) for how it gets the data and how to
wire up more than one account.

`pet event <name>` is what writes that line: agent hooks call the CLI
directly, so there is no generated shell script anywhere. With `--allow` it
also prints `{"decision":"allow"}` — for agents whose tool hooks are
synchronous and wait for a verdict, like Antigravity. The app itself knows
nothing about any particular agent — anything that writes that line can drive
it. Claude Code, Codex, Gemini CLI, opencode, Antigravity, Cursor and pi are
supported out of the box; see [Agent plugins](PLUGINS.md). Without a plugin
the pet simply idles, wanders and sleeps.

## Interaction

- **Drag** the pet anywhere; the drop position is remembered.
- **Double-click** toggles chase mode (follow the cursor while Claude is idle).
- **Right-click** pops a small Behaviour menu on the pet itself: chase cursor,
  antics when bored, and the activity bubbles.
- **Flick** the pet to throw it — it tumbles through the air, squashes against
  the screen edges as it bounces, and flashes how fast you flung it. With
  chase mode on it still throws, then heads back to the cursor.
- **Menu bar icon**: live status and an update row up top; then **Appearance**
  (skin, size, menu bar icon), **Behaviour** (chase, antics, activity bubbles,
  chime, follow session) and **Agent Plugin**; About and Quit at the foot.
- Clicks only register on the creature itself; everywhere else in its window
  they pass through to the app underneath.
