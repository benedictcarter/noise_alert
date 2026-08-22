# noise_alert

Aircraft noise complaint app for iOS and Android. Press one button during an overflight: the app
records the sound level (A-weighted, with a 30 s pre-roll), the GPS fix and the time, looks up the
flight on free ADS-B data, and hands your mail app a ready-to-send complaint letter.

Nothing leaves the device except the email you send yourself, from your own account.

- **Reading the code for the first time: [REVIEW.md](REVIEW.md)**
- Design and rationale: [PLAN.md](PLAN.md)
- Outstanding work: [TODO.md](TODO.md) · completed: [DONE.md](DONE.md)
- Gotchas worth knowing before you touch the audio path: [LESSONS_LEARNT.md](LESSONS_LEARNT.md)

## Layout

`lib/` is organised by function, not by layer:

| Directory | What lives there |
|---|---|
| [net/](lib/net/) | every outbound call, and every URL |
| [mic/](lib/mic/) | recording and measuring sound |
| [where/](lib/where/) | GPS and the geometry on a sphere |
| [flights/](lib/flights/) | deciding which aircraft it was |
| [map/](lib/map/) | drawing the evidence picture |
| [chart/](lib/chart/) | drawing the level trace |
| [letter/](lib/letter/) | writing and sending the complaint |
| [snap/](lib/snap/) | one event, start to saved record |
| [me/](lib/me/) | the user's own details and settings |
| [ui/](lib/ui/) | screens |

Everything that touches the network is in [lib/net/](lib/net/) and every address the app can reach
is in [lib/net/endpoints.dart](lib/net/endpoints.dart). That is enforced, not just intended:
[test/outbound_surface_test.dart](test/outbound_surface_test.dart) fails the build if a URL or an
import of `package:http` appears anywhere else. Files that can reach the network carry an
`// OUTBOUND:` banner saying what they send and when:

```sh
grep -rn "^// OUTBOUND" lib
```

## Build

```sh
flutter pub get
flutter analyze      # must be clean
flutter test         # 166 tests
flutter run          # Android; iOS needs a Mac
```

iOS cannot be built on Windows: a macOS machine or CI runner is required for TestFlight.

## Release

```sh
scripts/build_release.sh
```

Use the script rather than a bare `flutter build apk`. A plain release build is 83 MB because it
carries three copies of every native library, one per CPU; the script splits them and the arm64 APK
that a real phone installs is 29 MB. The script explains both of its flags and why
`--target-platform android-arm64` is not one of them.

Two consequences of splitting, both permanent:

- The build number is offset by ABI, so pubspec `+17` ships as versionCode 2017 on arm64. Android
  refuses any later install with a lower versionCode, so once a split APK is on a phone every
  future build for it has to be a split one too.
- `build/symbols` is the only copy of the Dart symbol table. Archive it next to the APK it came
  from, as `release/symbols-vX.Y.Z`, or that build's stack traces are unreadable forever.

R8 (`isMinifyEnabled`) was measured and does nothing here: the Android half of a Flutter app is a
thin shell of plugin entry points that the keep rules protect, so the APK came out byte for byte
identical. It is deliberately left off.
