# iOS Simulator Testing Guide

This is a practical manual-testing cheat sheet for running Levy Home in Xcode Simulator. It is written for a Node/frontend developer who is comfortable with terminal workflows but newer to Xcode, Swift, and iOS simulator tooling.

`levy-home` is the working project. `levy-home-app` is deprecated conceptual reference only.

## Current Status

Stage 19 has added a Preferences Theme setting with System, Light, and Dark options plus app-wide light/dark styling. The current iOS app builds and launches in Simulator with live Home overview loading/error/refresh states, live curated Home quick actions with confirmation/progress/result states, the live Activity timeline from Stage 8, the Preferences tab from Stage 9, product-safe push registration status, product-safe API sync status, local garage preference sync state, and persisted theme preference state. Simulator intentionally reports APNs registration as unavailable and skips API device sync until a physical-device APNs token exists; a native APNs token and APNs delivery require a signed build on a physical iPhone plus backend APNs credentials. Model/API client/view-model tests can run with `xcodebuild test` or Xcode's `Cmd-U`.

Update this guide if the project name, scheme name, bundle identifier, or derived-data path changes in a later stage.

Current values:

| Setting | Current value | How to confirm |
| --- | --- | --- |
| Project file | `LevyHome.xcodeproj` | `ls *.xcodeproj` |
| Workspace file | None currently | `ls *.xcworkspace` |
| Scheme | `LevyHome` | `xcodebuild -list -project LevyHome.xcodeproj` |
| Test target | `LevyHomeTests` | Xcode test navigator or `xcodebuild test` |
| Verified simulator | `iPhone 17 Pro`, iOS 26.5 | `xcrun simctl list devices available` |
| Bundle ID | `com.levyhome.app` | Xcode target settings or built app `Info.plist` |

Stage 13 physical-device note:

- The app target now includes the Push Notifications capability and `LevyHome/Resources/LevyHome.entitlements` with `aps-environment` set to `development`.
- To test native APNs token registration, choose a physical iPhone in Xcode, set your Apple development team on the `LevyHome` target if Xcode asks, run the app, open Preferences, tap the debug-only Developer Tools wrench, and tap `Register For Push`.
- The simulator should not prompt for or receive a native APNs token; it should show device registration as unavailable.

## First-Time Sanity Checks

Run these from the repo root:

```sh
cd /Users/joshlevy/Desktop/levy-home
xcode-select -p
xcodebuild -version
xcrun simctl list devices available
```

What you want:

- `xcode-select -p` points into Xcode, usually `/Applications/Xcode.app/Contents/Developer`.
- `xcodebuild -version` prints an installed Xcode version.
- `simctl` lists at least one available iPhone simulator.

If command-line tools point somewhere unexpected, fix the selected Xcode:

```sh
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
```

## Easiest Manual Flow In Xcode

This is the most beginner-friendly workflow and the one to use first.

1. Open the project:

```sh
open LevyHome.xcodeproj
```

If the repo has a workspace instead, open that:

```sh
open LevyHome.xcworkspace
```

2. In Xcode, choose the `LevyHome` scheme from the top toolbar.

3. Choose your simulator device, for example `iPhone 17 Pro`.

4. Press `Cmd-R` or click the Run button.

5. Wait for the build to finish and the Simulator to open.

6. Confirm the current stage's acceptance criteria from `docs/03-implementation-roadmap.md`.

Useful Xcode shortcuts:

| Shortcut | Action |
| --- | --- |
| `Cmd-R` | Build and run app |
| `Cmd-U` | Run tests |
| `Cmd-B` | Build only |
| `Cmd-Shift-K` | Clean build folder |
| `Cmd-0` | Show/hide left navigator |
| `Cmd-Shift-Y` | Show/hide debug console |

## Command-Line Build And Run

Use this when you want a repeatable terminal workflow.

### 1. Confirm Schemes

For a project:

```sh
xcodebuild -list -project LevyHome.xcodeproj
```

For a workspace:

```sh
xcodebuild -list -workspace LevyHome.xcworkspace
```

### 2. Boot The Simulator

```sh
xcrun simctl boot "iPhone 17 Pro" || true
open -a Simulator
```

If your installed device name differs, list devices and copy the exact name:

```sh
xcrun simctl list devices available
```

### 3. Build For Simulator

Project version:

```sh
xcodebuild \
  -project LevyHome.xcodeproj \
  -scheme LevyHome \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' \
  -derivedDataPath build/DerivedData \
  build
```

Workspace version:

```sh
xcodebuild \
  -workspace LevyHome.xcworkspace \
  -scheme LevyHome \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' \
  -derivedDataPath build/DerivedData \
  build
```

### 4. Install The Built App

```sh
xcrun simctl install booted build/DerivedData/Build/Products/Debug-iphonesimulator/LevyHome.app
```

### 5. Find The Bundle ID

```sh
/usr/libexec/PlistBuddy \
  -c 'Print CFBundleIdentifier' \
  build/DerivedData/Build/Products/Debug-iphonesimulator/LevyHome.app/Info.plist
```

### 6. Launch The App

The current bundle identifier is `com.levyhome.app`:

```sh
xcrun simctl launch booted com.levyhome.app
```

## Run Tests

Use these commands to run the `LevyHomeTests` unit test target.

Project version:

```sh
xcodebuild \
  -project LevyHome.xcodeproj \
  -scheme LevyHome \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' \
  -derivedDataPath build/DerivedData \
  test
```

Workspace version:

```sh
xcodebuild \
  -workspace LevyHome.xcworkspace \
  -scheme LevyHome \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' \
  -derivedDataPath build/DerivedData \
  test
```

## Manual Theme Checks

Use this after Stage 19 or any later visual styling changes.

1. Build, install, and launch the app in Simulator using the command-line flow above or Xcode `Cmd-R`.
2. Open Preferences.
3. Confirm the Appearance card shows a Theme row.
4. Tap Theme.
5. Confirm System, Light, and Dark rows appear and the selected row has a checkmark.
6. Choose System, then toggle the simulator appearance:

```sh
xcrun simctl ui booted appearance light
xcrun simctl ui booted appearance dark
```

7. Confirm the app follows the simulator appearance in System mode.
8. Choose Light and confirm the app stays light when the simulator is dark.
9. Choose Dark and confirm the app stays dark when the simulator is light.
10. Quit and relaunch the app, then confirm the last selected Theme value persists.

## Clean Builds

If Xcode seems confused, start with the light clean:

```sh
xcodebuild \
  -project LevyHome.xcodeproj \
  -scheme LevyHome \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' \
  clean
```

If that is not enough, remove local derived data for this repo:

```sh
rm -rf build/DerivedData
```

For stubborn Xcode state, use Xcode's menu:

```text
Product -> Clean Build Folder
```

or press `Cmd-Shift-K`.

## Simulator Basics

Boot/open Simulator:

```sh
xcrun simctl boot "iPhone 17 Pro" || true
open -a Simulator
```

Shut down all simulators:

```sh
xcrun simctl shutdown all
```

Erase one simulator:

```sh
xcrun simctl erase "iPhone 17 Pro"
```

Erase all simulator content and settings:

```sh
xcrun simctl erase all
```

Use `erase all` sparingly. It removes installed apps and simulator state.

## Logs And Debugging

The easiest log view is Xcode's debug console after pressing `Cmd-R`.

From terminal, stream logs for the running app after you know the process name:

```sh
xcrun simctl spawn booted log stream --level debug --predicate 'process == "LevyHome"'
```

If the app crashes immediately, launch from Xcode first so Xcode shows the crash and call stack.

## Screenshots And Recordings

Take a simulator screenshot:

```sh
xcrun simctl io booted screenshot /tmp/levy-home-screenshot.png
open /tmp/levy-home-screenshot.png
```

Record the simulator screen:

```sh
xcrun simctl io booted recordVideo /tmp/levy-home-recording.mov
```

Stop recording with `Ctrl-C`, then open it:

```sh
open /tmp/levy-home-recording.mov
```

## Local API Notes For Later Stages

For iOS Simulator, `localhost` usually points to your Mac, so a simulator app can often call a local API like:

```text
http://localhost:4000
```

For a physical iPhone, `localhost` means the phone itself. Use your Mac's LAN IP instead, for example:

```text
http://192.168.1.25:4000
```

Find your Mac's LAN IP:

```sh
ipconfig getifaddr en0
```

The backend lives in `apps/api`. For local simulator testing, start it on port `4000`:

```sh
npm run api:build
npm run api:start
```

For Home Assistant phone activity verification, first configure the live Home Assistant env values plus either `HOME_ASSISTANT_PHONE_ENTITIES` or `HOME_ASSISTANT_PHONE_ENTITY_PATTERNS`, then run:

```sh
scripts/verify-home-assistant-activity-simulator.sh
```

That Phase 7 runner starts a known local API process with activity ingestion enabled, waits for a `phone_state_changed` record in `/api/events`, then builds, installs, and launches the simulator app with `LEVY_HOME_API_BASE_URL=http://localhost:4000`.

## Stage-By-Stage Manual Testing Pattern

For each implementation stage:

1. Read that stage in `docs/03-implementation-roadmap.md`.
2. Build and run in Xcode with `Cmd-R`.
3. Perform the stage's manual test plan.
4. Run unit tests with `Cmd-U` or `xcodebuild test` if tests exist for that stage.
5. Confirm no unrelated scope slipped in.
6. Capture a screenshot if the stage changes visible UI.

## Common Problems

| Symptom | First thing to try |
| --- | --- |
| Xcode cannot find scheme | Run `xcodebuild -list`, then select the correct scheme in Xcode. |
| Simulator is not listed | Open Xcode, go to `Window -> Devices and Simulators`, and install/boot a simulator runtime. |
| Build succeeds but app does not open | Install and launch manually with `simctl`, or press `Cmd-R` in Xcode. |
| App still shows old behavior | Clean build folder with `Cmd-Shift-K`, then run again. |
| Network call fails in simulator | Confirm local API is running, confirm API base URL, and try opening the URL in Safari inside the Simulator. |
| Permission prompt does not appear again | Delete the app from Simulator or erase the simulator to reset permissions. |
| APNs push does not work in simulator | Expected for this project. Real remote push testing requires a physical iPhone and later APNs stages. |

## Quick Command Cheat Sheet

```sh
cd /Users/joshlevy/Desktop/levy-home

# List simulators
xcrun simctl list devices available

# Boot simulator
xcrun simctl boot "iPhone 17 Pro" || true
open -a Simulator

# Build
xcodebuild -project LevyHome.xcodeproj -scheme LevyHome -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' -derivedDataPath build/DerivedData build

# Build and install latest app, optionally overriding the API URL for one run
LEVY_HOME_API_BASE_URL=http://localhost:4000 scripts/build-install-simulator.sh

# Choose an exact simulator if duplicate names exist
SIMULATOR_DEVICE_ID='099E306C-A087-4E2F-9CFE-289EFFE62AAA' \
  LEVY_HOME_API_BASE_URL=http://localhost:4000 \
  scripts/build-install-simulator.sh

# Install
xcrun simctl install booted build/DerivedData/Build/Products/Debug-iphonesimulator/LevyHome.app

# Print bundle ID
/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' build/DerivedData/Build/Products/Debug-iphonesimulator/LevyHome.app/Info.plist

# Launch
xcrun simctl launch booted com.levyhome.app

# Test, after a test target exists
xcodebuild -project LevyHome.xcodeproj -scheme LevyHome -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' -derivedDataPath build/DerivedData test
```
