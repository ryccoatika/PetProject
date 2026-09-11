# Using the pet

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

## Size

The pet can be drawn anywhere from half to double size: 🐈 → **Size** holds a
slider with a live readout and a **Reset to 100%**, and the CLI has the same:

    pet size            print the current size
    pet size 150        set it (a percentage, or a multiplier like 1.5)
    pet size reset

Nothing in the drawing code knows about this. The window is resized to the
design size times the scale, and the view's *bounds* are left at the design
size — AppKit scales a view whose bounds are smaller than its frame, so the
art, the bubbles and the grab area all follow without a single coordinate
being touched. It costs nothing measurable: an idle sprite is about 0.7% CPU
at 200%, the same as at 100%, because it still only redraws when its frame
changes.

