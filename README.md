# Pet Project

A desktop pet that reacts to what your coding agent is doing — it types at a
tiny laptop while a tool runs, thinks between steps, raises a `!` when the
agent needs you, and celebrates when a turn finishes. The rest of the time it
wanders, grooms itself and falls asleep.

| | |
|---|---|
| [**MacApp**](MacApp) | the macOS app and the `pet` command line |
| [**Plugins**](Plugins) | how Claude Code, Codex, Gemini CLI and opencode drive it |

A mobile version is planned; skin files are designed to be shared between
platforms.

## Quick start

    cd MacApp
    ./build.sh          # build, install to ~/Applications, run
    pet plugin install  # optional: react to your coding agent

All artwork is vector-drawn in code — there are no image assets. Skins are
plain JSON, so a new creature is a file, not a build.

Requires macOS 12 or later, Intel or Apple Silicon.
