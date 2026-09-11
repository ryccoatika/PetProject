# Contributing

Thanks for taking a look. This is a small project with no build system to
fight: clone it, run `./build.sh`, and you have the app running.

## Getting set up

```sh
git clone https://github.com/ryccoatika/PetProject.git
cd PetProject/MacApp
./build.sh          # compiles, installs to ~/Applications, restarts the pet
```

You need macOS 12 or later and the Xcode command line tools (`xcode-select
--install`). Nothing else — no Homebrew, no package manager.

`./build.sh --no-install` builds without touching your installed copy.

### Working in Xcode

There is no `.xcodeproj` — a binary project file conflicts in every pull
request and would force everyone to install full Xcode. Instead there is a
Swift package, which Xcode opens natively:

```sh
open MacApp/Package.swift
```

That gives you indexing, jump-to-definition, breakpoints and Instruments, and
`swift build` works from the terminal. It builds the *binary*; the `.app`
bundle — Info.plist, icon, skins, signature — is assembled by `./build.sh`,
which is what you run to actually see the pet.

`Sources/Pet/DefaultSkins.swift` is generated from `Skins/*.petskin` by
`build.sh` and committed, so the package builds without a code generation
step. If you change a shipped skin, run `./build.sh` and commit the result —
CI checks it is not stale.

Start with [Architecture](docs/ARCHITECTURE.md); it explains how the agent
hooks, the state file, the loop and the drawing fit together.

## Making a change

- **One change per pull request.** A bug fix and a refactor in the same branch
  are hard to review and harder to revert.
- **Match the surrounding code.** Swift API Design Guidelines, four spaces, no
  semicolons, types in `MacApp/Sources/` named after what they hold.
- **Comment the *why*.** The code says what it does. A comment earns its place
  by explaining a decision that is not obvious — a workaround, a measured
  trade-off, an API that behaves unexpectedly.
- **New file, no build change.** `build.sh` compiles `Sources/*.swift`.

## Testing your change

There is no unit test suite. What there is instead:

```sh
./build/pet render sheet.png          # every skin against every pose
./build/pet render --tracks t.png     # every atlas track of every sprite pack
./build/pet icon 512 icon.png         # the app icon
```

Open the PNGs and look. For a drawing change this catches more than a test
would.

For behaviour, run the thing:

```sh
pet status          # what the running app thinks is happening
pet plugin status   # which agents are wired up, and where
cat ~/.config/pet/state
```

If you change how the pet reacts, you can drive it without an agent:

```sh
echo '{"tool_name":"Bash"}' | pet event PreToolUse    # it starts typing
echo '{}' | pet event Stop                            # it celebrates
```

Two things worth knowing before you measure anything:

- **Running any shell command fires the hooks**, so the pet is in its *working*
  state while you measure. Write a stale event first to measure idle:
  `echo "Stop||$(( $(date +%s) - 3600 ))" > ~/.config/pet/state`
- **The app caches nothing across launches** except preferences and the config
  folder, so `pet restart` is a clean slate.

If you touch anything that edits an agent's config, test it against a file that
already contains somebody else's hooks, and confirm they survive both install
and uninstall. That is the failure mode that matters most here.

## Branches

- **`develop`** is where work lands. Branch from it, and open your pull request
  against it. It is the default branch, so GitHub picks it for you.
- **`main`** is what has been released. Only the maintainer merges `develop`
  into `main`, and that merge publishes a release.

## Sending it

```sh
git switch develop
git pull
git switch -c short-description
# ... commit ...
git push -u origin short-description
```

Then open a pull request **against `develop`**. The template asks what changed, why, and how you
checked it — the third one is the part reviewers care about most.

Commit messages: a short imperative summary line, then a blank line, then the
why. Look at `git log` for the house style.

CI builds the app and renders the sheets on every pull request. It will catch a
compile error; it cannot catch a pet that looks wrong, so say what you saw.

## Adding things

- **A skin** — a `.petskin` JSON file. See [Skins](docs/SKINS.md). Drop it in
  `MacApp/Skins/` to ship it, or `~/.config/pet/skins` to keep it local.
- **An agent** — a `HookHost` entry and a line in `HookHost.all`. See
  [Agent plugins](docs/PLUGINS.md). Check the agent's real payload before you
  write the event names; they differ more than you would expect.
- **A CLI command** — a case in `CLI.run` and a function in the matching
  `CLI+*.swift`, plus a line in `CLI.help()`.

## Reporting a bug

Include `pet status` and `pet plugin status` output, your macOS version, and
which agent you use. If the pet misbehaves visually, a screen recording beats a
description.
