# noise_alert

Flutter (iOS + Android) app for logging aircraft noise events and generating complaint emails.

- Reading it for the first time: [REVIEW.md](REVIEW.md)
- Design and rationale: [PLAN.md](PLAN.md)
- Outstanding work: [TODO.md](TODO.md). Completed work moves to [DONE.md](DONE.md)
- Hard-won gotchas: [LESSONS_LEARNT.md](LESSONS_LEARNT.md). Append as they are hit

## Non-negotiables
- **No personal data leaves the device.** No backend, no analytics, no crash reporter that ships
  location. Complaints are sent by the user from their own mail account. Five outbound services exist
  and every one of them is deliberate: coordinates to adsb.lol and to airplanes.live to find the
  aircraft that is overhead now; coordinates to the OpenSky Network to find one that was overhead up
  to an hour ago, and only once the user has put their own OpenSky credentials in Settings; map
  tiles from OpenFreeMap, which are requested by tile coordinate and carry no key, no cookie and no
  account; and (only when the user presses the button) a postcode to postcodes.io to fill in their
  town. No name, no email address and no identifier goes with any of them. Adding a sixth is a
  decision, not a detail. This is enforced rather than promised: everything that touches the
  network lives in `lib/net/`, every address is in `lib/net/endpoints.dart`, every file that can
  reach out carries an `// OUTBOUND:` banner, and
  [test/outbound_surface_test.dart](test/outbound_surface_test.dart) fails the build if any of
  that drifts. Adding a host means changing that test, this paragraph and REVIEW.md in the same
  commit.
- **The only mandatory fields are a name and a postcode.** House number, street, town and phone
  number are all optional, and no email address is asked for at all: the letter goes from the
  user's own mail account, so the reply address travels with it. `ComplainantProfile.isComplete`
  is the single definition of "enough to complain with".
- **Name the closest match, and say that is what it is.** SEND names the top ADS-B
  candidate outright when it was within `MatchConfig.autoConfirmMaxHorizontalM` (1 km) horizontally;
  beyond that it degrades to REVIEW and the review screen shows confidence and alternates.
  Every letter states that the identification is the closest match and has not been independently
  verified.
- **A complaint is never blocked by missing evidence.** No microphone, no fix and no flight is
  still a valid report: "I live at this address and at this time a plane annoyed me" is sufficient.
  Sound, location and a named aircraft each make it stronger; none of them is a precondition.
- **Lead on the rise, not on an absolute figure.** The headline is the peak against the
  background, and the background is the quietest tenth of the recording (LA90), never a mean: a
  mean is dragged up by the aircraft it is supposed to be compared against. Both readings come off
  the same microphone in the same recording, so the gap is a like-for-like comparison whatever that
  handset is individually out by. There is **no calibration concept in the app at all**: no setting,
  no offset field, no "uncalibrated" caveat anywhere in the UI or the letter.
- **The map is evidence, and it is drawn rather than screenshotted.** MapLibre's snapshotter
  renders the basemap only, so the tracks, the house and the legend are painted in Dart through the
  app's own projection. Every map carries the OpenFreeMap attribution, a scale bar and the "closest
  match" wording, baked into the PNG so they travel with it. No fix, no tiles or no aircraft each
  degrade the picture; none of them blocks a send.
- **An audio clip is always saved** (the loudest 10 s, on the device only). The only question
  put to the user is whether to *attach* it, and it is previewable before sending.

## Layout

`lib/` is organised by function, not by layer. There is no `data/`, `domain/` or `features/`.

`net/` (outbound calls, and the only place a URL may appear) · `mic/` (recording and measurement) ·
`where/` (GPS and geometry) · `flights/` (which aircraft it was) · `map/` (the evidence picture) ·
`chart/` (the level trace) · `letter/` (writing and sending) · `snap/` (one event, end to end) ·
`me/` (the user's details and settings) · `ui/` (screens).

Tunable constants sit with the lane they tune: `mic/config.dart`, `flights/config.dart`,
`map/config.dart`. Addresses do not: they are all in `net/endpoints.dart`.
