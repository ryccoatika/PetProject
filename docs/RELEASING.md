# Releasing

For maintainers. A release is cut by merging `develop` into `main`.

## Steps

1. On `develop`, decide the new version and write it to `VERSION`
   (semantic versioning: breaking, feature, fix).
2. In `CHANGELOG.md`, move the entries out of `## [Unreleased]` into a new
   `## [x.y.z] - YYYY-MM-DD` section, and update the link definitions at the
   bottom.
3. Open a pull request from `develop` to `main` and merge it.

The Release workflow then does the rest: it reads `VERSION`, stops if that tag
already exists, takes the notes for that version out of `CHANGELOG.md`, builds
the disk image, creates the `vx.y.z` tag, and publishes a GitHub release with
the `.dmg` and a `.zip` attached.

The zip is what the app's in-app updater downloads: its SHA-256 is appended to
the release notes, and the updater refuses to install a download whose
checksum or reported version does not match. Do not edit that checksum line
out of the published notes.

## If it does not publish

- **"already released"** — `VERSION` was not bumped, so the tag exists. That is
  the guard working: merging `develop` into `main` for a documentation fix does
  not cut a release.
- **"CHANGELOG.md has no section for x.y.z"** — the version and the changelog
  disagree. The workflow refuses rather than publishing a release with empty
  notes.

## What ships

`MacApp/dmg.sh` builds the image. On a CI runner the window layout is skipped:
there is nobody to look at it, and a headless Finder holds the volume open
afterwards, which makes ejecting it fail. The image is still valid — it just
opens as a plain folder view rather than with the background and icon
positions. Build it locally if you want the arranged version attached instead.

The skip keys off `CI`. Set `PET_DMG_LAYOUT=1` to lay the window out anyway, or
`PET_DMG_LAYOUT=0` to skip it on your own machine.

The app is signed ad-hoc, not notarised, so the first launch of a downloaded
build needs System Settings → Privacy & Security → Open Anyway. Right-click →
Open stopped working for this in macOS 15. Notarising would need a paid Apple
Developer ID and the certificate in repository secrets.
