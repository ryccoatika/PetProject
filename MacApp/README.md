# Desktop Pet — macOS app

The macOS app of the Desktop Pet project (`~/Developments/PetProjects`);
a mobile version is planned alongside it. Skin files are intended to be
shared between platforms.

A macOS desktop pet that reacts to Claude Code. A transparent, always-on-top
window draws an animated creature that changes pose based on what Claude is
doing. All artwork is vector-drawn in code — no image assets.

## Code layout

One Swift module, no dependencies. `main.swift` only decides what to run;
everything else lives in `Sources/`, one concern per file.

    Package.swift               open this in Xcode
    main.swift → Sources/Pet/main.swift

    Sources/Pet/
      Pose.swift                what the pet is doing
      Preferences.swift         the preference domain shared with the CLI
      Skin.swift                a drawn skin: palette and traits
      SkinStore.swift           finding, seeding and validating skins
      SpritePet.swift           a codex-pets.net pack: atlas slicing, drawing
      SpriteStore.swift         where packs live
      SpriteInstaller.swift     installing packs from id, URL, folder or zip
      HookHost.swift            the agents, their events and config files
      HookPlugin.swift          registering and removing hooks
      OpencodePlugin.swift      the JavaScript plugin opencode loads
      PetView.swift             view state, dragging, draw entry points
      PetView+Art.swift         how each pose is drawn
      Renderers.swift           icon, disk image background, contact sheets
      AppDelegate.swift         lifecycle, window, shared state
      AppDelegate+Menu.swift    building the menu bar
      AppDelegate+Art.swift     choosing, importing, exporting skins
      AppDelegate+Plugins.swift agent plugins from the menu
      AppDelegate+Tools.swift   the `pet` command, menu bar icon, visibility
      AppDelegate+Loop.swift    loop rate, placement, activity, each step
      CLI.swift                 dispatch, help, the hook event entry point
      CLI+App.swift             status, start/stop, show/hide, tray
      CLI+Skins.swift           skins, packs, config folder
      CLI+Plugin.swift          agent plugins, uninstall

`build.sh` compiles `Sources/Pet/*.swift`, so a new file needs no build change.
It regenerates `Sources/Pet/DefaultSkins.swift` from `Skins/`, which is
committed so `swift build` needs no code generation step.

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
`~/.local/bin`, which is not on the default PATH — the command exists but the
shell cannot find it.

To know whether that is actually a problem the app asks the user's own login
shell (`$SHELL -ilc 'command -v pet'`) in the background at launch. Its own
environment cannot answer: launched from Finder it never sees the shell
profile, and a folder missing from `/etc/paths` may well be added by the
user's `.zshrc` — checking that file alone reports a problem that is not
there.

When the shell does find it, nothing is shown. When it does not, the menu
grows a **⚠ Command Line Tool — needs PATH setup** entry that says where the
command is and offers to copy the line for `~/.zshrc`. `pet status` and the
runtime file report the same thing as `cli=ok` or `cli=needs-path`.

The one rough edge is Gatekeeper. The app is ad-hoc signed, not notarised, and
a disk image cannot clear its own quarantine, so macOS refuses the first launch
of a downloaded build. Since macOS 15 the right-click → Open bypass is gone —
the warning offers only Move to Trash and Done — and the way through is System
Settings → Privacy & Security → **Open Anyway**, or `xattr -dr
com.apple.quarantine /Applications/Pet.app`.

A build you compiled yourself is never quarantined, so this only affects people
installing from a release. Notarising with a paid Apple Developer ID is the
only way to remove the step for them.


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

## More

- [Architecture](../docs/ARCHITECTURE.md) — how it all fits together
- [Using the pet](../docs/USAGE.md)
- [CLI reference](../docs/CLI.md)
- [Skins](../docs/SKINS.md) — the `.petskin` format and sprite packs
- [Agent plugins](../docs/PLUGINS.md)
