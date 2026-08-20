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

## Record until STOP, always-saved clips, and a draggable worst moment (2026-08-20)
- **The recording starts at the press.** RECORD opens the event; nothing before the press is in the
  graph, the LAeq or the clip. The 30 s ring buffer still runs, but now for one purpose only: a
  snapshot of the street taken at the instant of the press, carried to the analyzer as a *separate*
  buffer (`EventWindow.ambient`) so the rise above background — the one figure an uncalibrated
  handset cannot distort — survives.
- **Nothing stops the recording but STOP.** The fixed 20 s post-roll is gone; the person holding the
  phone is the only one who knows when the aircraft has gone. The button counts *up*, and a
  5-minute cap (`AudioConfig.maxEventSeconds`) exists purely as a memory backstop.
- **A clip is always saved**, on the device only. The keep-or-not switch is gone from the snap
  screen and from settings; the only remaining question is whether to *attach* it.
- **SNAP is now RECORD** — the button, the nav bar tab, the progress text and the home-screen
  widget, which went back to a 1x1 red circle: the plane mark at 22 dp over "REC". The 2x1 pill
  existed to hold a whole word, and one cell is enough once the word is three letters. Now
  resizable in both directions, so the mark can be stretched out again on a roomier home screen.
- **The user can drag the peak marker.** Tapping or dragging on the review chart marks the worst
  moment as *experienced* — closest approach, or whatever actually made the noise unbearable. It is
  stored as `Snap.markedPeakMs` (schema v3), drawn on the attached chart in a distinct colour, and
  written into the letter as `{markedPeakNote}` in the first person and explicitly *not* as a
  measurement.
- **The analyzer was rewritten to stream.** One pass, 25 ms block energies and a prefix sum over
  blocks, plus a `SampleSource` abstraction so the event stays `Int16List`. Without this a 5-minute
  recording needed ~345 MB of Float64 working arrays; it now needs ~29 MB in total.
- 86 tests green (was 72).

## Records on open, sends in one tap, and never loses a report (2026-08-20)
- **The app opens recording.** Reaching for the phone under a flight path is the press; the seconds
  spent finding a button are seconds of aircraft you do not get back. A recording nobody asked for
  is discarded the moment the user leaves the Record tab or backgrounds the app, so opening the app
  to change a setting does not leave a snap of the kitchen behind. The cost is the pre-roll, and
  with it the background level: the letter then quotes no rise above background, which understates
  the nuisance rather than overstating it.
- **STOP & SEND**, in darker blue beside STOP & SAVE. It names the closest ADS-B match, drafts the
  complaint and opens the mail app: open, stop-and-send, send. If the best candidate is further
  than 1 km horizontally it degrades to STOP & SAVE and shows the review screen, because that is
  the case where the matcher can genuinely pick the wrong aircraft.
- **A silent microphone no longer loses the complaint.** `AcousticMetrics.unmeasured` carries the
  reason instead of an exception, and every consumer asks `hasMeasurement` before printing a
  decibel figure. The letter says "Sound level: not measured", gives the reason, and stands on the
  address and the time.
- **Green, not red.** The record button and the home-screen widget are green — red is the colour
  every other app uses for "this deletes something".
- **The meter and the chart are half-lit when not recording**, so what is being logged is obvious
  from arm's length.
- **A past snap goes straight to the historical source.** A live feed only reports aircraft in the
  sky *now*, so for anything older than the track cache the live query could only ever return
  "nothing found" — slowly, and without saying why. It now says exactly why: live feeds cannot see
  into the past, and OpenSky history needs credentials.
- **Stored letters upgrade themselves** when they are an untouched older default, so a handset that
  saved its settings under b8 stops mailing a hard-coded table of zeroes. An edited letter is never
  touched.
- 98 tests green (was 86).

## The widget records again, and the letter can be scanned (2026-08-20)
- **Tapping the home-screen widget recorded nothing.** It started a capture that ended in the same
  millisecond, so the user was thrown to the review screen with "bad state" before they had let go
  of the phone. Two faults compounded: `awaitEventEnd()` looped on `isRunning`, so a stream that was
  not up when the event opened ended the capture at once; and `arm()`/`disarm()` overlapped, leaving
  the service convinced it was armed with the microphone off. Both are fixed, and a capture now
  starts the recorder itself if it finds it stopped.
- **AT A GLANCE.** The letter opens with when it happened, how loud it was and which aircraft it
  was, so a recipient -- or Ben, before he sends it -- can see in three lines whether the figures
  are plausible. Plain text, because the composer is handed `isHTML: false` and the mailto:
  fallback could not carry markup anyway; an upper-case heading and labelled lines survive every
  mail client, which bold characters and HTML do not. The calibration caveat sits on the same line
  as the decibel figure, since the block is meant to be read on its own.
- 103 tests green (was 98).
