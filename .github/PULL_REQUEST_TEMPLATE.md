<!-- Open this against `develop`. Pull requests into `main` are release merges
     and are made by the maintainer. -->

### What does this change?

<!-- One or two sentences. What is different after this is merged? -->

### Why?

<!-- The problem, or the itch. Link an issue if there is one: Fixes #123 -->

### How did you check it?

<!-- The part reviewers care about most. Anything that applies:
     - commands you ran, and what you saw
     - `./build/pet render sheet.png` if you touched drawing (attach it)
     - the agent you tested against, if you touched hooks
     - what you did NOT test -->

### Notes for the reviewer

<!-- Trade-offs you made, alternatives you rejected, anything you are unsure
     about. Saying "I am not certain about X" is welcome, not a weakness. -->

---

- [ ] `./build.sh` succeeds and the pet runs
- [ ] I looked at the pet afterwards, not only at the build output
- [ ] If I changed hook registration, another tool's hooks survive install and uninstall
- [ ] Docs updated if behaviour changed
- [ ] `CHANGELOG.md` updated under `## [Unreleased]` if this is user-visible
- [ ] Targeted at `develop`
