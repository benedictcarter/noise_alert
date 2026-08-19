# TODO

See [PLAN.md](PLAN.md) for the full design and rationale. Completed items move to [DONE.md](DONE.md).

## Blocked on Ben
- [ ] Confirm airport + recipient addresses for the default recipient set (flight-watch group, airport
      noise team). Currently defaults to `benedict.carter@gmail.com` only.
- [ ] **UAT:** run the app on a handset, snap a real overflight, check the letter reads right.
- [ ] Decide whether a real SPL meter can be borrowed for a one-off calibration (offset per handset).
      Until then every letter carries the "NOT been calibrated" paragraph and leads on excess over
      ambient, which is offset-independent.
- [ ] **iOS is parked** (2026-08-19, Ben: no Mac and no access to one). Windows cannot build or sign
      an iOS app. When iOS matters, the route is **cloud macOS CI** — Codemagic (free tier, built for
      Flutter, does signing + TestFlight upload) or GitHub Actions `macos-latest`. No Mac needed.
      A macOS VM on non-Apple hardware breaks Apple's licence, so the release path will not rest on it.
      Also needs the Apple Developer Program (£79/$99 a year) before TestFlight — not yet.

## Next up
- [ ] First on-device smoke test on Android: permissions, live meter, snap → review → mail composer
      end to end. **No device or AVD available yet** — `flutter devices` shows only Windows and Edge,
      neither of which can run this app (`record`, `geolocator`, `sqflite` are mobile-only here).
      Needs either Ben's phone over USB with developer mode on, or an AVD built from a *Google APIs*
      system image (a bare AOSP image has no mail app, so the composer handoff cannot be tested).
- [ ] CI: `flutter analyze` + `flutter test` on push (GitHub Actions).
- [ ] Permission denial / "denied forever" UI states — the services return failures cleanly but the
      screens do not yet offer "open settings".
- [ ] `permission_handler` and `share_plus` are declared in `pubspec.yaml` but unused — either wire
      them up (M4 export) or drop them before release.

## M4 — Evidence quality
- [ ] Calibration flow beyond the raw offset field (guided side-by-side reading against an SPL meter)
- [ ] CSV export of all snaps; share sheet
- [ ] Multiple named recipient sets (the model supports a list; the UI edits only the first)
- [ ] Re-open / resend a sent complaint from history

## M5 — Beta hardening
- [ ] Offline queue: snap now, match later (OpenSky 1-hour retro back-fill is written but untested
      against the live service — needs credentials)
- [ ] Battery, long-session and interruption cases (call arrives mid-record, headset plugged in)
- [ ] Signed APK for the beta group; TestFlight once a Mac/CI runner exists

## M6 — Autonomous listening (Phase 2)
- [ ] YAMNet TFLite integration, aircraft-class scoring
- [ ] Dual-gate trigger (class score + LAeq floor), tunable thresholds
- [ ] Android foreground service (`FOREGROUND_SERVICE_MICROPHONE`)
- [ ] iOS background audio session; document store-review fallback
- [ ] Auto-snap review queue (never auto-send)

## M7 — Store release
- [ ] Privacy policy, data-safety / privacy-manifest forms
- [ ] App icons, screenshots, store copy
- [ ] Android 14+ foreground-service declaration if M6 ships
