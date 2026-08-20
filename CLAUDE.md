# noise_alert

Flutter (iOS + Android) app for logging aircraft noise events and generating complaint emails.

- Design and rationale: [PLAN.md](PLAN.md)
- Outstanding work: [TODO.md](TODO.md) — completed work moves to [DONE.md](DONE.md)
- Hard-won gotchas: [LESSONS_LEARNT.md](LESSONS_LEARNT.md) — append as they are hit

## Non-negotiables
- **No personal data leaves the device.** No backend, no analytics, no crash reporter that ships
  location. Complaints are sent by the user from their own mail account.
- **Name the closest match, and say that is what it is.** STOP & SEND names the top ADS-B
  candidate outright when it was within `MatchConfig.autoConfirmMaxHorizontalM` (1 km) horizontally;
  beyond that it degrades to STOP & SAVE and the review screen shows confidence and alternates.
  Every letter states that the identification is the closest match and has not been independently
  verified.
- **A complaint is never blocked by missing evidence.** No microphone, no fix and no flight is
  still a valid report: "I live at this address and at this time a plane annoyed me" is sufficient.
  Sound, location and a named aircraft each make it stronger; none of them is a precondition.
- **Never present uncalibrated dB as an absolute measurement.** Label it in the UI and in the email.
- **An audio clip is always saved** (the loudest 10 s, on the device only). The only question
  put to the user is whether to *attach* it, and it is previewable before sending.
