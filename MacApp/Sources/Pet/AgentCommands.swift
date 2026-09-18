//  AgentCommands.swift
//  Desktop Pet
//
//  The create-pet and create-sprite commands installed into an agent
//  alongside its hooks, teaching it to make skins for the pet. Agents with
//  a skills mechanism (Claude Code, Codex) get them as SKILL.md skills,
//  modelled on Codex's own hatch-pet; the rest get command files in their
//  own dialect.

import Cocoa

enum AgentCommands {

    /// `wants` is the line telling the agent what to build: command files
    /// interpolate the host's own arguments placeholder ($ARGUMENTS,
    /// {{args}}, …); skills have no placeholder and defer to the request.

    static func skinBody(wants: String) -> String {
        """
        Create a new drawn skin for the desktop pet (the Pet.app menu bar creature).

        \(wants)

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

    static func spriteBody(wants: String) -> String {
        """
        Create a sprite pet (a codex-pets style spritesheet character) for the
        desktop pet (Pet.app).

        \(wants)

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

        The spritesheet is a PNG or WebP with a fully transparent background,
        8 columns of 192x208-pixel cells, so 1536 px wide; height is
        rows x 208. Rows are animation tracks, top to bottom:

        | Row | Track | Shows when |
        |-----|-------|------------|
        | 0 | Idle | sitting, and sleeping (slowed down) |
        | 1 | Run right | walking right |
        | 2 | Run left | walking left (mirror of row 1) |
        | 3 | Waving | the waving idle antic |
        | 4 | Jumping | a turn just finished, or a hover |
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
        1. Make a working folder `<id>/` with `pet.json` and the spritesheet.
        2. Run `pet pets install <path-to-folder>`.
        3. Run `pet skin <id>` to switch to it.
        4. `pet render --tracks <file.png>` renders every installed pack's
           tracks to one image for checking.
        """
    }

    /// Codex ships the curated hatch-pet skill, which composes its
    /// $imagegen system skill to draw the character — far better sheets
    /// than a scripted fallback, and its output is already the codex-pets
    /// atlas the desktop pet reads.
    static func codexSpriteBody(wants: String) -> String {
        """
        Create a sprite pet for the desktop pet (Pet.app), using the built-in
        hatch-pet skill.

        \(wants)

        Steps:
        1. Invoke the `hatch-pet` skill with this request. It composes the
           `$imagegen` system skill to draw the character and assembles
           `pet.json` and `spritesheet.webp` under
           `${CODEX_HOME:-~/.codex}/pets/<id>/`.
        2. Install the hatched pet into the desktop pet:
           `pet pets install ~/.codex/pets/<id>`
        3. Switch to it: `pet skin <id>`.
        4. Confirm with `pet status` that `current` shows the new id.

        No conversion is needed: the atlas hatch-pet produces — 8 columns of
        192x208 cells, 9 rows (idle, run right, run left, waving, jumping,
        failed, waiting, running, review) — is exactly what the desktop pet
        reads.

        If `pet` is not on the PATH, it is installed as /usr/local/bin/pet or
        ~/.local/bin/pet. If the hatch-pet skill is unavailable, script the
        sheet yourself to the same atlas layout (transparent PNG or WebP,
        unused frames fully transparent, feet at the bottom of each cell) and
        install the folder the same way.
        """
    }

    /// Markdown with frontmatter — opencode and Cursor command files.
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

    /// A SKILL.md, in the shape of Codex's curated skills — YAML frontmatter
    /// with a name and a trigger-rich description, body below.
    static func skill(name: String, description: String, body: String) -> String {
        """
        ---
        name: \(name)
        description: \(description)
        ---

        \(body)

        <!-- Written by `pet plugin install`; removed by `pet plugin uninstall`. -->
        """
    }

    static let skinDescription = "Design a new drawn skin for the desktop pet"
    static let spriteDescription = "Create a spritesheet pet for the desktop pet"
    static let skinHint = "the creature and its colours"
    static let spriteHint = "the character to draw"

    static let skinSkillDescription =
        "Design and install a drawn skin for the desktop pet (Pet.app, the menu "
        + "bar creature): a small .petskin JSON of five colours and silhouette "
        + "traits. Use when the user wants a new look, colours, creature or "
        + "mascot for their desktop pet as a drawn skin. Writes the file into "
        + "the pet's skins folder and switches to it with the pet CLI."
    static let spriteSkillDescription =
        "Create and install an animated spritesheet pet for the desktop pet "
        + "(Pet.app) in the codex-pets atlas format: 8 columns of 192x208 "
        + "cells, up to 11 animation rows, transparent unused cells. Use when "
        + "the user wants an animated character, mascot or sprite pet on their "
        + "desktop. Generates the sheet, then installs it with the pet CLI."
    static let codexSpriteSkillDescription =
        "Create and install an animated pet for the desktop pet app (Pet.app) "
        + "by composing the installed hatch-pet skill (and its $imagegen "
        + "system skill) to draw a codex-pets atlas, then installing the "
        + "hatched pet with the pet CLI. Use when the user wants an animated "
        + "character, mascot or sprite pet on their desktop."

    /// The line a command file uses to hand over what the user typed.
    static func wantsLine(_ args: String) -> String { "The user wants: \(args)" }
    /// Skills have no arguments placeholder; the request is the context.
    static let wantsFromRequest = "Follow the user's request for what to make."

    /// How a host wants its command files dressed.
    enum Style { case frontmatter, toml, skill }

    /// The two files for a host, in its command folder and dialect.
    /// `args` is the host's placeholder for the command's arguments;
    /// `hatchPet` swaps the sprite instructions for the ones that ride
    /// Codex's built-in hatch-pet skill.
    static func files(
        folder: String, args: String, style: Style, hatchPet: Bool = false
    )
        -> [(path: String, source: String)]
    {
        let wants = style == .skill ? wantsFromRequest : wantsLine(args)
        let skin = skinBody(wants: wants)
        let sprite = hatchPet ? codexSpriteBody(wants: wants) : spriteBody(wants: wants)
        switch style {
        case .skill:
            return [
                (
                    "\(folder)/create-pet/SKILL.md",
                    skill(name: "create-pet", description: skinSkillDescription, body: skin)
                ),
                (
                    "\(folder)/create-sprite/SKILL.md",
                    skill(
                        name: "create-sprite",
                        description: hatchPet
                            ? codexSpriteSkillDescription : spriteSkillDescription,
                        body: sprite)
                ),
            ]
        case .toml:
            return [
                (
                    "\(folder)/create-pet.toml",
                    toml(description: skinDescription, body: skin)
                ),
                (
                    "\(folder)/create-sprite.toml",
                    toml(description: spriteDescription, body: sprite)
                ),
            ]
        case .frontmatter:
            return [
                (
                    "\(folder)/create-pet.md",
                    markdown(description: skinDescription, hint: skinHint, body: skin)
                ),
                (
                    "\(folder)/create-sprite.md",
                    markdown(description: spriteDescription, hint: spriteHint, body: sprite)
                ),
            ]
        }
    }
}
