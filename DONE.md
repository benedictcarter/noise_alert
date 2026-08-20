# Done

- 2026-08-19 — Repo initialised; stack and architecture decided; PLAN.md / TODO.md / CLAUDE.md /
  LESSONS_LEARNT.md written.


## Post-roll fix, level chart, and Flightpath Watch branding (2026-08-20)
- **Endless post-roll fixed.** `captureEventWindow` waited for a *sample count* (20 s x 48 kHz), so
  any handset delivering below 48 kHz stretched the wait in proportion and a stalled stream never
  ended at all. It now waits on a wall clock, measures the rate actually delivered
  (`totalWritten / elapsed`) and carries that rate through the window length, the A-weighting
  design, the analysis and the WAV header.
- **STOP & SAVE shows a countdown**, and a red line appears on the snap screen when the delivered
  sample rate is more than 2% off the requested one.
- **dB-over-time chart.** One `LevelChartPainter` drives the live meter, the review screen and an
  off-screen PNG (`ChartImageService`) attached to every complaint ahead of the audio clip. The
  trace is stored in the metrics row, because the audio usually is not kept. Fixed 30-110 dB axis,
  so a quiet event and a loud one cannot look alike, and the UNCALIBRATED caveat travels in the
  caption.
- **Renamed to Flightpath Watch Alert** — app label, in-app title, iOS display name and the letter's
  "measured with" line. The Dart package and the repo stay `noise_alert`.
- **New launcher icon**: the real plane-and-swoosh, lifted out of the FLIGHTPATH WATCH logo by
  `scripts/make_icons.py` and exported to every Android density plus an adaptive (and monochrome)
  icon and the full iOS set. The source is a 191x72 screenshot, so the mark is 94 px wide; the
  script recovers it by resampling ink *coverage* as a soft alpha rather than thresholding first,
  which is what keeps the sub-pixel edge information a threshold would throw away. Tilted 26 deg in
  the square tiles, because a 3:1 mark laid flat in a square is a stripe.
- **Widget is now a 2x1 pill** with the mark over "FPW SNAP", instead of a bare 1x1 circle.
- **Default Cc is `info@flightpathwatch.co.uk`**, with a one-time `recipientSeed` pass so installs
  that predate the address pick it up exactly once and a user who deletes it does not get it back.
- 72 tests, `flutter analyze` clean.

## M0 — Scaffold (2026-08-19)
- Flutter 3.47 project for iOS + Android only; toolchain installed (Flutter SDK, Android SDK,
  licences accepted, two Android devices visible to `flutter devices`).
- Riverpod 2.x wiring, strict lints, `flutter analyze` → **No issues found!**
- Dropped freezed / json_serializable / drift / dio in favour of hand-written models, `sqflite` and
  `package:http` — the code-gen chain would not resolve against the SDK's analyzer.
- Permissions declared: `RECORD_AUDIO`, `ACCESS_FINE_LOCATION`, `ACCESS_COARSE_LOCATION`, `INTERNET`
  plus `SENDTO`/`VIEW` queries on Android; `NSMicrophoneUsageDescription` and
  `NSLocationWhenInUseUsageDescription` on iOS.

## M1 — Snap core (2026-08-19)
- Raw PCM capture at **48 kHz** mono via `record`, `AndroidAudioSource.unprocessed`, AGC / echo
  cancellation / noise suppression off, Bluetooth mic routing blocked on both platforms.
- IEC 61672-1 A-weighting: three bilinear-transformed biquads normalised to 0 dB at 1 kHz.
- `NoiseAnalyzer`: LAeq, LAmax (fast, 125 ms), ambient LA90 from pre-roll only, and the loudest
  10 s window found by prefix-sum energy search.
- 30 s pre-roll ring buffer + 20 s after the press, so the event is captured despite reaction time.
- GPS fix with accuracy gating and a stale-fix guard.
- WAV clip writer that slices only the peak window.
- `sqflite` schema (snaps, profile, settings) with hand-written SQL.
- Big-button snap screen with live dB(A) meter and clipping indicator; history list with
  swipe-to-delete.

## M2 — Flight match (2026-08-19)
- `AdsbSource` interface; `Tar1090Source` covering **adsb.lol** and **airplanes.live** (free, no key).
- `OpenSkySource` with OAuth2 client-credentials for the 1-hour retrospective back-fill.
- FlightRadar24 ruled out — enterprise-only, no free tier.
- Propagation-delay-aware matcher: searches T−45 s … T+10 s, scores by closest approach (slant range,
  elevation angle, altitude, time alignment), returns confidence plus the runner-up list.
- Review screen: candidates as a single radio group with an explicit "None of these / unidentified"
  option, pre-ticked only when confidence clears the pre-select bar, plus "look up again".

## M3 — Complaint email (2026-08-19)
- Device-only profile store (name, address, postcode, email, phone).
- Recipient set (to / cc / bcc) with an optional BCC-to-self so the user keeps their own record.
- Form-letter template with ~30 tokens, live preview, editable subject and body, reset to defaults.
- `flutter_email_sender` handoff with the clip attached, falling back to `mailto:` when no composer
  is configured; snap marked sent only if the composer actually opened.
- Clip preview player on the review screen — play the snip *before* choosing to attach it.

## Product invariants locked by tests (2026-08-19)
- **Never name a flight the user has not confirmed.** The template reads `snap.confirmedCandidate`
  only; an unconfirmed candidate produces a truthful "aircraft not identified" paragraph.
- **Never present uncalibrated dB as absolute.** Every letter states handset model, OS version,
  sample rate, A-weighting and calibration status, and leads on excess over ambient, which is
  independent of the calibration offset.

## Tests (2026-08-19)
51 tests green in one run, `flutter analyze` clean:
`a_weighting_test` (5) · `noise_analyzer_test` (6) · `flight_matcher_test` (6) ·
`complaint_template_test` (9) · `ring_buffer_test` (5) · `database_test` (8, real SQLite via
`sqflite_common_ffi`) · `adsb_parsing_test` (12, fixture bodies through the real JSON path).

Added value equality to `ComplainantProfile`, `RecipientSet` and `AppSettings` along the way —
`StateNotifier` only notifies listeners when `state != newState`, so without it every keystroke in
the settings form rebuilt every consumer.

## First Android build (2026-08-19)
- Release APK builds on Windows: 52.7 MB, debug-signed via Flutter's template `release` config, so
  no keystore is needed until store submission.
- Dropped `permission_handler` and `share_plus` — declared but never imported, and the former broke
  the build by demanding an SDK platform hash (`android-37`) that no longer exists.
- `kotlin.incremental=false` in `android/gradle.properties`; Kotlin's incremental caches fail to
  unmap on Windows and killed two builds on different modules.
- APK sideloaded to the test handset over MTP — the LG G7 ThinQ exposes no ADB interface, so
  `flutter run` and hot reload are unavailable on it.

## Widget, GPS honesty, stop-and-save, mail attachments (2026-08-20)
All four from Ben's first round of on-device use.

- **1×1 home-screen widget.** `SnapWidgetProvider` + `snap_widget.xml`; the tap launches
  `MainActivity` with `snap_now`, and Dart picks it up over `MethodChannel('noise_alert/quick_snap')`
  by two paths — a pull at startup for a cold launch, a push via `onNewIntent` while running.
  Handling only the first is the classic bug: the widget then works once per app lifetime.
- **GPS read 0, 0.** Root cause was two-fold — `capture()` did `fix?.latitude ?? 0`, and the app
  never showed that location was off device-wide (which it was). Latitude/longitude are now nullable
  end to end, schema v2 migrates existing `0, 0` rows to NULL, the permission is requested when the
  snap screen opens rather than mid-capture, and a banner offers "Turn on" or "Settings" depending
  on which of the four states the device is actually in. `current()` falls back from a high-accuracy
  fix to a coarse one instead of failing outright.
- **STOP & SAVE.** Waiting out the full 20 s post-roll was annoying. `cutCaptureShort()` ends the
  window early and keeps whatever was recorded; the GPS fetch now runs in parallel with the post-roll
  so a press during the locating stage is not swallowed.
- **Audio attachments.** Clips are written to `getApplicationSupportDirectory()`, the only path
  `flutter_email_sender`'s FileProvider actually declares, and the composer is retried without
  attachments before falling back to `mailto:` (see LESSONS_LEARNT).
- **Latent bug found on the way:** a snap taken before the ring buffer had filled averaged
  unrecorded digital silence into the background level. `ambientLa90Db` is now nullable and the
  letter and review screen say "not measured" rather than quoting an inflated rise.

62 tests, `flutter analyze` clean.
