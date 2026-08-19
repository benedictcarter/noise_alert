# TODO

See [PLAN.md](PLAN.md) for the full design and rationale.

## Blocked on Ben
- [ ] Confirm airport + recipient addresses for the default recipient set (flight-watch group, airport noise team)
- [ ] Confirm home/monitoring location and typical overflight altitude (tunes the match scoring)
- [ ] Decide: is a real SPL meter available to calibrate against?
- [ ] Confirm audio clip default (off recommended) and clip length (10 s recommended)

## M0 — Scaffold
- [ ] `flutter create` with org id, iOS + Android only
- [ ] Riverpod + freezed + drift + dio wiring, lints, `flutter analyze` clean
- [ ] CI: analyze + unit tests
- [ ] Permission plumbing (mic, location, notifications) with denial/limited states

## M1 — Snap core
- [ ] Raw PCM capture at 16 kHz mono, AGC/voice-processing disabled
- [ ] A-weighting biquad cascade + LAeq + LAmax(125 ms) — unit tested against synthetic tones
- [ ] GPS fix with accuracy gating and a stale-fix guard
- [ ] Optional M4A clip writer (10 s ring buffer so we capture pre-roll)
- [ ] drift schema: snaps, metrics, clips
- [ ] Big-button screen with live dB meter; history list

## M2 — Flight match
- [ ] `AdsbSource` interface; adsb.lol + airplanes.live clients
- [ ] OpenSky OAuth2 client-credentials client with credit budgeting
- [ ] Propagation-delay-aware candidate scoring (slant range, elevation angle, altitude, time)
- [ ] Review screen: best match, alternates, confidence, "unidentified aircraft"
- [ ] Unit tests with recorded fixture responses

## M3 — Complaint email
- [ ] Profile store (name, address, postcode, email) — device-only
- [ ] Recipient sets (to/cc/bcc) per airport, editable
- [ ] Form-letter template with tokens + live preview
- [ ] `flutter_email_sender` handoff with attachment; `mailto:` fallback
- [ ] Mark-as-sent + resend from history

## M4 — Evidence quality
- [ ] Calibration screen (offset per device) + `calibrated` flag on every snap
- [ ] CSV export of all snaps; share sheet
- [ ] BCC-to-group option

## M5 — Beta hardening
- [ ] Offline queue + OpenSky 1-hour retro back-fill
- [ ] Battery and permission edge cases; error states
- [ ] TestFlight + signed APK for the beta group

## M6 — Autonomous listening (Phase 2)
- [ ] YAMNet TFLite integration, aircraft-class scoring
- [ ] Dual-gate trigger (class score + LAeq floor), tunable thresholds
- [ ] Android foreground service (`FOREGROUND_SERVICE_MICROPHONE`)
- [ ] iOS background audio session; document store-review fallback
- [ ] Auto-snap review queue (never auto-send)

## M7 — Store release
- [ ] Privacy policy, data-safety / privacy-manifest forms
- [ ] iOS usage strings, icons, screenshots, store copy
