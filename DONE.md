# Done

- 2026-08-19: Repo initialised; stack and architecture decided; PLAN.md / TODO.md / CLAUDE.md /
  LESSONS_LEARNT.md written.


## The map, and the track the aircraft actually flew (2026-08-21)
The complaint could quote a decibel figure and a callsign. It could not show the flight going over
the house, which is the one piece of evidence a recipient cannot argue away by disputing a phone's
microphone.

- **Basemap is OpenFreeMap** (`https://tiles.openfreemap.org/styles/liberty`) through `maplibre_gl`:
  real OSM vector tiles, no API key, no registration, no request limit, no cookies. The attribution
  line is the whole of what it asks in return, so it lives in `FlightMapPanel` (a map cannot be put
  on a screen without it) and is *painted into* the emailed PNG, because a line under a widget does
  not travel with an image into somebody's inbox. This is the app's third and last outbound call,
  and `CLAUDE.md` now says so.
- **Tracks come free.** The matcher was already polling adsb.lol every three seconds; the lookup
  service now keeps each aircraft's positions and publishes them on a stream, so the live map is a
  *view of that cache* rather than a second source of traffic to a donated feed.
- **No positions table.** The track serialises into the existing `snaps.match_json`, so there was no
  migration; a row written before the map existed decodes with an empty track and is still drawable
  as a single dot. Capped at `MatchConfig.maxTrackPoints` (60) by `decimateTrack`, keeping both ends,
  because `allSnaps()` decodes every match on every history load.
- **The picture is drawn, not screenshotted.** `takeSnapshot` does not photograph the map on screen:
  both platforms hand the job to an independent `MapSnapshotter` given only a style URL and a camera,
  so every runtime layer is absent from the result. The basemap comes from a hidden one-pixel map
  (`MapSnapshotHost`) and everything else (tracks, aeroplanes, the house, scale bar, caption,
  attribution) is painted in Dart over the top through `MercatorView`, which reproduces MapLibre's
  own projection. See LESSONS_LEARNT.
- **Live map on the record screen, event map on review.** The review map highlights whichever
  candidate the radio buttons currently point at, so "which of these four was it?" can be answered by
  looking at which line went over the house. Neither is interactive: both sit in scrolling lists, and
  a map that accepts drags eats the scroll.
- **Nothing blocks a complaint.** No fix → a plain panel saying so and no map attached, with no
  mention of one in the letter. No tiles → the geometry is drawn on pale paper, still to scale, and
  the letter still describes it. No aircraft → a map of the recording location saying in as many
  words that none was identified. A render that fails at any point returns null and the letter goes
  without it.
- 24 map tests and 4 template tests added; 147 pass.

## Sign the release properly, before anyone installs it (2026-08-21)
v1.0.0 was tagged and about to be emailed out still carrying Flutter's scaffolded
`signingConfig = signingConfigs.getByName("debug")`. Debug-signed builds install and run, so nothing
had ever complained, but Android refuses an update across a signature change, so every one of those
installs would have had to be uninstalled (losing the user's recordings) before a properly signed
version could reach them.

- **A real key**: 4096-bit RSA, 10,000 days, `CN=Flightpath Watch`, in
  `android/flightpath-watch-release.jks` with its password in `android/key.properties`. Both are
  gitignored and both are copied to `S:/code/_secrets/noise_alert/`: lose them and the app can never
  be updated again.
- **The Gradle config falls back to the debug key when `key.properties` is missing**, so a fresh
  clone and any CI runner still build. Only a machine holding the key produces a distributable APK.
- Verified with `apksigner verify --print-certs`: one signer, v2 scheme, the right DN.
- Released as **v1.0.1** rather than re-cutting v1.0.0, because that tag was already pushed and
  moving a published tag is a force-push.

## The launch screen, and the app is called Flightpath Watch Report (2026-08-21)
Opening the app flashed a plain white window while the process started and the database opened.
Nothing was broken: `main()` awaits `AppDatabase.open()` before `runApp`, but a blank white screen
is indistinguishable from an app that has failed to start, which is exactly the wrong first second
for this audience.

- **The launch window now carries the wordmark.** `drawable-*/splash_wordmark.png` is the plane from
  the launcher icon over FLIGHTPATH / WATCH / REPORT, composed once at 4x by
  `scripts/make_splash.py` and downsampled per density so the letterforms match across handsets.
  The native splash cannot render text, so it has to be baked into a bitmap.
- **White in dark mode too.** Both `launch_background.xml` variants pin `@android:color/white`
  rather than `?android:colorBackground`. The artwork is black ink on a transparent ground, so a
  dark-mode handset would otherwise have shown black on black.
- **Android 12+ gets `values-v31`.** From API 31 the OS draws its own splash and ignores
  `windowBackground` entirely, so that path sets `windowSplashScreenBackground` white and the
  launcher icon as the animated icon. The wordmark cannot go there: the animated icon is masked to
  a circle.
- **Renamed to Flightpath Watch Report** in `strings.xml`, `MaterialApp.title`, the welcome screen,
  the letter's provenance line and `pubspec.yaml`. The Dart package, the repo and the Android
  application id stay `noise_alert`; renaming those buys nothing and breaks the installed build.
- **The stop buttons say what they lead to.** DISCARD / REVIEW & SEND / JUST SEND, two lines each on
  the last two, because both of them end in a sent complaint and the single words REVIEW and SEND
  read as alternatives rather than as two routes to the same place.

## Make it simple enough for someone who is not technical (2026-08-20)
The audience is largely pensioners, opening the app because a jet has just gone over. Every screen
had to stop reading as a list of things that might be wrong with their phone.

- **A welcome screen.** `WelcomeScreen` replaces the whole app (not a dialog over it) until there
  is a name and a postcode. It is rendered instead of `HomeShell` precisely so `SnapScreen` is never
  built, and therefore never asks for the microphone, before the user has read what the app is for.
- **Name and postcode are the only mandatory fields.** House number, street, town and phone are
  optional. `ComplainantProfile.isComplete` is the one definition of enough.
- **The email address field is gone entirely.** It fed exactly two things: a `bccSelf` switch and an
  `{email}` sign-off token. Both were redundant: the letter is sent from the user's own account, so
  the reply address is already on it. Anyone wanting a copy puts themselves in Bcc. The `{email}`
  token survives resolving to an empty string, because `_substitute` leaves an *unknown* token
  standing as literal text and a user who had edited their letter would otherwise post "{email}".
- **Postcode lookup.** `PostcodeService` hits postcodes.io (free, no key, no quota, ONS open data)
  and fills in the town. Only on a button press, and a failure says "it does not matter, type it
  yourself" rather than blocking anything.
- **Settings split into three screens.** A menu, not a form: My details / The complaint email /
  Recordings and flights. The first row shows the user's details in place, in red if they are still
  missing. `MyDetailsForm` is shared with the welcome screen so there is one form, not two.
- **The microphone refusal has a UI at last.** A refused permission is no longer an error banner; the
  record button itself becomes an amber TURN ON THE MIC, which explains why the microphone is needed,
  asks again, and (if the phone has stopped showing its own dialog, which Android does after two
  refusals) offers the app's settings page. Retryable for ever: nothing dead-ends.
- **String sweep.** "snap" is now "recording" throughout; LAeq/LA90/LAmax carry plain-English labels
  with the term in brackets; the review screen leads on the rise ("23 dB louder than the quiet
  street") rather than an absolute figure; and the "microphone hit its limit" and "no background"
  notes were rewritten so neither reads as the user's fault.

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
- **Renamed to Flightpath Watch Report**: app label, in-app title, iOS display name and the letter's
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

## M0: Scaffold (2026-08-19)
- Flutter 3.47 project for iOS + Android only; toolchain installed (Flutter SDK, Android SDK,
  licences accepted, two Android devices visible to `flutter devices`).
- Riverpod 2.x wiring, strict lints, `flutter analyze` → **No issues found!**
- Dropped freezed / json_serializable / drift / dio in favour of hand-written models, `sqflite` and
  `package:http`: the code-gen chain would not resolve against the SDK's analyzer.
- Permissions declared: `RECORD_AUDIO`, `ACCESS_FINE_LOCATION`, `ACCESS_COARSE_LOCATION`, `INTERNET`
  plus `SENDTO`/`VIEW` queries on Android; `NSMicrophoneUsageDescription` and
  `NSLocationWhenInUseUsageDescription` on iOS.

## M1: Snap core (2026-08-19)
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

## M2: Flight match (2026-08-19)
- `AdsbSource` interface; `Tar1090Source` covering **adsb.lol** and **airplanes.live** (free, no key).
- `OpenSkySource` with OAuth2 client-credentials for the 1-hour retrospective back-fill.
- FlightRadar24 ruled out: enterprise-only, no free tier.
- Propagation-delay-aware matcher: searches T-45 s … T+10 s, scores by closest approach (slant range,
  elevation angle, altitude, time alignment), returns confidence plus the runner-up list.
- Review screen: candidates as a single radio group with an explicit "None of these / unidentified"
  option, pre-ticked only when confidence clears the pre-select bar, plus "look up again".

## M3: Complaint email (2026-08-19)
- Device-only profile store (name, address, postcode, email, phone).
- Recipient set (to / cc / bcc) with an optional BCC-to-self so the user keeps their own record.
- Form-letter template with ~30 tokens, live preview, editable subject and body, reset to defaults.
- `flutter_email_sender` handoff with the clip attached, falling back to `mailto:` when no composer
  is configured; snap marked sent only if the composer actually opened.
- Clip preview player on the review screen: play the snip *before* choosing to attach it.

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

Added value equality to `ComplainantProfile`, `RecipientSet` and `AppSettings` along the way:
`StateNotifier` only notifies listeners when `state != newState`, so without it every keystroke in
the settings form rebuilt every consumer.

## First Android build (2026-08-19)
- Release APK builds on Windows: 52.7 MB, debug-signed via Flutter's template `release` config, so
  no keystore is needed until store submission.
- Dropped `permission_handler` and `share_plus`: declared but never imported, and the former broke
  the build by demanding an SDK platform hash (`android-37`) that no longer exists.
- `kotlin.incremental=false` in `android/gradle.properties`; Kotlin's incremental caches fail to
  unmap on Windows and killed two builds on different modules.
- APK sideloaded to the test handset over MTP: the LG G7 ThinQ exposes no ADB interface, so
  `flutter run` and hot reload are unavailable on it.

## Widget, GPS honesty, stop-and-save, mail attachments (2026-08-20)
All four from Ben's first round of on-device use.

- **1×1 home-screen widget.** `SnapWidgetProvider` + `snap_widget.xml`; the tap launches
  `MainActivity` with `snap_now`, and Dart picks it up over `MethodChannel('noise_alert/quick_snap')`
  by two paths: a pull at startup for a cold launch, a push via `onNewIntent` while running.
  Handling only the first is the classic bug: the widget then works once per app lifetime.
- **GPS read 0, 0.** Root cause was two-fold: `capture()` did `fix?.latitude ?? 0`, and the app
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
  buffer (`EventWindow.ambient`) so the rise above background (the one figure an uncalibrated
  handset cannot distort) survives.
- **Nothing stops the recording but STOP.** The fixed 20 s post-roll is gone; the person holding the
  phone is the only one who knows when the aircraft has gone. The button counts *up*, and a
  5-minute cap (`AudioConfig.maxEventSeconds`) exists purely as a memory backstop.
- **A clip is always saved**, on the device only. The keep-or-not switch is gone from the snap
  screen and from settings; the only remaining question is whether to *attach* it.
- **SNAP is now RECORD**: the button, the nav bar tab, the progress text and the home-screen
  widget, which went back to a 1x1 red circle: the plane mark at 22 dp over "REC". The 2x1 pill
  existed to hold a whole word, and one cell is enough once the word is three letters. Now
  resizable in both directions, so the mark can be stretched out again on a roomier home screen.
- **The user can drag the peak marker.** Tapping or dragging on the review chart marks the worst
  moment as *experienced*: closest approach, or whatever actually made the noise unbearable. It is
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
- **Green, not red.** The record button and the home-screen widget are green: red is the colour
  every other app uses for "this deletes something".
- **The meter and the chart are half-lit when not recording**, so what is being logged is obvious
  from arm's length.
- **A past snap goes straight to the historical source.** A live feed only reports aircraft in the
  sky *now*, so for anything older than the track cache the live query could only ever return
  "nothing found", slowly, and without saying why. It now says exactly why: live feeds cannot see
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
  was, so a recipient (or Ben, before he sends it) can see in three lines whether the figures
  are plausible. Plain text, because the composer is handed `isHTML: false` and the mailto:
  fallback could not carry markup anyway; an upper-case heading and labelled lines survive every
  mail client, which bold characters and HTML do not. The calibration caveat sits on the same line
  as the decibel figure, since the block is meant to be read on its own.
- 103 tests green (was 98).


## Calibration removed; the letter leads on peak vs background (2026-08-20)
- **The whole calibration concept is gone.** No settings section, no offset field, no "I have
  calibrated this handset" switch, no `calibrated` / `calibrationOffsetDb` on `AcousticMetrics` or
  `AppSettings`, no uncalibrated banner on the main screen, no caveat on the review screen, no
  UNCALIBRATED wording on the chart caption, no apologetic paragraph in the letter. The full-scale
  reference is fixed at 120 dB SPL in `LevelReference` and never varies. Rows written by earlier
  builds still carry the two dropped JSON keys; `AcousticMetrics.fromJson` reads past them so no
  logged event becomes unopenable.
- **The background is now the LA90 of the recording itself**, not a mean and not the true minimum.
  A mean is dragged up by the aircraft; the true minimum is one 125 ms block, so a single dropout
  would put the floor twenty decibels low and inflate every rise. The tenth percentile is the
  standard definition of "background noise level" and is what the minimum is trying to be.
- **Record-on-open no longer costs the background figure.** The pre-roll buffer is now only a
  fallback for a recording stopped inside `NoiseAnalyzer.minAmbientSeconds` (3 s); anything longer
  supplies its own quiet street. This closes the first "Record-on-open follow-ups" item.
- **The letter was rewritten around the rise.** AT A GLANCE now reads
  `Loudest: 40.3 dB above the background, 78.4 dB(A) at its peak, against 38.1 dB(A) when it was
  quiet`; the measurement block leads with the rise, then LAmax, then the background labelled
  "quietest 10% of the recording (LA90)", then LAeq labelled as the average over the whole
  recording. The method note states handset, OS, sample rate and weighting, then that the peak and
  the background were read by one microphone in one recording, so the gap is like-for-like.
- CLAUDE.md's "never present uncalibrated dB" non-negotiable replaced with the rise-over-background
  rule; PLAN.md's calibration screen and M4 calibration item removed.


## 83 MB to 29 MB, and a hunt for code that nothing calls (2026-08-22)
Two questions, and they turned out to have very different answers: the install was fat for a reason
that had nothing to do with the source, and the source had almost nothing in it to cut.

**The install: 83.2 MB to 29.2 MB, a 65% cut.** Unzipping the APK and summing entries by directory
put 93% of it in `lib/`, as three copies of the same native libraries: `lib/x86_64` 31.4 MB (an
emulator ABI the app will never run on), `lib/arm64-v8a` 29.6 MB (what the G7 ThinQ actually uses)
and `lib/armeabi-v7a` 24.2 MB. `classes.dex` was 2.5 MB and every asset together under 0.3 MB. The
Dart source was never the problem.

- **`--split-per-abi` is the fix**, and `--target-platform android-arm64` is the trap that looks like
  it. The latter only controls what the Flutter tool compiles, so it drops the other ABIs of
  `libflutter.so` and `libapp.so` and leaves every plugin's alone: an "arm64-only" build still
  carried `libmaplibre.so` for x86_64 and armeabi-v7a and came to 47.7 MB. Written up in
  LESSONS_LEARNT.
- **`--split-debug-info` is nearly a megabyte for free**, taking `libapp.so` from 6.50 MB to 5.56 MB.
  `--obfuscate` was deliberately not taken with it: enum names are persisted to SQLite as strings
  through `.name`, and that is not a thing to gamble on for a build that is already stripped.
- **R8 was measured and does nothing.** `isMinifyEnabled` plus `isShrinkResources` produced an APK of
  30,645,603 bytes; so did the build without them. Identical to the byte, `classes.dex` 2.466 MB
  either way. The Android half of a Flutter app is a shell of plugin entry points that the keep
  rules protect. Reverted, and the reasoning is in README and LESSONS_LEARNT so it does not get
  proposed again.
- **The floor is the three libraries that are left**: `libflutter.so` 11.20 MB, `libmaplibre.so`
  10.35 MB, `libapp.so` 5.56 MB. Nothing short of dropping the map moves it, and the map is evidence.
- `scripts/build_release.sh` now carries both flags and the explanation, so the small build is the
  one you get by default rather than the one you have to remember.
- **The versionCode is now offset by ABI**: pubspec `+17` ships as 2017 on arm64. This is a one-way
  door. Android refuses a lower versionCode, so every future build for that handset has to be a
  split one or the update is rejected as a downgrade.

**The code: 58 lines, and that is genuinely all there was.** Every public top-level name, static
constant, field, method and getter was cross-referenced against the whole of `lib` and `test`. What
came out was fifteen members nothing ever called:

- `DeviceDescription.summary`, `AWeighting.cascade`, `PcmRingBuffer.addSamples`,
  `RecorderService.isCapturing`, `EventRecording.durationSeconds`
- `FlightLookupService.lastError` with its field and its three assignments, and
  `trackedAircraftCount`
- `LocationFix.isUsable`, `LocationService.ensurePermission`
- `CaptureProgress.isBusy`, `CaptureSendResult.needsReview`, and `SnapService.captureAndSend`, whose
  SEND rationale moved onto `sendCaptured`, the half the UI actually calls
- `FlightMatch.selected` and `withSelection`, dead because `Snap` carries the real selection
- `AdsbSource.supportsHistorical` and both of its overrides, declared and never once queried

Everything else survived a reason to exist. `flutter analyze` was already clean, an 8-line clone
detector found no repetition outside the frozen letter templates in `settings.dart` (which have to
be duplicated, byte for byte, or the settings upgrade path stops recognising them), all fourteen
dependencies are imported, and `Database.backfillableSnaps` was left alone because it is scaffolding
for the offline queue that TODO.md still lists. 150 tests green throughout.

**One thing the sweep turned up that was not about size.** `CLAUDE.md` said three outbound calls; the
code makes them to five services across six hosts. adsb.lol, airplanes.live, OpenSky (auth and api),
OpenFreeMap and postcodes.io. Nothing improper is happening, every one of them is coordinates or
tile numbers with no identifier attached, but a stated non-negotiable that undercounts is worse than
no statement at all. `CLAUDE.md` now lists all five.
