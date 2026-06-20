# TestFlight Readiness Guide

This guide captures the Stage 18 release-readiness path for internal TestFlight distribution. It prepares the app and backend for release validation without adding deferred product scope.

`levy-home` is the working project. `levy-home-app` remains deprecated conceptual reference only.

## Current Status

Stage 18 is prepared, but not release-certified.

The repo can be locally checked for Release build health, backend compile/test health, privacy manifest coverage, and obvious secret leakage. The full Stage 18 acceptance criteria still require external inputs that are not present in source control:

- Completed Stage 17 physical-device APNs and garage control verification.
- Apple Developer Team signing on the `LevyHome` target.
- Internal TestFlight access.
- Final release API URL.
- Production APNs configuration.
- Safe production Home Assistant facade configuration.
- A decision that selected controls are safe for internal testers, or a decision to disable them before distribution.

## Current Build Identity

| Setting | Current value |
| --- | --- |
| Project | `LevyHome.xcodeproj` |
| Scheme | `LevyHome` |
| App target | `LevyHome` |
| Test target | `LevyHomeTests` |
| Bundle ID | `com.levyhome.app` |
| Version | `0.1.0` |
| Build | `1` |
| Release API build setting | `LEVY_HOME_API_BASE_URL = http://localhost:4000` |
| Push entitlement | `aps-environment = development` |
| Developer Tools access | Debug-only Preferences toolbar item |

## Required Decisions Before Archive

### Release API URL

The Release configuration currently points at the development API URL:

```text
LEVY_HOME_API_BASE_URL = http://localhost:4000
```

Before archiving for TestFlight, set the Release value to the intended internal backend URL in Xcode build settings or an included release `.xcconfig`.

Do not ship a TestFlight build that still points to `localhost`; a TestFlight-installed iPhone will treat `localhost` as the phone itself, not Josh's Mac or the backend host.

### Signing And APNs

Before archiving:

- Set the Apple Developer Team for the `LevyHome` app target.
- Confirm the app identifier is `com.levyhome.app` or update the bundle ID consistently everywhere.
- Confirm the app identifier has Push Notifications enabled in Apple Developer.
- Use a distribution provisioning profile suitable for TestFlight.
- Confirm the archived app is signed for the production APNs environment.
- Configure the backend with `APNS_ENVIRONMENT=production` for production-distribution device tokens.
- Keep APNs private keys outside the repo.

The checked-in entitlements file currently declares `aps-environment` as `development` for local physical-device testing. Confirm the archived app's effective entitlements before upload.

### Backend Exposure And Controls

The API is currently an internal facade, not a hardened internet-facing production API.

Before distributing to internal testers:

- Host the API somewhere reachable by tester devices.
- Decide whether that host is private-network/VPN-only or public.
- If public, protect state-changing action endpoints before enabling real controls.
- Keep `/api/ha/events` protected with `LEVY_HOME_HA_WEBHOOK_SECRET`.
- Decide whether `/api/debug/send-test-push` is allowed in the internal environment.
- Confirm `HOME_ASSISTANT_MODE=live` only after entity IDs and curated actions are verified.
- Confirm the close-garage and lights-off actions are safe, or disable them for the build/environment.

## Local Preflight Commands

Run these from the repo root before attempting an archive:

```sh
npm run api:typecheck
npm run api:test
npm run api:build
```

Run iOS tests:

```sh
xcodebuild \
  -project LevyHome.xcodeproj \
  -scheme LevyHome \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' \
  -derivedDataPath build/DerivedData \
  test
```

Verify Release compilation without requiring a signing profile:

```sh
xcodebuild \
  -project LevyHome.xcodeproj \
  -scheme LevyHome \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  -derivedDataPath build/DerivedDataRelease \
  CODE_SIGNING_ALLOWED=NO \
  build
```

Check the currently configured API URL in the built app:

```sh
/usr/libexec/PlistBuddy \
  -c 'Print LevyHomeAPIBaseURL' \
  build/DerivedDataRelease/Build/Products/Release-iphoneos/LevyHome.app/Info.plist
```

Confirm no obvious source-controlled secret values are present:

```sh
rg -n "APNS_PRIVATE_KEY|HOME_ASSISTANT_TOKEN|LEVY_HOME_HA_WEBHOOK_SECRET|BEGIN PRIVATE|AuthKey_.*\\.p8" \
  --glob '!node_modules/**' \
  --glob '!apps/api/.env' \
  .
```

Documentation examples and placeholder environment names are expected. Real values are not.

## Archive Flow

Use Xcode for the first archive because signing and TestFlight upload errors are easier to inspect there.

1. Open `LevyHome.xcodeproj`.
2. Select the `LevyHome` scheme.
3. Select `Any iOS Device` or a connected physical iPhone.
4. Confirm the `LevyHome` target has the correct Team, bundle ID, signing, version, build number, and Release API URL.
5. Choose `Product -> Archive`.
6. In Organizer, validate the archive.
7. Upload to App Store Connect for internal TestFlight.

Equivalent CLI archive command after signing is configured:

```sh
xcodebuild \
  -project LevyHome.xcodeproj \
  -scheme LevyHome \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  -archivePath build/LevyHome.xcarchive \
  archive
```

## Internal TestFlight Smoke Test

Use a physical iPhone. Simulator cannot validate native APNs tokens or TestFlight install behavior.

- Install the TestFlight build.
- Launch the app.
- Confirm Home loads against the intended backend.
- Confirm Activity loads recent events.
- Confirm Notifications opens and stays history-focused.
- Confirm Preferences opens and shows notification delivery status.
- Confirm Developer Tools behavior matches the chosen internal policy.
- Register for notifications on device.
- Confirm the backend records an APNs device with production environment.
- Send one debug push only if the internal environment allows debug push.
- Send one garage event through the intended backend.
- Confirm the notification arrives or is skipped according to preferences.
- Confirm Activity records the event and push status.
- Confirm Home reflects the latest garage/light status.
- Confirm selected controls are safe and enabled as intended, or disabled if not approved.

## Stage 18 Exit Criteria

Stage 18 is complete only when:

- Stage 17 has been physically verified.
- A signed Release archive succeeds.
- The build uses a non-localhost release API URL.
- The archived app's APNs entitlement and backend APNs environment are production-aligned.
- Developer Tools behavior follows the internal distribution policy.
- No secrets are committed to app or API source.
- `PrivacyInfo.xcprivacy` reflects APIs currently used by the app.
- Internal TestFlight install launches.
- Selected controls are confirmed safe or disabled for the build.

