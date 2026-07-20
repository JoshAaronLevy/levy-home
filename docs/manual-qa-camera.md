# Kids Room Camera release checklist

Use this checklist only when a physical iPhone is available. The current
implementation deliberately excludes cry sensitivity and two-way talkback; do
not test or describe either as shipped functionality.

## Before testing

- Confirm the live Home Assistant catalog still contains `camera.kids_room`,
  `number.kids_room_speaker_volume`, `eufy_security.start_p2p_livestream`,
  `eufy_security.stop_p2p_livestream`, and `eufy_security.ptz`.
- Confirm the deployed API is configured with the separate
  `LEVY_HOME_CAMERA_ACCESS_TOKEN`, not the Home Assistant long-lived token.
- Start with the physical Kids Room camera in its safe resting position.

## Physical-device checks

- Open Camera in portrait. Verify the stream starts, shows live frames with
  acceptable latency, and shows the loading/unavailable states appropriately.
- Move up, down, left, and right once each. Confirm the correct physical
  movement, then return the camera to its safe position.
- Open the speaker menu, read the current camera speaker volume, change it, and
  confirm it takes effect at the camera. Close the menu by tapping outside it.
- Open fullscreen, confirm landscape rotation, continuity of the live session,
  the compact translucent lower-corner controls, and the upper-right close
  control. Return to portrait and confirm the stream remains available.
- Switch tabs, background and foreground the app, lock and unlock the phone,
  temporarily interrupt network access, restore it, and verify recovery or a
  clear retry state. Confirm that leaving Camera or terminating playback stops
  the active session.
- Inspect the device and API logs for the test window. They must not contain
  camera frames, room audio, Home Assistant tokens, the Levy Home camera bearer
  token, full stream URLs, or raw Home Assistant response payloads.

## Completion

- Stop the camera session and manually confirm the camera is back in its safe
  resting position.
- Record the device model, iOS version, API deployment/version, and date with
  the test result. Do not attach camera imagery, audio, credentials, or stream
  captures to the record.
