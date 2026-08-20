# noise_alert

Flutter (iOS + Android) app for logging aircraft noise events and generating complaint emails.

- Design and rationale: [PLAN.md](PLAN.md)
- Outstanding work: [TODO.md](TODO.md) — completed work moves to [DONE.md](DONE.md)
- Hard-won gotchas: [LESSONS_LEARNT.md](LESSONS_LEARNT.md) — append as they are hit

## Non-negotiables
- **No personal data leaves the device.** No backend, no analytics, no crash reporter that ships
  location. Complaints are sent by the user from their own mail account.
- **Never state a flight the user has not confirmed.** Matching is probabilistic; the review screen
  always shows confidence and alternates.
- **Never present uncalibrated dB as an absolute measurement.** Label it in the UI and in the email.
- **An audio clip is always saved** (the loudest 10 s, on the device only). The only question
  put to the user is whether to *attach* it, and it is previewable before sending.
