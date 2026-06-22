# Levy Home

Native SwiftUI iOS app for a curated family smart-home notification and control experience.

## Development

Open `LevyHome.xcodeproj` in Xcode, select the `LevyHome` scheme, and run on an iPhone simulator. See `docs/06-ios-simulator-testing-guide.md` for command-line and Xcode testing steps.

For the shopping list CRUD plus WebSocket local proof, see `docs/09-shopping-list-realtime-local-verification.md`.

## Backend API

The Stage 10 backend facade lives in `apps/api`. It defaults to safe mock Home Assistant mode.

```sh
npm install
cp apps/api/.env.example apps/api/.env
npm run api:dev
```

Useful checks:

```sh
npm run api:typecheck
npm run api:test
npm run api:build
```

See `docs/07-home-assistant-facade.md` for the status/action endpoints and Home Assistant configuration.
