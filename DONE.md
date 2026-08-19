# Done

- 2026-08-19 — Repo initialised; stack and architecture decided; PLAN.md / TODO.md / CLAUDE.md /
  LESSONS_LEARNT.md written.

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
31 tests green in one run, `flutter analyze` clean:
`a_weighting_test` (5) · `noise_analyzer_test` (6) · `flight_matcher_test` (6) ·
`complaint_template_test` (9) · `ring_buffer_test` (5).
