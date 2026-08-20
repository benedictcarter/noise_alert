# TODO

See [PLAN.md](PLAN.md) for the full design and rationale. Completed items move to [DONE.md](DONE.md).

## Blocked on Ben
- [ ] Confirm the airport noise-team address for the default recipient set. `To:` is still
      `benedict.carter@gmail.com` only; `Cc:` is now `info@flightpathwatch.co.uk`.
- [ ] **UAT:** run the app on a handset, record a real overflight (RECORD -> STOP), check the
      letter reads right. `noise_alert_b7.apk`.
- [ ] **iOS is parked** (2026-08-19, Ben: no Mac and no access to one). Windows cannot build or sign
      an iOS app. When iOS matters, the route is **cloud macOS CI** — Codemagic (free tier, built for
      Flutter, does signing + TestFlight upload) or GitHub Actions `macos-latest`. No Mac needed.
      A macOS VM on non-Apple hardware breaks Apple's licence, so the release path will not rest on it.
      Also needs the Apple Developer Program (£79/$99 a year) before TestFlight — not yet.

## Next up
- [ ] First on-device smoke test on Android: permissions, live meter, record → review → mail composer
      end to end. Release APK is **sideloaded to the LG G7 ThinQ** (`Download/noise_alert.apk`, over
      MTP — the phone exposes no ADB interface at all, see LESSONS_LEARNT; each build is copied
      under a new name, `_b2`/`_b3`/`_b4`, because deleting over MTP hangs). Install and run from a
      file manager; there is no `flutter run` hot reload on this handset, so each change means a
      rebuild and re-copy.
- [ ] CI: `flutter analyze` + `flutter test` on push (GitHub Actions).
- [ ] Microphone permission denial / "denied forever" UI state. Location is done (banner with
      "Turn on" / "Settings"); the mic still fails silently.
- [ ] iOS quick-snap: the Android home-screen widget has no iOS counterpart. `QuickSnapChannel`
      degrades to "no pending snap" on any platform without the channel, so nothing breaks — but a
      Control Centre / Lock Screen widget is the iOS equivalent when iOS is unparked.

## Record-until-stop follow-ups
- [ ] The 5-minute cap (`AudioConfig.maxEventSeconds`) is a hard stop with no warning before it —
      the recording just ends and is marked truncated. Decide whether the UI should say so as it
      approaches, or whether the cap should be raised.
- [ ] The marked worst moment is annotation only. It cannot re-cut the clip, because the full event
      audio is discarded after analysis — only the measured loudest 10 s is written to disk. If the
      mark should move the clip, the event WAV has to be kept until the review screen is done with
      it.

## Branding
- [ ] iOS launch screen and `LaunchImage` still carry the old placeholder artwork — regenerate when
      iOS is unparked.
- [ ] The icons are traced from a 191x72 screenshot of the logo
      (`assets/icon/flightpath_watch_logo.jpg`), which is all the resolution there is. If the
      original vector ever turns up, drop it in and re-run `scripts/make_icons.py`.

## M4 — Evidence quality
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

## Make it safe for someone who is not technical
Most users are pensioners. Every screen has to read as "press this, we will handle it", never as a
list of things that might be wrong with their phone.
- [ ] UAT the whole restructure on the handset: welcome form, mic refusal and recovery, the three
      settings screens, and a real overflight end to end.
- [ ] The postcode lookup fills in the *council area*, not the post town. For most addresses these
      are the same word; for some they are not. Watch whether that reads oddly in a real letter.
- [ ] The review screen still shows five acoustics rows. They are labelled in plain English now,
      but consider collapsing them behind a "show the detail" tap so the headline stands alone.

## Record-on-open follow-ups
- [ ] An auto-started recording is discarded on leaving the Record tab or backgrounding the app.
      Check on the handset that this does not eat a recording the user did mean to keep (e.g. they
      pull down the notification shade mid-flyover).
- [ ] OpenSky credentials are still not configured on Ben's handset, so no past snap can ever be
      looked up. Either walk through creating an account or accept that offline captures go out as
      "not identified".
