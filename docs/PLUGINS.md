# Agent plugins

Teaches a coding agent to tell the [the pet](../MacApp) what it is doing,
so the pet types at its laptop while a tool runs, thinks between steps, raises
a `!` when it needs you, and celebrates when a turn ends.

Optional. Without it the pet still runs — it just idles, wanders and sleeps.

Supported agents: **Claude Code**, **Codex**, **Gemini CLI**, **opencode**,
**Antigravity**, **Cursor** and **pi**. Claude Code counts whether it runs in
the terminal or inside the [Claude Desktop app](#claude-desktop).

## Install

From the menu bar: 🐈 → **Agent Plugin**, which lists every supported agent
with a tick beside the ones the pet is wired into. Clicking a row installs or
removes that agent's hooks. Agents that are not installed on the machine are
shown greyed out, and a Claude folder outside the managed one that still holds
pet hooks gets its own row offering to clean it.

Or from the terminal:

    pet plugin install            every agent found on this machine
    pet plugin install claude     claude | codex | gemini | opencode
                                  | antigravity | cursor | pi
    pet plugin status
    pet plugin uninstall [agent]  with no agent: every one of them

Then start a new session in that agent so the hooks load. The `pet` command
comes with the app, so there is nothing else to copy and no separate installer
to keep in step.

## Skin skills and commands

Installing a plugin also teaches the agent to make skins: **create-pet** and
**create-sprite** land next to the hooks and leave with
`pet plugin uninstall`. On Claude Code and Codex they are SKILL.md skills —
modelled on Codex's own curated hatch-pet skill — so the agent can also
reach for them from a plain request; elsewhere they are command files.

- **create-pet** — designs a drawn `.petskin` (the small JSON format), writes
  it into the skins folder and switches to it.
- **create-sprite** — creates a spritesheet pet. On Codex it rides the
  built-in **hatch-pet** skill (which composes the `$imagegen` system skill
  to draw the character), then installs the hatched pet from
  `~/.codex/pets/<id>` with `pet pets install` — the atlas is the same. On
  every other agent — none has built-in image generation — the atlas layout
  and track table are in the command and the agent generates the sheet with
  a script, then installs it the same way.

| Agent | Files |
|---|---|
| Claude Code | `~/.claude/skills/create-{pet,sprite}/SKILL.md` |
| Codex | `~/.codex/skills/create-{pet,sprite}/SKILL.md` |
| Gemini CLI | `~/.gemini/commands/create-{pet,sprite}.toml` |
| opencode | `~/.config/opencode/command/create-{pet,sprite}.md` |
| Cursor | `~/.cursor/commands/create-{pet,sprite}.md` |

Antigravity and pi have no equivalent, so they get hooks only. Only files at
exactly these paths are ever written or removed.

## Usage badge

A small badge below the pet shows Claude's and Codex's own rate-limit
numbers — a ring pair per account, outer ring the longer window, inner ring
the shorter one, the more urgent of the two as the number in the centre. No
caption is drawn under a ring; hovering it shows that account's name (its
config folder, with the agent's name — `~/.claude` → **Claude**,
`~/.claude-account1` → **Claude · account1**, `~/.codex` → **Codex**) in a
small pill above the card instead, so the badge stays as small as the rings
alone need — this is why the agent name always stays in the caption rather
than collapsing to a bare "default": a plain Claude and a plain Codex
account both being installed at once is the *common* case, not an edge
case, and both collapsing to the same word left no way to tell them apart.
The label is self-drawn rather than a native tooltip — this window is a
borderless overlay owned by an accessory app, where AppKit's own tooltip
tracking proved unreliable — so hover rides the same `NSEvent.mouseLocation`
poll the main loop already runs every tick for the pet's own hover and drag
handling; the window stays fully click-through throughout. Ring pairs sit
side by side, one per account, capped at 6 so the badge cannot grow
absurdly wide; `pet usage` has no such cap and prints every account.
**Show Usage Below Pet** (menu, or the pet's right-click menu) toggles it.

The two agents get the data in entirely different ways:

**Claude Code** installs one more thing beyond hooks: its own `statusLine`
entry. That is the only place Anthropic exposes rate-limit numbers — hooks
never receive them — so `pet plugin install claude --path <dir>` also
points that config's `statusLine.command` at
`pet statusline --claude-dir <dir>`, which reads the JSON Claude Code sends
it and writes the rolling 5-hour "session" window and the 7-day "week, all
models" window (the same two `/usage` shows) into
`<configDir>/usage/<account>`. `statusLine` holds exactly one command,
unlike hooks, so a pre-existing custom one is saved beside `settings.json`
and chained to rather than replaced; uninstalling restores it, and clears
that account's recorded reading so its ring does not linger.

Running Claude Code under several accounts — `~/.claude`,
`~/.claude-account1`, `~/.claude-account2`, … via `$CLAUDE_CONFIG_DIR` or a
shell alias — install the plugin once per account with `--path`:

```sh
pet plugin install claude --path ~/.claude
pet plugin install claude --path ~/.claude-account1
pet plugin install claude --path ~/.claude-account2
```

Each gets its own hooks, skills and `statusLine` entry, and each shows up as
its own ring the moment that account's Claude Code reports rate limits.

**Codex** has no equivalent to `statusLine` — its only external hook
(`notify`) carries turn metadata, never usage, and the 5-hour/weekly
percentages its own `/statusline` shows exist only inside its interactive
TUI. There is nothing for it to push to `pet`, so nothing is installed into
Codex's config for this at all: `pet` instead polls Codex's own session
files every 30 seconds — `~/.codex/sessions/**/rollout-*.jsonl` and any
sibling `~/.codex-*` folder, mirroring how multiple Claude accounts are
named — reading only the tail of the most recently modified file for the
latest `rate_limits` reading Codex already records for itself. This is
read-only and unofficial: Codex ships no documented format for its rollout
files, so a future Codex release changing that internal shape can silently
stop this working, unlike Claude's supported `statusLine` contract.
Uninstalling a Codex account (`pet plugin uninstall codex --path <dir>`)
still clears its recorded reading, the same as Claude's.

A per-model weekly figure (Fable's own week, say) is not included: Anthropic
does not expose it anywhere outside `/usage`'s own interactive display, so
there is nothing to read.

`statusLine` holds exactly one command, unlike hooks. If a custom statusline
was already configured, install saves it (next to that `settings.json`, as
`.pet-statusline-previous.json`) and `pet statusline` runs it first, appending
the usage line to its output; uninstall reads the same file to put the
original command back — untouched if it is not recognisable as ours to begin
with. Badge and usage data only appear for Pro and Max plans, and only after
a session's first response.

## What it registers

Five of the seven take JSON config listing commands to run. Claude Code,
Codex and Gemini CLI share one shape — a `hooks` object keyed by event name,
each holding matcher groups — Cursor puts commands directly in each event's
list, and Antigravity keys the top level by hook name, so the pet owns exactly
one entry there. The command registered is always the CLI itself:

    /path/to/pet event <PetEventName>

The argument is always the pet's own event name, so each agent's vocabulary is
translated at install time and the app never has to learn seven of them.

| | Claude Code | Codex | Gemini CLI | Antigravity | Cursor |
|---|---|---|---|---|---|
| config | `~/.claude/settings.json` | `~/.codex/hooks.json` | `~/.gemini/settings.json` | `~/.gemini/config/hooks.json` | `~/.cursor/hooks.json` |
| payload | JSON on stdin | JSON on stdin | JSON on stdin | JSON on stdin, camelCase | JSON on stdin |
| `timeout` unit | seconds | seconds | **milliseconds** | seconds | seconds |
| async | yes | yes | **no — hooks block** | **no — see below** | after-events never block |
| matcher | `"*"` on tool events | omitted | omitted | omitted | omitted |

opencode and pi have no command hooks; they load script plugins instead, so
the installer writes one — `~/.config/opencode/plugin/pet.js` (JavaScript) and
`~/.pi/agent/extensions/pet.ts` (TypeScript, needs pi 0.83+). Both write the
state file directly from their handlers, so they cost nothing per event.

Event name mapping:

| Pet | Claude Code | Codex | Gemini CLI | Antigravity | Cursor | opencode | pi |
|---|---|---|---|---|---|---|---|
| `SessionStart` | `SessionStart` | `SessionStart` | `SessionStart` | — | `sessionStart` | `session.created` | `session_start` |
| `UserPromptSubmit` | `UserPromptSubmit` | `UserPromptSubmit` | `BeforeAgent` | `PreInvocation` | `beforeSubmitPrompt` | — | `input` |
| `PreToolUse` | `PreToolUse` | `PreToolUse` | `BeforeTool` | `PreToolUse` | `preToolUse` | `tool.execute.before` | `tool_execution_start` |
| `PostToolUse` | `PostToolUse` | `PostToolUse` | `AfterTool` | `PostToolUse` | `postToolUse` | `tool.execute.after` | `tool_execution_end` |
| `Notification` | `Notification` | `PermissionRequest` | `Notification` | — | — | `permission.asked` | `ui_prompt_start` |
| `Stop` | `Stop` | `Stop` | `AfterAgent` | `PostInvocation` | `stop` | `session.idle` | `agent_end` |
| `SessionEnd` | `SessionEnd` | `SessionEnd` | `SessionEnd` | `Stop` | `sessionEnd` | — | `session_shutdown` |

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

### Antigravity

Antigravity's hooks file lives under `~/.gemini`, but it is not Gemini CLI's:
since 1.1 Antigravity reads only `~/.gemini/config/hooks.json`, in its own
format, and silently ignores `settings.json`. Its hooks are synchronous, and
`PreToolUse` waits for a verdict on stdout — so that one event is registered
as `pet event PreToolUse --allow`, which records the activity and prints
`{"decision":"allow"}`. At ~29 ms per event the wait is invisible. There is no
SessionStart or Notification equivalent, so the pet wakes on the first prompt
and never raises the `!` bubble for Antigravity.

Because `~/.gemini` also belongs to Gemini CLI, the installer decides whether
Antigravity is present by looking for the app itself (`Antigravity.app` or
`~/.antigravity`), not for the config folder.

### Cursor

One file drives both the IDE's agent and the `agent` CLI:
`~/.cursor/hooks.json`, with `version: 1` and commands sitting directly in
each event's list. Cursor hooks fail open — a hook that prints nothing never
blocks anything — and the file is watched, so changes apply without a restart.
There is no Notification equivalent. The CLI also merges hooks from Claude
Code's settings.json, so a tool event there can fire the pet twice — harmless,
as both write the same state line.

### pi

pi has no command hooks — like opencode it loads script plugins, so the
installer writes a TypeScript extension to `~/.pi/agent/extensions/pet.ts`
that writes the state file directly. It needs pi 0.83 or later, where the
extension event bus became public. pi picks the file up on the next session or
`/reload`. A failed tool arrives as `isError` on `tool_execution_end` and is
recorded as a failure, and `ui_prompt_start` — pi asking the user something —
raises the `!` bubble.

### Claude Desktop

The Claude Desktop app's agent mode runs a bundled Claude Code pointed at
`~/.claude`, so the ordinary `claude` plugin covers it: install once and the
pet reacts to Desktop agent sessions too, with nothing extra to set up.

Plain chat conversations are different. They run remotely, and the app exposes
no hooks, no per-message logs and no event API a local process could subscribe
to, so the pet cannot react to them. If that ever changes, support would land
as a new `HookHost` like any other agent.

### Failures

Claude Code and Cursor have dedicated failure events (`PostToolUseFailure`,
and `StopFailure` on Claude Code), and they are registered. Everywhere else
the failure is in the result payload, so it is read where the payload is read:
`pet event` treats a `tool_response` carrying an `error` or `success: false`,
or a top-level `error` (Antigravity's shape), as a failure whatever the agent
called the event, and the pi extension does the same with `isError`. A null
`error` does not count. opencode reports turn failures through its own
`session.error`.

Claude Code fires a `Notification` both for a real permission ask and for its
idle "waiting for your input" nudge after a turn ends. The bubble tells them
apart by the notification's `message`: a permission ask reads "Waiting for
you" (and shows the message) and stands the pet up, while the idle nudge reads
a calmer "Waiting for your reply" and fades after a minute without raising the
pet. So a finished, idle turn no longer looks like it needs you.

## Other config folders

Each agent has one default config location — `~/.claude`, `~/.codex`,
`~/.gemini`, `~/.cursor`, `~/.pi/agent` and so on. To use a different one,
pass `--path`:

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

That is the whole interface for the pet's pose. `pet event <name>` reads the
hook payload on stdin, pulls out `tool_name`, and writes that line. Anything
that can write a line of text can drive the pet, so these agents are simply
the first producers — a mobile pet would define its own.

For the activity bubbles there is a second, optional layer: when the payload
carries a session id (`session_id`, `conversation_id` or `conversationId`)
the same event is also written to

    ~/.config/pet/sessions/<session-id>

    EVENT|TOOL|EPOCH|PROJECT|DETAIL|CWD|APP

where PROJECT is the last component of the payload's working directory
(`cwd`, `workspace_roots` or `workspacePaths`), DETAIL is one short human
line from the payload — the prompt, a tool call's `description`, the file or
the command — CWD is that working directory, and APP is the bundle id and pid
of the terminal or IDE running the agent (found by walking `pet event`'s
parent-process chain), so clicking a bubble can raise it. CWD and APP are
base64-encoded; newlines and `|` are cleaned out of the plain fields. One
file per session means concurrent agents never fight over a file. `SessionEnd`
deletes the file, and anything a day old is cleaned up on read.

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

`HookHost` in `../MacApp/Sources/Pet/HookHost.swift` describes an agent: its
config files, its event names, whether each takes a matcher, and which of the
three JSON dialects its config uses (nested matcher groups, flat command
lists, or a top level keyed by hook name). An agent with no command hooks gets
a generated script instead, like opencode and pi. Adding one is a new static
property plus an entry in `HookHost.all`.
