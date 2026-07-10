# MacWiki Beta Release Checklist

> **RETIRED — historical reference only.** Public release and notarization are
> outside the current internal-beta scope. The active readiness contract is
> `INTERNAL_BETA_QUALITY_PROGRAM.md`; use `scripts/internal_beta_preflight.sh`
> for CLI fallback evidence.

Use this checklist every time you publish a beta to GitHub.

## 0) Fast Path

Run the full non-manual preflight in one command:

```bash
./scripts/preflight_beta_release.sh \
  --identity "Developer ID Application: YOUR NAME (TEAMID)" \
  --notary-profile "macwiki-notary"
```

That command covers metadata consistency, repo hygiene, secret scan, build/test/release gates, signing, notarization, stapling, and `.app` packaging.

For the full guided publish flow (prompts + GitHub release upload), run:

```bash
./scripts/release_beta.sh \
  --identity "Developer ID Application: YOUR NAME (TEAMID)" \
  --notary-profile "macwiki-notary"
```

## 1) Product Freeze

- [ ] Pick the beta version (example: `v0.5.0-beta.1`).
- [ ] Write one-sentence scope for this beta.
- [ ] Confirm known caveats you are intentionally shipping.

## 2) macOS Readiness

- [ ] App icon exists and is applied (do not ship generic executable icon).
  - Generate/update default placeholder:
  ```bash
  ./scripts/generate_app_icon.sh
  ```
  - Import custom icon art:
  ```bash
  ./scripts/generate_app_icon.sh /absolute/path/to/custom-1024.png
  ```
- [ ] App name, version, and bundle metadata are correct (`Info.plist`).
- [ ] Packaged `Contents/Resources/BuildInfo.plist` records the release commit, branch, `GitDirty=false`, Xcode version, and Swift version.
- [ ] Package target, `Info.plist`, README, and packaged binary all agree on the minimum macOS version.
- [ ] Settings opens from `Cmd+,`.
- [ ] About panel includes app name/version plus license/trademark links.
- [ ] Keyboard-first flows work (`Cmd+K`, `Cmd+T`, `Cmd+Shift+I`).
- [ ] VoiceOver smoke pass on core navigation surfaces.
- [ ] Empty/error/loading states are legible in light and dark appearances.

## 3) Security and Privacy

- [ ] No secrets in source:
  ```bash
  rg -n "(?i)(api[_-]?key|client[_-]?secret|bearer\\s+[A-Za-z0-9._-]{16,}|(access|refresh|auth)[_-]?token\\s*[:=]\\s*[\\\"'][^\\\"']{8,}|password\\s*[:=]\\s*[\\\"'][^\\\"']+)" Sources Tests scripts README.md Package.swift
  ```
- [ ] Runtime tokens and API credentials are not hardcoded.
- [ ] Telemetry/crash behavior (if any) is disclosed in release notes.

## 4) Build, Test, and Packaging Gates

- [ ] Debug build passes:
  ```bash
  swift build
  ```
- [ ] Test suite passes:
  ```bash
  swift test
  ```
- [ ] Release build passes:
  ```bash
  swift build -c release
  ```
- [ ] `.app` beta artifact is packaged:
  ```bash
  ./scripts/package_beta_app.sh \
    --identity "Developer ID Application: YOUR NAME (TEAMID)" \
    --notary-profile "macwiki-notary"
  ```
- [ ] The packaged artifact is traceable to this release commit:
  ```bash
  /usr/libexec/PlistBuddy -c "Print :GitCommit" "dist/<MacWiki.app>/Contents/Resources/BuildInfo.plist"
  /usr/libexec/PlistBuddy -c "Print :GitDirty" "dist/<MacWiki.app>/Contents/Resources/BuildInfo.plist"
  ```
- [ ] Manual QA matrix is complete: `PUBLIC_BETA_QA_MATRIX.md`.

## 5) Repo Hygiene (Before First Public Push)

- [ ] Confirm local-only files are ignored and untracked:
  - `.agent/`
  - `AGENTS.md`, `CLAUDE.md`, `GEMINI.md`, `ANTIGRAVITY.md`
  - `MODEL_HANDOVER_*.md`
  - `macwiki-sidebar-audit.png`
  - `.build/`, `.swiftpm/`, `MacWikiURLCache/`, profiling files
- [ ] Verify:
  ```bash
  git status --short
  ```
- [ ] Release scripts are being run from a clean git tree only.

## 6) Publish to GitHub

Recommended: use the guided script.

```bash
./scripts/release_beta.sh \
  --identity "Developer ID Application: YOUR NAME (TEAMID)" \
  --notary-profile "macwiki-notary"
```

Manual commands are still available if needed:

```bash
git status --short
git push origin <current-branch>
git tag -a v0.5.0-beta.N -m "MacWiki beta v0.5.0-beta.N"
git push origin v0.5.0-beta.N
gh release create v0.5.0-beta.N --prerelease --generate-notes --title "MacWiki v0.5.0-beta.N"
```

## 7) CI Confirmation

- [ ] GitHub Actions CI is green for this commit (`swift build`, `swift test`, `swift build -c release`).
- [ ] If CI is red, fix and republish before announcing the beta.

## 8) App Artifact Upload

Upload the packaged `.zip` created by `package_beta_app.sh` to the prerelease:

```bash
gh release upload v0.5.0-beta.N dist/MacWiki-v0.5.0-beta.N.zip --clobber
```

If your packaged filename includes a timestamp, either rename it first or use the exact generated path.

## 9) Signing and Notarization (Required For Public Beta)

- [ ] Use a Developer ID signing identity for `package_beta_app.sh`:
  ```bash
  ./scripts/package_beta_app.sh \
    --identity "Developer ID Application: YOUR NAME (TEAMID)" \
    --notary-profile "macwiki-notary"
  ```
- [ ] The packaged app is notarized, stapled, and accepted by Gatekeeper before announcement.

## 10) Post-Release

- [ ] Smoke-test the released tag on a clean machine/user account.
- [ ] Track top issues discovered by beta users.
- [ ] Archive the current performance run from `scripts/profile_reader_open.sh` with the release artifacts or QA notes.
- [ ] Record outcomes in development log and QA report.
