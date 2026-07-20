# Stretch Goals

## Stage 5 — Two-way talk

**Status:** Deferred until a secure, end-to-end talkback transport is proven on
a physical iPhone.

Levy Home’s Camera tab can currently use the backend-brokered MJPEG stream for
video and the allowlisted Home Assistant controls for PTZ and camera-speaker
volume. That does **not** provide iPhone-to-camera audio.

### Current limitation

The installed Eufy bridge reports `start_talkback` and `stop_talkback` commands
and accepts continuous audio frames upstream, but Home Assistant does not expose
them as a typed talkback service. The raw `eufy_security.send_message` bridge
escape hatch must not be exposed to Levy Home because it would allow arbitrary
bridge JSON and break the app-to-backend security boundary.

The Home Assistant MJPEG proxy is video-only and cannot be treated as a two-way
audio transport. The camera microphone/speaker switches are device settings,
not proof that an iPhone talk session is active.

### Required proof before implementation

1. On a physical iPhone, prove this full chain: iPhone microphone capture →
   authenticated Levy Home transport → Eufy bridge/camera speaker.
2. Prove explicit stop, timeout, network-loss, route-change, and interruption
   behavior. Confirm the camera no longer receives audio after stop.
3. Choose a dedicated, backend-brokered talkback session contract. It must use
   short-lived access, keep Home Assistant/Eufy credentials server-side, and
   never reuse an unauthenticated stream URL.
4. Confirm audio format requirements and any needed server-side transcoding for
   the Eufy bridge protocol before capturing microphone audio in the app.

### Implementation requirements once supported

- Request microphone permission only when the user first enables talk; preserve
  a clear denial and retry path.
- Configure `AVAudioSession` deliberately for recording and playback, including
  interruption and route-change handling.
- Use a neutral connecting state while the talkback session starts. Change the
  microphone control to its red active background only after the backend and
  audio transport confirm that talk is live.
- Tapping again, leaving the Camera view, backgrounding the app, route loss,
  timeout, or any error must stop microphone capture and the backend session,
  then restore the default control appearance.
- Decide and document whether talk is push-to-talk or a latched toggle before
  shipping. The requested initial interaction is a latched toggle, but it must
  remain reversible if physical testing indicates push-to-talk is safer.
- Do not log microphone audio, raw bridge messages, stream URLs, or credentials.

### Exit criteria

Two-way talk is only complete when an actual physical iPhone can start and stop
audible talkback to the Kids Room camera reliably, with safe cleanup and no
Home Assistant credentials exposed to the app.
