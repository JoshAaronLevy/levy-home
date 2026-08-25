---
name: prepare-deploy
description: Create, verify, retain, commit, and push a Transporter-ready Levy Home IPA. Invoke explicitly for a completed Levy Home release.
---

# Prepare a Levy Home deployment

Use this workflow only when the user explicitly invokes `$prepare-deploy` for the Levy Home repository. It is for a completed change that is ready for a TestFlight handoff; it does not upload to TestFlight or submit anything to App Store Connect.

## Preflight

1. Work from the repository root and inspect `git status --short` and `git diff --check` before making any change.
2. If the worktree has modified, staged, or untracked files, stop before changing the version, building, pruning artifacts, committing, or pushing. Tell the user to commit or stash their work first. Never stash, commit, or discard it on their behalf at this stage.
3. Confirm the current branch, its upstream, and whether the remote has commits not present locally. If the branch is behind or diverged, stop and ask the user to reconcile it; do not build an artifact from an out-of-date release branch.
4. Read the current `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` values in `LevyHome.xcodeproj/project.pbxproj`, the App Store Connect export options, and the existing `deployments/` artifacts. Use the next patch version and next integer build number unless the user supplied an explicit version/build.

## Validate and build

1. Run the relevant existing validation for the completed change before the release build. Choose checks based on the affected code, and keep their results for the handoff.
2. Update only the necessary project-version fields using the repository’s established convention. Keep every target/configuration version in sync.
3. Create a fresh Release archive using the project’s established generic iOS destination and signing configuration. Confirm the expected `.xcarchive` exists before exporting it.
4. Export an App Store Connect IPA using `build/ExportOptions-AppStoreConnect.plist`, then copy the exact exported IPA to `deployments/LevyHome-<new_version>.ipa`.

## Verify the exact deployment artifact

Verify the copied IPA itself, not merely the archive or export directory:

- bundle identifier is `com.levyhome.app`;
- short version and build match the new values;
- `LevyHomeAPIBaseURL` is the production API URL unless the user explicitly requested a different environment;
- entitlements contain `aps-environment=production` and `get-task-allow=false`;
- `codesign --verify --deep --strict` succeeds and the signature is Apple Distribution; and
- run `scripts/verify-siri-ipa.sh` against the copied IPA.

If any archive, export, or verification step fails, stop. Do not prune artifacts, commit the version bump, or push. Preserve the failure evidence and report it.

## Retain release artifacts

Only after the exact copied IPA has passed every verification, retain the three newest direct `.ipa` files in `deployments/`, ordered by modification time. Remove only the older IPA artifacts. Report every removed filename. Do not remove a newly built IPA or unrelated deployment files.

## Commit and push

1. Recheck the worktree. The only intended tracked change at this point is `LevyHome.xcodeproj/project.pbxproj`; the new IPA is a release artifact and should remain untracked unless the repository already tracks deployment IPAs by established convention.
2. Stage only `LevyHome.xcodeproj/project.pbxproj`, inspect the staged file list, and commit it with exactly `Bumped version/build to <new_version>/<new_build>`.
3. Push the current branch and all committed changes to its configured remote upstream. If the push fails, do not undo the verified IPA or local commit; report both precisely.

## Handoff

Report the IPA path, version/build, SHA-256, validation/build results, artifacts pruned, commit hash, and push result. State clearly that the IPA is ready for manual upload through Transporter and that no TestFlight upload was performed.
