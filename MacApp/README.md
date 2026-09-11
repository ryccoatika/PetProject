# Desktop Pet — macOS app

The macOS app of the Desktop Pet project (`~/Developments/PetProjects`);
a mobile version is planned alongside it. Skin files are intended to be
shared between platforms.

A macOS desktop pet that reacts to Claude Code. A transparent, always-on-top
window draws an animated creature that changes pose based on what Claude is
doing. All artwork is vector-drawn in code — no image assets.

## Build

    ./build.sh

Compiles `main.swift` and bundles `Pet.app` (menu-bar only, `LSUIElement`),
both into `build/`, then installs the app to `~/Applications` and restarts
the running pet.

    build/
    ├── pet           compiled binary
    ├── icon.png      1024px app icon, rendered by the app itself
    ├── Pet.iconset/  the sizes iconutil needs
    └── Pet.app       app bundle: Skins/ and Pet.icns in Contents/Resources

## Sharing it

    ./dmg.sh

Produces `build/DesktopPet-1.0.dmg`: the usual Mac installer window with
`Pet.app` beside an `Applications` shortcut, a background telling you to drag
one onto the other, and a custom volume icon. The background is rendered by
the app itself (`pet dmgbg`), and the window layout is set through Finder, so
positions and background survive in the image's `.DS_Store`.

Dragging the app in is all that is needed: on first launch it symlinks itself
as `pet` into `/usr/local/bin` if that is writable, otherwise `~/.local/bin`.
It only ever creates or repoints a link to a `Pet.app` — another program named
`pet` is left alone.

On a stock Mac `/usr/local/bin` is owned by root, so the link usually lands in
`~/.local/bin`, which is **not** on the default PATH — the command exists but
the shell will not find it. The app cannot detect this itself (a Finder-
launched app does not get the user's shell environment), so instead the menu
says **Command Line Tool — needs PATH setup…**, and opening it shows where the
command is and offers to copy the one line to add to `~/.zshrc`. Until then the
full path works.

The one rough edge is Gatekeeper. The app is ad-hoc signed, not notarised, and
a disk image cannot clear its own quarantine, so the first launch needs
right-click → Open (or Open Anyway in System Settings → Privacy & Security).
Notarising with a paid Apple Developer ID is the only way to remove that step.

`install.sh` is still here for installing from a checkout or a copied folder
without the disk image — it copies the app, clears the quarantine attribute and
symlinks the CLI — but nothing packages it any more.

## App icon

The icon is drawn by the app from the same vector art as the pet — there is
no image file to maintain:

    ./build/pet --icon 1024 icon.png

`build.sh` renders it, resizes it into `Pet.iconset`, runs `iconutil` to make
`Pet.icns`, and `Info.plist` points at it with `CFBundleIconFile`. To restyle
the icon, edit the `--icon` block in `main.swift`.

Note: on macOS 26 the systemwide *icon style* (System Settings → Appearance)
can render every app icon monochrome — `ClearDark` and `Tinted` both do. The
icon is full colour; set the style to Default to see it that way.

`build/` is generated and git-ignored.

## The `pet` command

`install.sh` symlinks the app binary as `pet` (into `/usr/local/bin` if it is
writable, otherwise `~/.local/bin`), so the CLI and the app are the same
binary and never drift apart.

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
    pet plugin install [agent]   claude | codex | gemini | opencode (see ../Plugins)
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
see [`../Plugins`](../Plugins). Without a plugin the pet simply idles, wanders and
sleeps.

## Interaction

- **Drag** the pet anywhere; the drop position is remembered.
- **Double-click** toggles chase mode (follow the cursor while Claude is idle).
- **Menu bar 🐈**: live status, skin picker, chase toggle, quit.
- Clicks only register on the creature itself; everywhere else in its window
  they pass through to the app underneath.

## Sprite pets

Besides the drawn skins, the pet can be a spritesheet character from
[codex-pets.net](https://codex-pets.net):

    pet pets install perlica-endfield     download from the marketplace
    pet pets install ~/Downloads/foo.codex-pet   a local folder or .zip
    pet pets                              list what is installed
    pet pets remove <id>
    pet skin <id>                         switch to it (same command as skins)

Packs land in `~/.config/pet/pets/<id>/` and appear in the menu and in
`pet skins` alongside the drawn skins.

### The atlas

A pack is a `pet.json` plus a spritesheet. The atlas is 8 columns of 192x208
cells; v1 sheets have 9 rows and v2 sheets 11. Frame counts per row are
*measured* from the image rather than assumed — published packs do not always
match the documented counts (the sample pack's idle row has 7 frames, not the
documented 6).

| Row | Track | Used for |
|-----|-------|----------|
| 0 | Idle | sitting, and sleeping (slowed down) |
| 1 | Run right | walking right |
| 2 | Run left | walking left |
| 3 | Waving | being picked up and dragged |
| 4 | Jumping | a turn just finished |
| 5 | Failed | a tool reported a failure |
| 6 | Waiting | waiting for you (permission / notification) |
| 7 | Running | a tool is running |
| 8 | Review | thinking between steps |
| 9 | Look around - right side | idle glancing, facing right |
| 10 | Look around - left side | idle glancing, facing left |

Rows 9 and 10 are v2 only; on a v1 sheet they fall back to Idle.

    ./build/pet render --tracks tracks.png

renders every track of every installed pack for checking.

### Cost

Three things keep a spritesheet affordable at 30fps: each cell is cropped from
the sheet once and cached, a sprite is redrawn only when its frame actually
changes, and the window is only moved when the pet has moved.

| | CPU |
|---|---|
| drawing the whole sheet every frame (first attempt) | 28% |
| cell caching only | 16% |
| plus redraw-on-change and skipping idle window moves | **6.5%** |

For comparison the drawn art sits at about 8.6%: it animates continuously, so
it genuinely redraws every frame, while an idle sprite advances a frame only a
few times a second.

## Skins

Skins are data, not code. Each one is a `.petskin` file (JSON):

```json
{
  "id": "fox",
  "name": "Fox",
  "colors": {
    "body":     "#E4703A",
    "bodyDark": "#B04A22",
    "belly":    "#FFF5EC",
    "ink":      "#2E1A12",
    "accent":   "#2E1A12"
  },
  "traits": {
    "crest": "ears",
    "whiskers": true,
    "darkLimbs": true
  }
}
```

| Field | Meaning |
|-------|---------|
| `id` | unique key, also the saved preference value |
| `name` | label in the menu |
| `colors.body` / `bodyDark` | main coat and its shadow tone (ears, stripes, plates) |
| `colors.belly` | belly patch, muzzle patch and paws |
| `colors.ink` | outlines |
| `colors.accent` | nose and inner ear |
| `traits.crest` | `ears`, `floppy`, `round` or `spikes` |
| `traits.stripes` | dark bars along the back |
| `traits.whiskers` | whiskers on the muzzle |
| `traits.snout` | broad muzzle patch with a rounded nose |
| `traits.eyePatches` | dark markings around the eyes |
| `traits.darkLimbs` | legs, tail and paws use `bodyDark` |

Colours are `#RRGGBB` (or `#RRGGBBAA`). Every trait is optional and
defaults to `false`.

### Where they live

    ~/.config/pet/skins/

The skins folder is `skins/` inside the config folder, which is resolved in
this order:

1. `$PET_CONFIG_DIR` — wins over everything, expands `~`
2. the folder chosen with **Change Config Folder…** in the menu
3. `~/.config/pet` (default)

An empty skins folder is filled automatically: first from an older install's
folder (`~/Library/Application Support/DesktopPet/Skins`, so a custom skin
survives the move), otherwise from the copies shipped inside the app bundle.
Deleting the folder therefore restores the shipped set. `Skins/` in this repo
is the source for those copies.

    PET_CONFIG_DIR=~/dotfiles/pet ./build/pet --render sheet.png

### Managing them

Menu bar 🐈 → **Skin**:

- **Import Skin…** — validates the file, then copies it into the folder
- **Export Current Skin…** — writes the active skin out as `<id>.petskin`
- **Open Skins Folder** — reveals the folder in Finder
- **Change Config Folder…** — pick a different config folder; skins are read
  from `skins/` inside it. Disabled when `$PET_CONFIG_DIR` is set.
- **Use Default Location** — shown only while a custom folder is in use
- **Reload Skins** — re-reads from disk

The submenu also shows the current skins path, so it is always clear which
folder is in effect.

The submenu re-reads the folder every time it opens, so a file dropped in
shows up without restarting. A skin file that fails to parse is skipped and
listed in the submenu with the reason; the rest still load.

Shipped: Tabby cat, Dog, Panda, Dino.
