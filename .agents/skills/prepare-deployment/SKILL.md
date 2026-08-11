---
name: prepare-deployment
description: Prepare a Transporter/TestFlight release for Levy Home. Use only when the user explicitly asks to package the current Levy Home work for deployment, bump its version, create an IPA in deployments, or commit and push the release.
---

# Prepare Levy Home Deployment

Perform the complete Levy Home release handoff from `/Users/joshlevy/Desktop/levy-home`. Do not use this skill for ordinary development, planning, or simulator-only work.

## Scope and safeguards

- Treat explicit invocation as authorization to make the release changes, create the IPA, commit, and push the release work.
- Inspect the current branch, `origin/main`, and `git status` before editing. Never silently include unrelated or ambiguous user changes; identify them and ask before staging them.
- Do not upload to Transporter, submit to App Store Connect, or deploy external services. The output is a verified IPA and a Git handoff.
- If the requested version or build is omitted, increment the current patch version and integer build number by one. Keep every target and test configuration in `LevyHome.xcodeproj/project.pbxproj` aligned.

## Release workflow

1. Fetch `origin`, confirm the current branch and whether it is aligned with `origin/main`, then inspect:
   - `LevyHome.xcodeproj/project.pbxproj`
   - `build/ExportOptions-AppStoreConnect.plist`
   - the existing changelog convention, creating root `CHANGELOG.md` only when none exists
   - `git status --short` and the release diff
2. Add a concise changelog entry for the release. Record user-facing changes, not implementation minutiae.
3. Run relevant validation before archiving. Include API typecheck/tests for API changes and iOS tests when a usable simulator is available. Any required check failure blocks the release until resolved or explicitly waived by the user.
4. Bump `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` consistently in all app, extension, widget, intent, and test configurations.
5. Archive and export with the repository release settings:

```bash
xcodebuild archive \
  -project LevyHome.xcodeproj \
  -scheme LevyHome \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  -archivePath build/Archives/LevyHome-<version>-<build>.xcarchive \
  -derivedDataPath build/ArchiveDerivedData \
  -allowProvisioningUpdates
```

Wait for `build/Archives/LevyHome-<version>-<build>.xcarchive` to exist, then export it with `build/ExportOptions-AppStoreConnect.plist` to `build/AppStoreExports/LevyHome-<version>-<build>/`.

6. Copy the final IPA to `deployments/LevyHome-<version>.ipa`; verify that copied artifact directly, not just the archive or export directory:
   - `BundleIdentifier` is `com.levyhome.app`
   - short version and build match the requested release
   - `LevyHomeAPIBaseURL` is `https://levy-home.onrender.com`
   - `aps-environment` is `production`
   - `get-task-allow` is `false`
   - `codesign --verify --deep --strict` passes on the expanded app bundle
   - `scripts/verify-siri-ipa.sh deployments/LevyHome-<version>.ipa https://levy-home.onrender.com` passes
   - calculate and report the IPA SHA-256
7. Run `git diff --check`, review the exact staged release contents, and stage only the validated release files, including the IPA when it is tracked by this repository.
8. Git handoff:
   - On an up-to-date `main`, commit with a release message and push `origin main`.
   - On another branch, commit and push that branch; create a pull request to `main` with `gh pr create --base main --fill` when authenticated. If a PR cannot be created, report the exact remaining command or blocker.
9. Report the release version/build, final IPA path, SHA-256, verification results, and Git commit/push or PR outcome. State explicitly that the user still needs to upload the IPA with Transporter.
