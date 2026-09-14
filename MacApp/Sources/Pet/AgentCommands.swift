//  AgentCommands.swift
//  Desktop Pet
//
//  The /pet-skin and /pet-sprite commands installed into an agent alongside
//  its hooks, teaching it to make skins for the pet.

import Cocoa

enum AgentCommands {

    /// `args` is the host's own placeholder for "what the user typed after
    /// the command" — $ARGUMENTS, {{args}}, or a plain phrase where the host
    /// has no placeholder and simply appends the text.

    static func skinBody(args: String) -> String {
        """
        Create a new drawn skin for the desktop pet (the Pet.app menu bar creature).

        The user wants: \(args)

        A skin is one small JSON file:

        ```json
        {
          "id": "lowercase-unique-id",
          "name": "Display Name",
          "colors": {
            "body": "#F5AB5C",
            "bodyDark": "#D97E36",
            "belly": "#FFF3E0",
            "ink": "#3B2A1A",
            "accent": "#F08A69"
          },
          "traits": {
            "crest": "ears"
          }
        }
        ```

        Colors, all required, all hex: `body` is the main fur, `bodyDark` a
        darker shade of the same hue (shading, stripes, patches), `belly` the
        lightest (chest), `ink` the darkest of all (outlines, eyes, nose),
        `accent` the inner ear and nose. Pick a palette matching the request —
        do not copy the example.

        Traits: `crest` is required, one of `"ears"` (cat), `"floppy"` (dog),
        `"round"` (panda/bear) or `"spikes"` (dino). Optional booleans:
        `stripes` (tabby stripes in bodyDark), `whiskers`, `snout` (dog-like
        muzzle), `eyePatches` (panda eyes in bodyDark), `darkLimbs`
        (panda-style dark arms and legs).

        Steps:
        1. Run `pet skins dir` to find the skins folder.
        2. Write `<id>.petskin` there.
        3. Run `pet skin <id>` — the pet reloads and switches immediately.
        4. Confirm with `pet status` that `current` shows the new id.

        If `pet` is not on the PATH, it is installed as /usr/local/bin/pet or
        ~/.local/bin/pet.
        """
    }

    static func spriteBody(args: String) -> String {
        """
        Create a sprite pet (a codex-pets style spritesheet character) for the
        desktop pet (Pet.app).

        The user wants: \(args)

        A sprite pet is a folder holding `pet.json` and a spritesheet:

        ```json
        {
          "id": "lowercase-unique-id",
          "displayName": "Display Name",
          "description": "one line",
          "spriteVersionNumber": 2,
          "spritesheetPath": "spritesheet.png"
        }
        ```

        The spritesheet is a PNG with a fully transparent background,
        8 columns of 192x208-pixel cells, so 1536 px wide; height is
        rows x 208. Rows are animation tracks, top to bottom:

        | Row | Track | Shows when |
        |-----|-------|------------|
        | 0 | Idle | sitting, and sleeping (slowed down) |
        | 1 | Run right | walking right |
        | 2 | Run left | walking left (mirror of row 1) |
        | 3 | Waving | picked up and dragged |
        | 4 | Jumping | a turn just finished |
        | 5 | Failed | a tool reported a failure |
        | 6 | Waiting | waiting for the user |
        | 7 | Running | a tool is running (e.g. typing) |
        | 8 | Review | thinking between steps |
        | 9 | Look around, right | idle glancing (v2 only) |
        | 10 | Look around, left | idle glancing (v2 only) |

        Rules:
        - Frame counts per row are measured from the image, so a row may hold
          1 to 8 frames; leave unused frames fully transparent.
        - Rows may be omitted from the bottom up — anything missing falls back
          to Idle. A minimal pet is one row of idle frames; 11 rows is full v2.
        - The character should fill most of the cell with its feet at the
          bottom; cells are drawn anchored to the bottom.
        - Generate the sheet with a script (for example Python + Pillow):
          bold simple shapes, a consistent silhouette across frames, limbs
          shifted a few pixels between frames for motion.

        Steps:
        1. Make a working folder `<id>/` with `pet.json` and `spritesheet.png`.
        2. Run `pet pets install <path-to-folder>`.
        3. Run `pet skin <id>` to switch to it.
        4. `pet render --tracks <file.png>` renders every installed pack's
           tracks to one image for checking.
        """
    }

    /// Markdown with frontmatter — Claude Code, opencode and Cursor.
    static func markdown(description: String, hint: String, body: String) -> String {
        """
        ---
        description: \(description)
        argument-hint: \(hint)
        ---

        \(body)

        <!-- Written by `pet plugin install`; removed by `pet plugin uninstall`. -->
        """
    }

    /// Plain markdown — Codex prompts have no frontmatter.
    static func plain(body: String) -> String {
        """
        \(body)

        <!-- Written by `pet plugin install`; removed by `pet plugin uninstall`. -->
        """
    }

    /// Gemini CLI commands are TOML.
    static func toml(description: String, body: String) -> String {
        """
        # Written by `pet plugin install`; removed by `pet plugin uninstall`.
        description = "\(description)"
        prompt = \"\"\"
        \(body)
        \"\"\"
        """
    }

    static let skinDescription = "Design a new drawn skin for the desktop pet"
    static let spriteDescription = "Create a spritesheet pet for the desktop pet"
    static let skinHint = "the creature and its colours"
    static let spriteHint = "the character to draw"

    /// How a host wants its command files dressed.
    enum Style { case frontmatter, plain, toml }

    /// The two files for a host, in its command folder and dialect.
    /// `args` is the host's placeholder for the command's arguments.
    static func files(
        folder: String, args: String, style: Style
    )
        -> [(path: String, source: String)]
    {
        let skin = skinBody(args: args)
        let sprite = spriteBody(args: args)
        switch style {
        case .toml:
            return [
                (
                    "\(folder)/pet-skin.toml",
                    toml(description: skinDescription, body: skin)
                ),
                (
                    "\(folder)/pet-sprite.toml",
                    toml(description: spriteDescription, body: sprite)
                ),
            ]
        case .plain:
            return [
                ("\(folder)/pet-skin.md", plain(body: skin)),
                ("\(folder)/pet-sprite.md", plain(body: sprite)),
            ]
        case .frontmatter:
            return [
                (
                    "\(folder)/pet-skin.md",
                    markdown(description: skinDescription, hint: skinHint, body: skin)
                ),
                (
                    "\(folder)/pet-sprite.md",
                    markdown(description: spriteDescription, hint: spriteHint, body: sprite)
                ),
            ]
        }
    }
}
