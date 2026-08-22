# Reviewing this codebase

11,211 lines of Dart in `lib/`, plus 166 tests. This is the order to read it in
and what to look for in each part.

The directories are functional lanes, not layers. There is no `data/`,
`domain/` or `features/`: a question about the microphone is answered inside
`lib/mic/`, a question about the letter inside `lib/letter/`, and a question
about what leaves the device inside `lib/net/`.

---

## 1. Start here: what leaves the device

This is the security review, and it is deliberately small enough to read in
full. **Seven files carry an `// OUTBOUND:` banner and no others can.**

```
grep -rn "^// OUTBOUND" lib
```

| File | Lines | Goes to | Sends | When |
|---|---|---|---|---|
| [net/endpoints.dart](lib/net/endpoints.dart) | 49 | (the list itself) | | |
| [net/live_adsb.dart](lib/net/live_adsb.dart) | 154 | api.adsb.lol, api.airplanes.live | lat, lon, radius | every 3 s while recording |
| [net/opensky.dart](lib/net/opensky.dart) | 217 | auth.opensky-network.org, opensky-network.org | the user's own credentials, then a lat/lon box | only if they entered credentials |
| [net/postcodes.dart](lib/net/postcodes.dart) | 115 | api.postcodes.io | one postcode | only on a button press |
| [net/client.dart](lib/net/client.dart) | 21 | (the shared HTTP client) | | |
| [map/live_map.dart](lib/map/live_map.dart) | 439 | tiles.openfreemap.org | tile coordinates | while a map is on screen |
| [map/snapshot_host.dart](lib/map/snapshot_host.dart) | 218 | tiles.openfreemap.org | tile coordinates | while building the attached picture |
| [letter/sender.dart](lib/letter/sender.dart) | 134 | the user's own mail app | the whole complaint | only when they press send |

Read [net/endpoints.dart](lib/net/endpoints.dart) first. Every address the app
can reach is in it, with a table of what each one is sent.

**The claim, and how it is held.**
[test/outbound_surface_test.dart](test/outbound_surface_test.dart) fails the
build if any of this drifts:

- nothing outside `lib/net/` imports `package:http`
- no `http://` or `https://` appears in any Dart file except `endpoints.dart`,
  comments included
- `endpoints.dart` resolves to exactly six hosts, listed by name in the test
- exactly those seven files carry the banner
- `pubspec.yaml` contains no analytics, crash reporting or backend SDK

So the review question is not "did I find all the calls". It is "are these six
hosts acceptable, and is what each is sent as small as it claims".

**The two things worth arguing about.**

1. **Map tiles are fetched by native MapLibre, not by Dart.** There is no line
   of code in this repo that makes that request, so reading the source cannot
   prove what is in it. What can be said is that the style URL carries no key
   and no account, and that MapLibre is given nothing but a camera position.
   Verifying it properly means a proxy, not a code review.
2. **`letter/sender.dart` is the actual exfiltration point.** Name, address,
   time, decibels, aircraft, map and audio clip all go into a draft. It leaves
   through the user's own mail account, under their own reply address, at their
   hand. That is the design, not a leak, but it is where the personal data is.

---

## 2. The lanes

Read in this order. Each one stands alone.

| # | Lane | Files | Lines | What it is |
|---|---|---|---|---|
| 1 | [net/](lib/net/) | 5 | 556 | Everything that touches the network |
| 2 | [mic/](lib/mic/) | 8 | 1,410 | Recording and measuring sound |
| 3 | [where/](lib/where/) | 2 | 290 | GPS and the geometry on a sphere |
| 4 | [flights/](lib/flights/) | 6 | 929 | Deciding which aircraft it was |
| 5 | [map/](lib/map/) | 9 | 1,679 | Drawing the evidence picture |
| 6 | [chart/](lib/chart/) | 3 | 659 | Drawing the level trace |
| 7 | [letter/](lib/letter/) | 2 | 600 | Writing and sending the complaint |
| 8 | [snap/](lib/snap/) | 4 | 1,271 | One event, start to saved record |
| 9 | [me/](lib/me/) | 2 | 580 | The user's own details and settings |
| 10 | [ui/](lib/ui/) | 13 | 2,558 | Screens. No logic worth hiding here |
| | [root](lib/) | 3 | 393 | `main`, `app`, `providers` |

---

### 1. `net/` (556 lines)

Covered above. Read it first even if you skip everything else.

Tests: [adsb_parsing_test.dart](test/adsb_parsing_test.dart),
[postcode_test.dart](test/postcode_test.dart),
[outbound_surface_test.dart](test/outbound_surface_test.dart).

A note on the name `LiveAdsbSource`: one class serves both community feeds
because both speak the readsb/tar1090 `aircraft.json` schema. "tar1090" in the
parsing comments is a wire format, not a service.

### 2. `mic/` (1,410 lines)

The measurement, and the part most worth checking for correctness because a
number in a letter to a council should be defensible.

Read in this order:

1. [mic/config.dart](lib/mic/config.dart) (57) then
   [mic/ring_buffer.dart](lib/mic/ring_buffer.dart) (61). Why 48 kHz, and why
   there is a rolling pre-roll at all.
2. [mic/biquad.dart](lib/mic/biquad.dart) (156) and
   [mic/a_weighting.dart](lib/mic/a_weighting.dart) (118). The IEC 61672 A
   curve, as a cascade of biquads.
3. [mic/analyzer.dart](lib/mic/analyzer.dart) (357). The one to actually read.
4. [mic/metrics.dart](lib/mic/metrics.dart) (190),
   [mic/recorder.dart](lib/mic/recorder.dart) (361),
   [mic/wav_writer.dart](lib/mic/wav_writer.dart) (110).

**The design decision to check:** the headline figure is the peak against the
background, and the background is the quietest tenth of the recording (LA90),
never a mean. A mean is dragged up by the aircraft it is meant to be compared
against. Both readings come off one microphone in one recording, so the gap is
like-for-like whatever that handset is individually out by.

There is no calibration concept anywhere: no setting, no offset field, no
"uncalibrated" caveat. That is deliberate, and it is the reason the letter
leads on the rise rather than an absolute figure.

Tests: [noise_analyzer_test.dart](test/noise_analyzer_test.dart) (18),
[a_weighting_test.dart](test/a_weighting_test.dart) (5),
[ring_buffer_test.dart](test/ring_buffer_test.dart) (5).

### 3. `where/` (290 lines)

[where/geo.dart](lib/where/geo.dart) (73) is pure maths: haversine, bearings,
the local flat-earth approximation. Read it before `flights/matcher.dart`,
which leans on it.

[where/location.dart](lib/where/location.dart) (217) is permissions and fixes.
The thing to note: a missing fix degrades the complaint, it never blocks it.

### 4. `flights/` (1,087 lines)

1. [flights/aircraft.dart](lib/flights/aircraft.dart) (178) and
   [flights/match.dart](lib/flights/match.dart) (95). The shapes.
2. [flights/source.dart](lib/flights/source.dart) (39). The interface the two
   net clients implement.
3. [flights/matcher.dart](lib/flights/matcher.dart) (316). Scoring, and the
   speed-of-sound correction: an aircraft at 3 km was overhead nine seconds
   before you heard it.
4. [flights/lookup.dart](lib/flights/lookup.dart) (254). Which source, in what
   order, and the rolling track cache.
5. [flights/watch.dart](lib/flights/watch.dart) (158). Who turns the polling on
   and off. Short answer: opening the app and leaving it, and nothing else.

**The design decision to check:** the app names the top candidate outright when
it was within 1 km horizontally
([`MatchConfig.autoConfirmMaxHorizontalM`](lib/flights/config.dart)), and shows
a review screen otherwise. Every letter says the identification is the closest
match and has not been independently verified. That wording is not decoration:
it is what makes naming a stranger's callsign defensible.

Tests: [flight_matcher_test.dart](test/flight_matcher_test.dart) (6),
[auto_confirm_test.dart](test/auto_confirm_test.dart) (4),
[sky_watch_test.dart](test/sky_watch_test.dart) (10).

### 5. `map/` (1,726 lines)

The largest lane and the least surprising. The whole of it exists because
MapLibre's snapshotter renders the basemap only: runtime layers are absent from
the result, so tracks, the house and the legend are painted in Dart through the
app's own projection.

1. [map/projection.dart](lib/map/projection.dart) (129) and
   [map/geometry.dart](lib/map/geometry.dart) (91). Web Mercator, and framing.
2. [map/overlay.dart](lib/map/overlay.dart) (300). The painter. Attribution,
   scale bar and "closest match" wording are baked into the PNG so they travel
   with it.
3. [map/snapshot_host.dart](lib/map/snapshot_host.dart) (218) and
   [map/image_service.dart](lib/map/image_service.dart) (211). The offscreen
   render.
4. [map/live_map.dart](lib/map/live_map.dart) (439),
   [map/layers.dart](lib/map/layers.dart) (166),
   [map/plane_icon.dart](lib/map/plane_icon.dart) (97),
   [map/nearby.dart](lib/map/nearby.dart) (35). The on-screen map, and how much
   of the sky it is willing to draw.

Tests: [map_test.dart](test/map_test.dart) (24).

### 6. `chart/` (659 lines)

[chart/painter.dart](lib/chart/painter.dart) (403) draws the level trace for
both the screen and the attached PNG. Self-contained.

Tests: [level_chart_test.dart](test/level_chart_test.dart) (6).

### 7. `letter/` (600 lines)

[letter/template.dart](lib/letter/template.dart) (466) is the text of the
complaint and the rules for what to say when evidence is missing. Almost all of
its length is prose, and it is the file to read if you want to know what the
app actually claims on the user's behalf.

[letter/sender.dart](lib/letter/sender.dart) (134) hands the draft to the mail
app. Flagged above.

**The design decision to check:** a complaint is never blocked by missing
evidence. No microphone, no fix and no flight is still a valid report. Sound,
location and a named aircraft each make it stronger; none is a precondition.
The template has a branch for every combination and the tests enumerate them.

Tests: [complaint_template_test.dart](test/complaint_template_test.dart) (31),
[settings_template_test.dart](test/settings_template_test.dart) (8).

### 8. `snap/` (1,271 lines)

[snap/snap_service.dart](lib/snap/snap_service.dart) (696) is the orchestrator:
arm, record, stop, analyse, match, draw, save. The single largest file and the
one place the lanes meet. Read it after them, not before.

[snap/snap.dart](lib/snap/snap.dart) (292) is the record itself,
[snap/database.dart](lib/snap/database.dart) (211) the sqflite store.

Note: enum names are persisted as strings via `.name`, which is why release
builds are not obfuscated. See [LESSONS_LEARNT.md](LESSONS_LEARNT.md).

Tests: [database_test.dart](test/database_test.dart) (19).

### 9. `me/` (580 lines)

[me/profile.dart](lib/me/profile.dart) (214). The only mandatory fields are a
name and a postcode. House number, street, town and phone are optional, and no
email address is asked for at all, because the letter goes from the user's own
account and the reply address travels with it. `ComplainantProfile.isComplete`
is the single definition of "enough to complain with".

[me/settings.dart](lib/me/settings.dart) (366) includes the settings upgrade
path. `_legacyDefaultSubjects` holds strings that must byte-match what is
already stored on installs; do not tidy them.

### 10. `ui/` (2,558 lines)

Screens, and nothing a reviewer needs to trust.
[ui/snap/snap_screen.dart](lib/ui/snap/snap_screen.dart) (861) is the big one,
and it is big because it is a state machine with a lot of states, all of them
visible.

---

## 3. Running it

```
flutter analyze     # expected: no issues
flutter test        # expected: 166 passing
```

Release build: [scripts/build_release.sh](scripts/build_release.sh). It carries
`--split-per-abi`, and the comments explain why `--target-platform` is a trap
and why `--obfuscate` is not used.

## 4. What is deliberately absent

Worth knowing so you do not go looking:

- No backend, no accounts, no sync, no analytics, no crash reporting.
- No calibration UI, no dB offset, no "uncalibrated" caveat.
- No email address field.
- No code generation. Models are hand-written and immutable; Riverpod is used
  without its generator.
- No dependency injection framework beyond `providers.dart`.

The reasoning for each is in [CLAUDE.md](CLAUDE.md) under Non-negotiables, and
the longer argument in [PLAN.md](PLAN.md).
