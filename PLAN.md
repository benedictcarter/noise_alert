# Noise Alert: Implementation Plan

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

Organised by function, not by layer. The layered version of this
(`core/` + `data/` + `domain/` + `features/`) was built first and replaced on 2026-08-22: it
scattered a single question across four directories, and it gave the question a privacy reviewer
actually asks, "what leaves the device", no home at all.

```
lib/
  net/           EVERY outbound call, and the only place a URL may appear
                 endpoints.dart (the whole list), client.dart, live_adsb.dart,
                 opensky.dart, postcodes.dart
  mic/           PCM capture, A-weighting filter, LA90/LAeq/LAmax, WAV writer
  where/         geolocator wrapper, accuracy gating, spherical geometry
  flights/       AdsbSource interface, FlightMatcher, the lookup and track cache
  map/           MapLibre widget, projection, overlay painter, hidden snapshot host
  chart/         the level trace, for the screen and for the attached PNG
  letter/        template renderer + flutter_email_sender
  snap/          Snap, the sqflite store, and SnapService: one event end to end
  me/            ComplainantProfile and AppSettings
  ui/            screens: snap, review, history, settings, welcome
  listener/      PHASE 2: foreground service + YAMNet classifier
```

Tuning constants sit with the lane they tune (`mic/config.dart`, `flights/config.dart`,
`map/config.dart`). Addresses do not: they are all in `net/endpoints.dart`, and
`test/outbound_surface_test.dart` fails the build if one appears anywhere else. See
[REVIEW.md](REVIEW.md).
State: **Riverpod 2.x** (`StateNotifierProvider`, `ConsumerWidget`). Models: **hand-written**
immutable classes with `copyWith` / `toJson` / `fromJson`. DB: **sqflite**, hand-written SQL.
HTTP: **`package:http`**.

**No code generation.** The original plan was freezed + json_serializable + drift + dio. Dropped
during M0: on Flutter 3.47 the `build_runner` chain pinned `analyzer` to a version that conflicted
with the SDK's own, and `drift_dev` dragged the conflict wider. Hand-writing four model classes and
six SQL statements cost about an hour once; the generator chain would have cost that on every SDK
bump. `dio` went the same way: nothing here needs interceptors, so `package:http` is one less
constraint to satisfy.

## The three hard problems

### 1. Decibels on a phone mic
- Capture **raw PCM** (**48 kHz** mono) rather than a package's smoothed level, so we control the
  maths. 48 kHz is mandatory, not a preference: the A-weighting curve has a pole pair at 12.2 kHz,
  and at the usual 16 kHz voice rate that section collapses against Nyquist and the response stops
  being A-weighting at all. See `AWeighting.minimumRecommendedSampleRate`.
- Apply an **A-weighting biquad cascade**, then compute **LAeq** (energy average over the window) and
  **LAmax** (fast, 125 ms). These are the two numbers airports and councils actually use; a bare
  "peak dB" gets a complaint dismissed.
- Disable AGC / voice processing on the audio session, otherwise the OS quietly compresses the very
  thing we are measuring.
- **No calibration.** Dropped deliberately (2026-08-20). The full-scale reference is fixed at
  120 dB SPL (`LevelReference.fullScaleDbSpl`) for every handset, and there is no setting, no offset
  field and no "uncalibrated" wording anywhere. Requiring someone to borrow a reference sound level
  meter before they may complain about a jet is a way of ensuring nobody complains.
- **The letter leads on the rise above background**, because that is the figure the fixed reference
  cannot distort: the offset is in the peak and in the background alike, so it cancels in the
  subtraction. A handset several decibels out still reports the right *rise*.
- **The background is the LA90 of the recording itself** (the level exceeded 90% of the time), not
  a mean and not the true minimum. A mean is dragged upwards by the aircraft, which is the very
  thing being measured against; the true minimum is one 125 ms block, so a single dropout or gap in
  the traffic would put the floor twenty decibels below anything real and make every event look
  preposterous. A recording that runs from before the aircraft until after it has gone contains its
  own quiet street, which is why recording from launch costs nothing.
- Every email states the method: handset, OS, sample rate, weighting, and that the peak and the
  background were read by one microphone in one recording.

### 2. Matching a sound to a flight
Primary path is a **live query at the moment of the snap**, which is far more reliable than
historical lookup and dodges the paid-API problem entirely.

- **Sound is late.** A jet at 3,000 ft slant range was overhead about 2.7 s before you heard it
  (343 m/s). Search a window of **T-45 s to T+10 s**, not just T.
- Query aircraft within ~25 nm of the GPS fix:
  - `adsb.lol` `/v2/point/{lat}/{lon}/{radius}`: free, no key today, live only.
  - `airplanes.live`: free, 1 req/s, 250 nm max radius. Second opinion.
  - **OpenSky**: free, OAuth2 client-credentials, 4,000 credits/day, and crucially serves data
    **up to 1 hour retrospectively**. This is our back-fill for snaps taken offline.
- **Score** each candidate on slant range at closest approach, elevation angle (directly overhead
  beats 10 nm away at the same altitude), altitude, and time alignment after propagation delay.
  Emit a `confidence` plus the runner-up list.
- **Never auto-fill a flight number the user has not seen.** The review screen shows the best match,
  the alternates, and an "unidentified aircraft" option. A complaint naming the wrong airline is
  worse than one naming none.

### 3. Background listening (Phase 2)
- **YAMNet** TFLite (~4 MB, 0.96 s frames; AudioSet classes `Aircraft`, `Aircraft engine`,
  `Jet engine`, `Propeller`, `Fixed-wing aircraft`). Not CLAP: CLAP is far too heavy for a phone.
- Trigger = aircraft score over threshold for N consecutive frames **AND** LAeq above a floor. Two
  gates kills most false positives (lawnmowers, hairdryers, wind).
- Android: foreground service + `FOREGROUND_SERVICE_MICROPHONE` (Android 14+), persistent notification.
- iOS: `UIBackgroundModes: audio` with an active recording session. **Store-review risk**: Apple
  scrutinises always-on mic. Fallback if rejected: monitor while the app is open or the device is
  charging.
- Auto-snaps are queued for review, never auto-sent.

## Milestones

- **M0: Scaffold.** Flutter project, CI (analyze + test), permissions plumbing, settings skeleton.
- **M1: Snap core.** Big button, PCM capture, LAeq/LAmax, GPS, timestamp, optional 10 s M4A clip,
  persisted locally, history list. *Usable offline, produces real data.*
- **M2: Flight match.** ADS-B clients + scoring + review screen with alternates and confidence.
- **M3: Complaint email.** Profile (name/address/postcode/email), recipient sets per airport,
  form-letter template with tokens, attachment, mail-composer handoff, mark-as-sent.
- **M4: Evidence quality.** LAeq/LAmax presentation, CSV export, BCC-to-group.
- **M5: Beta hardening.** Offline queue + OpenSky 1-hour back-fill, permission edge cases, battery,
  error states, TestFlight/APK distribution to the beta group.
- **M6: Autonomous listening.** YAMNet, foreground service, thresholds, review queue.
- **M7: Store release.** Privacy policy, data-safety forms, iOS usage strings, icons, screenshots.

## Key packages
`record` (raw PCM) · `geolocator` · `permission_handler` · `sqflite` · `flutter_riverpod` (2.x) ·
`http` · `flutter_email_sender` · `url_launcher` (mailto fallback) · `just_audio` (clip preview) ·
`device_info_plus` + `package_info_plus` (handset/OS stamped into every letter) · `path_provider` ·
`share_plus` (export fallback) · `maplibre_gl` (vector basemap; `flutter_map` alone does raster) ·
`tflite_flutter` (M6) · `flutter_foreground_task` (M6)

## Known risks
1. **iOS mail composer needs a configured Mail account.** No account, no composer. Fallback:
   `mailto:` via `url_launcher` (loses the attachment) plus "export and attach manually".
2. **ADS-B coverage gaps.** Low, military and non-ADS-B traffic simply will not appear. The UI must
   handle "no candidate" gracefully rather than guessing.
3. **adsb.lol may introduce API keys** (their docs flag it). Keep clients behind an interface so
   sources are swappable; OpenSky is the keyed fallback that already works.
4. **Ambient speech in clips.** Recording bystanders is the one genuine privacy risk here. Clip
   defaults to off, user previews before sending, clip deletable from history.
5. **OpenFreeMap could fold.** It is donation-funded with no contract behind it. The tiles are
   swappable at one constant (`Endpoints.mapStyleUrl`), and the fallback is Protomaps: a single
   `.pmtiles` file, hostable anywhere or bundled in the APK for zero outbound calls. Every map
   already degrades to a drawn-on-paper version when the tiles do not arrive, so the failure mode is
   a duller picture rather than a broken feature.
6. **An absolute dB figure invites an argument about the handset.** Mitigated by leading on the
   rise above background rather than the absolute level, and by stating the method plainly, not by
   apologising for the measurement, which invites the recipient to dismiss the complaint entirely.

## Sources
- https://github.com/adsblol/api
- https://github.com/airplanes-live/api-archive
- https://openskynetwork.github.io/opensky-api/rest.html
- https://fr24api.flightradar24.com/docs/faq (enterprise only, ruled out)
- https://pub.dev/packages/flutter_email_sender
