# TODO

See [PLAN.md](PLAN.md) for the full design and rationale. Completed items move to [DONE.md](DONE.md).

## Blocked on Ben
- [ ] Confirm the airport noise-team address for the default recipient set. `To:` is still
      `benedict.carter@gmail.com` only; `Cc:` is now `info@flightpathwatch.co.uk`. Deliberate for
      the current beta (Ben + Flightpath Watch); see the security section for what changes when the
      group grows.
- [ ] **UAT:** run the app on a handset, record a real overflight (RECORD -> STOP), check the
      letter reads right. `flightpath-watch-b20-arm64.apk` (29.4 MB, arm64 only, versionCode 2020).
      b20 is the first build with backup switched off and the OpenSky secret in the keystore, so
      also worth checking: the app still starts, Settings still shows the OpenSky fields, and a
      secret typed in survives a force-stop and relaunch.
- [ ] **iOS is parked** (2026-08-19, Ben: no Mac and no access to one). Windows cannot build or sign
      an iOS app. When iOS matters, the route is **cloud macOS CI**: Codemagic (free tier, built for
      Flutter, does signing + TestFlight upload) or GitHub Actions `macos-latest`. No Mac needed.
      A macOS VM on non-Apple hardware breaks Apple's licence, so the release path will not rest on it.
      Also needs the Apple Developer Program (£79/$99 a year) before TestFlight, not yet.

## Security and privacy review (2026-08-22)
A full adversarial review, on the premise that the app had been built either maliciously or
incompetently. The good news first, because it bounds everything below: **no covert exfiltration and
no sixth endpoint.** Every network primitive in `lib/` is confined to `lib/net/`, there is no
WebView, no `Process`, no FFI, no socket, no telemetry package, no logging of PII, no SQL injection,
no world-readable storage and no path built from user or remote input. The architecture holds.

What did not hold was the layer underneath it: the app kept its promise about the *code* and the
platform broke it anyway, through backup. Those items are done; the rest are listed as found.

- [x] **Android backup shipped everything off-device.** `allowBackup` defaults to true, so the
      profile DB (name, address, phone, and a GPS fix per event), the recordings and the OpenSky
      secret all went to Google's servers and to any device-to-device transfer. Now
      `allowBackup="false"` plus `data_extraction_rules.xml`, which is the half that covers D2D.
- [x] **iOS did the same through iCloud.** The DB sits in Documents, which is backed up by default.
      Now excluded at launch via a new `noise_alert/backup` channel. **Compile-unverified:** iOS is
      parked and this was written on Windows, so the Swift wants a build before it is trusted.
- [x] **The OpenSky secret was cleartext in the settings row.** Moved to the platform keystore
      (`CredentialStore`), with a one-shot migration that scrubs the old copy out of SQLite on first
      launch. The client *id* stays in settings: it is an identifier, not a credential.

- [ ] **Default recipient: decided, and gated on the beta group growing** (Ben, 2026-08-22). `To:`
      stays `benedict.carter@gmail.com` and `Cc:` stays `info@flightpathwatch.co.uk` while the beta
      is exactly those two parties, both of whom are on the list knowingly. It stops being safe at
      user three: a stranger who never opens Settings would mail their name, address, coordinates
      and a recording of their home to a personal inbox without being shown where it went. **Do this
      before the first non-Ben install**, and do it by removal rather than replacement: no default
      `To:` at all, first send asks. Same trigger as the `seedGroupCc` item below.
- [ ] **`seedGroupCc` silently rewrites saved recipient lists** (`me/profile.dart`), adding a CC to
      an existing install on upgrade with no consent step, and `recipientSeed` is designed to be
      bumped again. Harmless while the only installs are Ben's; the same expand-the-beta trigger
      applies. Adding an address to a list the user has already reviewed should prompt once.
- [ ] **Home coordinates go out at 6 dp (~11 cm) every 3 s** to adsb.lol and airplanes.live
      (`net/live_adsb.dart`), and the OpenSky bounding box at 4 dp is symmetric so the centre
      averages straight back out (`net/opensky.dart`). The query radius is 25 nm: 2 dp returns the
      same aircraft. Round or jitter the *query* centre and keep the exact fix local for the
      geometry, which already uses `Observer` anyway.
- [ ] **`outbound_surface_test.dart` does not enforce what it claims.** Three holes, each of which
      a careless commit walks through green: it bans `package:http` but not `dart:io` `HttpClient`
      /`Socket`/`WebSocket` (and seven files outside `lib/net/` already import `dart:io` for file
      work); it greps for `https?://` literals, so `Uri.https('host', path)` is invisible; and the
      host-set assertion reads only `endpoints.dart` rather than all of `lib/net/`. Also worth
      noting in REVIEW.md that the guarantee stops at the Dart layer: the pubspec check is an
      8-word blocklist and nothing scans Gradle, CocoaPods or plugin native code.
- [ ] **Nothing runs that test before a release.** `scripts/build_release.sh` goes straight to
      `flutter build`, and there is no CI, so the tripwire CLAUDE.md describes as failing the build
      fails nothing. One line in the script, and the GitHub Actions item already in "Next up".
- [ ] **Deleted snaps leave their evidence behind.** `deleteSnap` removes the WAV and the row but
      not `{id}-map.png` or `{id}-level.png`, so a map centred on the user's home outlives the
      record they deleted (`snap/snap_service.dart`).
- [ ] **The mailto fallback joins recipients unencoded** (`letter/sender.dart`), so an address
      pasted with `?bcc=` in it breaks out of the address position into the query. Needs the user
      to paste a hostile "complaints address", and the primary `flutter_email_sender` path is
      unaffected, but per-recipient encoding is a one-liner.
- [ ] **Remote strings reach the letter with only `.trim()`.** Callsign, registration and type come
      from the feeds into the body and the subject (`letter/template.dart`), so spoofed ADS-B can
      put arbitrary text or newlines into a complaint the user signs. Not template injection:
      `_substitute` is single-pass and replacements are not re-scanned. Whitelist the characters.
- [ ] **The MapLibre style JSON decides the real hosts.** `endpoints.dart` pins the style URL, but
      the style itself names the tile, glyph and sprite hosts, fetched natively where no Dart test
      can see them. Either bundle the style with hosts pinned, or say plainly in CLAUDE.md that the
      map lane delegates its host list to OpenFreeMap.
- [ ] **`android:exported="true"` on MainActivity honours `snap_now` from anyone.** Any installed
      app can start it with the extra and trigger a capture (mic + fix). It is foreground-visible
      and an auto-capture is discarded unless the user acts, so impact is limited to nuisance. Fix
      is a non-exported trampoline activity for the widget's PendingIntent.
- [ ] **The release keystore and its plaintext password live inside the repo tree**
      (`android/key.properties`, `android/flightpath-watch-release.jks`). Verified never committed
      and gitignored, but one `git add -f` or one zip of the project folder from disclosure, and
      that pair signs updates that install silently over the real app. `_secrets/` already exists;
      move them and read from an absolute path.
- [ ] `endpoints.dart` cites `test/no_outbound_calls_outside_net_test.dart`, which does not exist.
      The real guard is `outbound_surface_test.dart`. One word, but it is the filename a reviewer
      greps for to check the promise is still enforced.

## Next up
- [ ] First on-device smoke test on Android: permissions, live meter, record → review → mail composer
      end to end. Release APK is **sideloaded to the LG G7 ThinQ** (`Download/noise_alert.apk`, over
      MTP: the phone exposes no ADB interface at all, see LESSONS_LEARNT; each build is copied
      under a new name, `_b2`/`_b3`/`_b4`, because deleting over MTP hangs). Install and run from a
      file manager; there is no `flutter run` hot reload on this handset, so each change means a
      rebuild and re-copy.
- [ ] CI: `flutter analyze` + `flutter test` on push (GitHub Actions).
- [ ] Re-run the dead-code sweep after the next feature lands. The scripts that found the
      fifteen unused members are throwaway but the method is not: cross-reference every public
      name against `lib` plus `test`, then check anything that only `test` mentions, because a
      member kept alive solely by its own test is the shape most dead code takes here.
- [ ] iOS quick-snap: the Android home-screen widget has no iOS counterpart. `QuickSnapChannel`
      degrades to "no pending snap" on any platform without the channel, so nothing breaks, but a
      Control Centre / Lock Screen widget is the iOS equivalent when iOS is unparked.

## Record-until-stop follow-ups
- [ ] The 5-minute cap (`AudioConfig.maxEventSeconds`) is a hard stop with no warning before it:
      the recording just ends and is marked truncated. Decide whether the UI should say so as it
      approaches, or whether the cap should be raised.
- [ ] The marked worst moment is annotation only. It cannot re-cut the clip, because the full event
      audio is discarded after analysis: only the measured loudest 10 s is written to disk. If the
      mark should move the clip, the event WAV has to be kept until the review screen is done with
      it.

## Branding
- [ ] iOS launch screen and `LaunchImage` still carry the old placeholder artwork: regenerate when
      iOS is unparked.
- [ ] The icons are traced from a 191x72 screenshot of the logo
      (`assets/icon/flightpath_watch_logo.jpg`), which is all the resolution there is. If the
      original vector ever turns up, drop it in and re-run `scripts/make_icons.py`.

## M4: Evidence quality
- [ ] CSV export of all snaps; share sheet
- [ ] Multiple named recipient sets (the model supports a list; the UI edits only the first)
- [ ] Re-open / resend a sent complaint from history

## M5: Beta hardening
- [ ] Offline queue: snap now, match later (OpenSky 1-hour retro back-fill is written but untested
      against the live service: needs credentials)
- [ ] Battery, long-session and interruption cases (call arrives mid-record, headset plugged in)
- [ ] Signed APK for the beta group; TestFlight once a Mac/CI runner exists

## M6: Autonomous listening (Phase 2)
- [ ] YAMNet TFLite integration, aircraft-class scoring
- [ ] Dual-gate trigger (class score + LAeq floor), tunable thresholds
- [ ] Android foreground service (`FOREGROUND_SERVICE_MICROPHONE`)
- [ ] iOS background audio session; document store-review fallback
- [ ] Auto-snap review queue (never auto-send)

## v2: Map and tracks
- [ ] UAT the map on the handset: live traffic on the record screen, the track on review, and the
      PNG as it arrives in a real inbox. Watch the first cold start especially: the tile style has
      to come down before anything is drawn.
- [ ] UAT the one-screen record layout: map on top taking the space the controls leave, the dB
      readout sitting on the trace below it, and nothing scrolling. Check the tall cases (location
      banner up, status line up and the three-button stop row all at once) and check the readout
      is still legible where the trace crosses it, now that it has no plate behind it and no unit
      beside it.
- [ ] Read one generated letter end to end after the dash purge. Every em dash, en dash and spaced
      double hyphen is gone from the strings, so the punctuation that replaced them wants a human
      eye on it once in the place it actually matters.
- [ ] UAT that the sound clip now arrives attached by default: send one without touching the review
      screen's toggle and confirm the WAV is on the mail.
- [ ] Decide whether to bundle a Protomaps London extract as the offline fallback. Only worth it if
      the "Map unavailable offline" panel turns out to be common in use.

## M7: Store release
- [ ] Privacy policy, data-safety / privacy-manifest forms
- [ ] App icons, screenshots, store copy
- [ ] Android 14+ foreground-service declaration if M6 ships

## Make it safe for someone who is not technical
Most users are pensioners. Every screen has to read as "press this, we will handle it", never as a
list of things that might be wrong with their phone.
- [ ] UAT the rest of the restructure on the handset: the welcome form on a fresh install, the
      three settings screens, and a real overflight end to end. (Mic refusal and recovery, and the
      three-button stop row, both passed on b13.)
- [ ] The review screen still shows five acoustics rows. They are labelled in plain English now,
      but consider collapsing them behind a "show the detail" tap so the headline stands alone.

## Record-on-open follow-ups
- [ ] An auto-started recording is discarded on leaving the Record tab or backgrounding the app.
      Check on the handset that this does not eat a recording the user did mean to keep (e.g. they
      pull down the notification shade mid-flyover).
- [ ] OpenSky credentials are still not configured on Ben's handset, so no past snap can ever be
      looked up. Either walk through creating an account or accept that offline captures go out as
      "not identified".
