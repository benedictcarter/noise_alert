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
flutter test         # 31 tests
flutter run          # Android; iOS needs a Mac
```

iOS cannot be built on Windows: a macOS machine or CI runner is required for TestFlight.
