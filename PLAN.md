# Noise Alert — Implementation Plan

**Goal:** phone app that captures aircraft noise events (dB + GPS + time + short clip), identifies the
responsible flight, and produces a ready-to-send complaint email from the user's own mail account.

## Decisions locked

| Area | Decision | Why |
|---|---|---|
| Stack | **Flutter** (iOS + Android, one codebase) | Raw PCM access, TFLite audio models, background service, native mail composer all available |
| Sending | **Device mail composer** (`flutter_email_sender`) | Mail leaves the *user's* mailbox. We store no personal data off-device, so we are not a GDPR controller |
| Storage | **On-device SQLite only** (`sqflite`, hand-written SQL) | Same reason. Export = CSV / `.eml`, never an upload |
| Distribution | Sideload/TestFlight beta, then free public store listing | Store constraints designed in from day 1, not bolted on |
| Auto-detect | **Phase 2** (YAMNet) | v1 must first nail the boring bits: dB, GPS, match, email |

### Why "no backend" actually solves the GDPR problem
- Name / postcode / email / GPS trace live only in the phone's app sandbox.
- The complaint is sent *by the user, from their own address*. We never see it.
- The durable, collatable record is the user's own **Sent** folder, plus an optional **BCC to the
  flight-watch group's shared mailbox**. The group (or the airport) is the controller of that
  mailbox, which they already are for complaints today.
- A local CSV/PDF export lets a user hand over their own evidence pack on request.
- Cost of this choice: one tap to send. Fully-autonomous sending is impossible without a relay
  server, and that would put personal data on our infrastructure. Accepted.

## Architecture

```
lib/
  core/          config, permissions, result types, logging
  data/
    audio/       PCM capture, A-weighting filter, LAeq/LAmax, WAV/M4A writer
    location/    geolocator wrapper, accuracy gating
    flights/     AdsbLolClient, AirplanesLiveClient, OpenSkyClient, FlightMatcher
    storage/     sqflite DB: snaps, matches, profile, settings
    mail/        template renderer + flutter_email_sender
  domain/        Snap, AcousticMetrics, AircraftSample, FlightMatch, ComplaintDraft (hand-written)
  features/
    snap/        the big button + live dB meter
    history/     list of snaps, status (matched / sent / unmatched)
    review/      confirm-flight screen before sending
    settings/    profile, recipients, calibration, clip on/off
  listener/      PHASE 2: foreground service + YAMNet classifier
```
State: **Riverpod 2.x** (`StateNotifierProvider`, `ConsumerWidget`). Models: **hand-written**
immutable classes with `copyWith` / `toJson` / `fromJson`. DB: **sqflite**, hand-written SQL.
HTTP: **`package:http`**.

**No code generation.** The original plan was freezed + json_serializable + drift + dio. Dropped
during M0: on Flutter 3.47 the `build_runner` chain pinned `analyzer` to a version that conflicted
with the SDK's own, and `drift_dev` dragged the conflict wider. Hand-writing four model classes and
six SQL statements cost about an hour once; the generator chain would have cost that on every SDK
bump. `dio` went the same way — nothing here needs interceptors, so `package:http` is one less
constraint to satisfy.

## The three hard problems

### 1. Decibels on an uncalibrated phone mic
- Capture **raw PCM** (**48 kHz** mono) rather than a package's smoothed level, so we control the
  maths. 48 kHz is mandatory, not a preference: the A-weighting curve has a pole pair at 12.2 kHz,
  and at the usual 16 kHz voice rate that section collapses against Nyquist and the response stops
  being A-weighting at all. See `AWeighting.minimumRecommendedSampleRate`.
- Apply an **A-weighting biquad cascade**, then compute **LAeq** (energy average over the window) and
  **LAmax** (fast, 125 ms). These are the two numbers airports and councils actually use; a bare
  "peak dB" gets a complaint dismissed.
- Disable AGC / voice processing on the audio session, otherwise the OS quietly compresses the very
  thing we are measuring.
- **Calibration screen**: per-device offset. Two routes — (a) enter a reading taken side-by-side with
  a real SPL meter, (b) ship a table of known offsets for common handsets. Store offset + device
  model; stamp every snap with `calibrated: true/false`.
- Every email states the method and whether it was calibrated. Overclaiming accuracy is the fastest
  way to get the whole complaint stream ignored.

### 2. Matching a sound to a flight
Primary path is a **live query at the moment of the snap**, which is far more reliable than
historical lookup and dodges the paid-API problem entirely.

- **Sound is late.** A jet at 3,000 ft slant range was overhead about 2.7 s before you heard it
  (343 m/s). Search a window of **T−45 s to T+10 s**, not just T.
- Query aircraft within ~25 nm of the GPS fix:
  - `adsb.lol` `/v2/point/{lat}/{lon}/{radius}` — free, no key today, live only.
  - `airplanes.live` — free, 1 req/s, 250 nm max radius. Second opinion.
  - **OpenSky** — free, OAuth2 client-credentials, 4,000 credits/day, and crucially serves data
    **up to 1 hour retrospectively**. This is our back-fill for snaps taken offline.
- **Score** each candidate on slant range at closest approach, elevation angle (directly overhead
  beats 10 nm away at the same altitude), altitude, and time alignment after propagation delay.
  Emit a `confidence` plus the runner-up list.
- **Never auto-fill a flight number the user has not seen.** The review screen shows the best match,
  the alternates, and an "unidentified aircraft" option. A complaint naming the wrong airline is
  worse than one naming none.

### 3. Background listening (Phase 2)
- **YAMNet** TFLite (~4 MB, 0.96 s frames; AudioSet classes `Aircraft`, `Aircraft engine`,
  `Jet engine`, `Propeller`, `Fixed-wing aircraft`). Not CLAP — CLAP is far too heavy for a phone.
- Trigger = aircraft score over threshold for N consecutive frames **AND** LAeq above a floor. Two
  gates kills most false positives (lawnmowers, hairdryers, wind).
- Android: foreground service + `FOREGROUND_SERVICE_MICROPHONE` (Android 14+), persistent notification.
- iOS: `UIBackgroundModes: audio` with an active recording session. **Store-review risk** — Apple
  scrutinises always-on mic. Fallback if rejected: monitor while the app is open or the device is
  charging.
- Auto-snaps are queued for review, never auto-sent.

## Milestones

- **M0 — Scaffold.** Flutter project, CI (analyze + test), permissions plumbing, settings skeleton.
- **M1 — Snap core.** Big button, PCM capture, LAeq/LAmax, GPS, timestamp, optional 10 s M4A clip,
  persisted locally, history list. *Usable offline, produces real data.*
- **M2 — Flight match.** ADS-B clients + scoring + review screen with alternates and confidence.
- **M3 — Complaint email.** Profile (name/address/postcode/email), recipient sets per airport,
  form-letter template with tokens, attachment, mail-composer handoff, mark-as-sent.
- **M4 — Evidence quality.** Calibration flow, LAeq/LAmax presentation, CSV export, BCC-to-group.
- **M5 — Beta hardening.** Offline queue + OpenSky 1-hour back-fill, permission edge cases, battery,
  error states, TestFlight/APK distribution to the beta group.
- **M6 — Autonomous listening.** YAMNet, foreground service, thresholds, review queue.
- **M7 — Store release.** Privacy policy, data-safety forms, iOS usage strings, icons, screenshots.

## Key packages
`record` (raw PCM) · `geolocator` · `permission_handler` · `sqflite` · `flutter_riverpod` (2.x) ·
`http` · `flutter_email_sender` · `url_launcher` (mailto fallback) · `just_audio` (clip preview) ·
`device_info_plus` + `package_info_plus` (handset/OS stamped into every letter) · `path_provider` ·
`share_plus` (export fallback) · `tflite_flutter` (M6) · `flutter_foreground_task` (M6)

## Known risks
1. **iOS mail composer needs a configured Mail account.** No account, no composer. Fallback:
   `mailto:` via `url_launcher` (loses the attachment) plus "export and attach manually".
2. **ADS-B coverage gaps.** Low, military and non-ADS-B traffic simply will not appear. The UI must
   handle "no candidate" gracefully rather than guessing.
3. **adsb.lol may introduce API keys** (their docs flag it). Keep clients behind an interface so
   sources are swappable; OpenSky is the keyed fallback that already works.
4. **Ambient speech in clips.** Recording bystanders is the one genuine privacy risk here. Clip
   defaults to off, user previews before sending, clip deletable from history.
5. **Uncalibrated dB presented as fact** would discredit the whole dataset. Always label it.

## Sources
- https://github.com/adsblol/api
- https://github.com/airplanes-live/api-archive
- https://openskynetwork.github.io/opensky-api/rest.html
- https://fr24api.flightradar24.com/docs/faq (enterprise only — ruled out)
- https://pub.dev/packages/flutter_email_sender
