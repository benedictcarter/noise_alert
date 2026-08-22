# noise_alert

Aircraft noise complaint app for iOS and Android. Press one button during an overflight: the app
records the sound level (A-weighted, with a 30 s pre-roll), the GPS fix and the time, looks up the
flight on free ADS-B data, and hands your mail app a ready-to-send complaint letter.

Nothing leaves the device except the email you send yourself, from your own account.

- Design and rationale: [PLAN.md](PLAN.md)
- Outstanding work: [TODO.md](TODO.md) · completed: [DONE.md](DONE.md)
- Gotchas worth knowing before you touch the audio path: [LESSONS_LEARNT.md](LESSONS_LEARNT.md)

## Build

```sh
flutter pub get
flutter analyze      # must be clean
flutter test         # 150 tests
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
