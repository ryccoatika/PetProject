# Agent plugins

Teaches a coding agent to tell the [the pet](../MacApp) what it is doing,
so the pet types at its laptop while a tool runs, thinks between steps, raises
a `!` when it needs you, and celebrates when a turn ends.

Optional. Without it the pet still runs — it just idles, wanders and sleeps.

Supported agents: **Claude Code**, **Codex**, **Gemini CLI** and **opencode**.
Claude Code counts whether it runs in the terminal or inside the
[Claude Desktop app](#claude-desktop).

## Install

From the menu bar: 🐈 → **Agent Plugin**, which lists every supported agent
with a tick beside the ones the pet is wired into. Clicking a row installs or
removes that agent's hooks. Agents that are not installed on the machine are
shown greyed out, and a Claude folder outside the managed one that still holds
pet hooks gets its own row offering to clean it.

Or from the terminal:

    pet plugin install            every agent found on this machine
    pet plugin install claude     claude | codex | gemini | opencode
    pet plugin status
    pet plugin uninstall [agent]  with no agent: every one of them

Then start a new session in that agent so the hooks load. The `pet` command
comes with the app, so there is nothing else to copy and no separate installer
to keep in step.

## What it registers

Three of the four take JSON config listing commands to run, with the same
shape — a `hooks` object keyed by event name, each holding matcher groups — so
one implementation serves them. The command registered is the CLI itself:

    /path/to/pet event <PetEventName>

The argument is always the pet's own event name, so each agent's vocabulary is
translated at install time and the app never has to learn four of them.

| | Claude Code | Codex | Gemini CLI | opencode |
|---|---|---|---|---|
| config | `~/.claude/settings.json` | `~/.codex/hooks.json` | `~/.gemini/settings.json` | `~/.config/opencode/plugin/pet.js` |
| mechanism | command hooks | command hooks | command hooks | JavaScript plugin |
| payload | JSON on stdin | JSON on stdin | JSON on stdin | handler arguments |
| `timeout` unit | seconds | seconds | **milliseconds** | n/a |
| async | yes | yes | **no — hooks block** | yes (handlers are async) |
| matcher | `"*"` on tool events | omitted | omitted | n/a |

Event name mapping:

| Pet | Claude Code | Codex | Gemini CLI | opencode |
|---|---|---|---|---|
| `SessionStart` | `SessionStart` | `SessionStart` | `SessionStart` | `session.created` |
| `UserPromptSubmit` | `UserPromptSubmit` | `UserPromptSubmit` | `BeforeAgent` | — |
| `PreToolUse` | `PreToolUse` | `PreToolUse` | `BeforeTool` | `tool.execute.before` |
| `PostToolUse` | `PostToolUse` | `PostToolUse` | `AfterTool` | `tool.execute.after` |
| `Notification` | `Notification` | `PermissionRequest` | `Notification` | `permission.asked` |
| `Stop` | `Stop` | `Stop` | `AfterAgent` | `session.idle` |
| `SessionEnd` | `SessionEnd` | `SessionEnd` | `SessionEnd` | — |

### opencode

opencode has no command-hook config — [native hooks are still a feature
request](https://github.com/anomalyco/opencode/issues/14863) — so the plugin is
a small JavaScript file written to `~/.config/opencode/plugin/pet.js`. It
writes the state file directly rather than spawning the CLI, so it costs
nothing per event. opencode 1.18 loads both `plugin/` and `plugins/`; the
installer writes one and removes a copy from the other so events cannot fire
twice.

| Event | What the pet does | Sprite track |
|-------|-------------------|--------------|
| `SessionStart` | wakes up | Idle |
| `UserPromptSubmit` | thinks — thought bubble | Review |
| `PreToolUse` | types at a laptop, tool name in the pill | Running |
| `PostToolUse` | back to thinking | Review |
| a tool failed | stands up, `!` bubble, "failed" | Failed |
| `Notification` / `PermissionRequest` | stands up, `!` bubble, "needs you" | Waiting |
| `Stop` | celebrates for a moment, then settles | Jumping |
| `SessionEnd` | back to idle | Idle |

### Claude Desktop

The Claude Desktop app's agent mode runs a bundled Claude Code pointed at
`~/.claude`, so the ordinary `claude` plugin covers it: install once and the
pet reacts to Desktop agent sessions too, with nothing extra to set up.

Plain chat conversations are different. They run remotely, and the app exposes
no hooks, no per-message logs and no event API a local process could subscribe
to, so the pet cannot react to them. If that ever changes, support would land
as a new `HookHost` like any other agent.

### Failures

Only Claude Code has dedicated failure events (`PostToolUseFailure` and
`StopFailure`), and both are registered. Everywhere else the failure is in the
result payload, so `pet event` reads it: a `tool_response` carrying an `error`
or `success: false`, or a top-level `error`, is recorded as a failure whatever
the agent called the event. A null `error` does not count. opencode reports
turn failures through its own `session.error`.

## Other config folders

Each agent has one default folder — `~/.claude` and `~/.codex`. To use a
different one, pass `--path`:

    pet plugin install claude --path ~/.claude-account1
    pet plugin uninstall claude --path ~/.claude-account1

`--path` is repeatable, takes either a folder or a config file directly, and
applies only to that command — nothing is remembered, so every run says exactly
where it is writing. No other folder is ever touched implicitly.

`pet plugin status` still looks around for `~/.claude-*` folders that carry pet
hooks and names them, with the command to clean each one, so an old install
cannot be silently forgotten.

## The contract

The hook writes one line to the pet's state file:

    ~/.config/pet/state        (or $PET_CONFIG_DIR/state)

    EVENT|TOOL|EPOCH           e.g.  PreToolUse|Edit|1789137504

That is the whole interface. `pet event <name>` reads the hook payload on
stdin, pulls out `tool_name`, and writes that line. Anything that can write a
line of text can drive the pet, so these two agents are simply the first
producers — a mobile pet would define its own.

## Notes

- Hooks are registered `async`, so they never add latency to a turn, and
  `pet event` always exits 0 — it cannot fail a turn.
- One process per event, versus a shell script's four (`sh`, `sed`, `date`,
  `mv`): about 29 ms instead of 107 ms per invocation on an M-series Mac.
- Each config file is backed up next to itself as `*.bak-pet` before editing;
  one that cannot be parsed is reported and left untouched.
- Re-running the install is safe: it reconciles its own entries — including
  upgrading ones from an older install that pointed elsewhere — and leaves
  every other hook alone.
- Ownership is matched strictly: the command's executable must be named `pet`
  (or the bundle's `Pet`) *and* its first argument must be `event`. A hook like
  `/opt/tools/snippet event PreToolUse` belongs to somebody else and is never
  touched, and neither install nor uninstall removes a hook it does not own.
- Codex also accepts hooks as a `[hooks]` table in `~/.codex/config.toml`.
  The plugin writes `hooks.json` instead, so your TOML is never rewritten.

## Adding another agent

`HookHost` in `../MacApp/Sources/HookHost.swift` describes an agent: its config files, its
event names and whether each takes a matcher. Adding one is a new static
property plus an entry in `HookHost.all`.
