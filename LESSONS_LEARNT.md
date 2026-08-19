# Lessons Learnt

Non-obvious gotchas hit while building noise_alert. Append as they happen — mechanism first, then the
incident that taught it.

## Flightradar24 has no free tier — do not design around it (2026-08-19)
**Mechanism:** the FR24 API is an enterprise, quote-based product gated behind sales; there is no
self-serve key. Designing the matcher against it would have stalled the project at the first API call.
**What to use instead:** live community ADS-B (`adsb.lol`, `airplanes.live` — free, no key, ~1 req/s)
queried *at the moment of the snap*, with OpenSky (free, OAuth2 client-credentials, 4,000 credits/day)
as the fallback. OpenSky is the only free source that serves **historical** data, and only for the
last **1 hour** — which is exactly why the offline back-fill window is one hour and not one day.

## Sound arrives late, so "the plane at time T" is the wrong query (2026-08-19)
**Mechanism:** sound travels ~343 m/s. An aircraft at 3,000 ft slant range was overhead ~2.7 s before
you heard it; at 10,000 ft, ~9 s. Add human reaction time to press the button and the true overhead
moment can be 20–40 s before the timestamp. Querying the instantaneous position at T will regularly
name the wrong aircraft — and a complaint naming the wrong airline is worse than one naming none.
**Rule:** search T−45 s to T+10 s and score by closest approach, not by position at T.

## A-weighting needs 48 kHz, and still over-attenuates at 16 kHz (2026-08-19)
**Mechanism:** the A-weighting curve is a pole at 20.6 Hz (×2), 107.7 Hz, 737.9 Hz and 12,194 Hz (×2).
Realising it as biquads means a **bilinear transform**, which warps the analogue frequency axis onto
the digital one: `ω_d = 2·arctan(ω_a·T/2)`. The warp is negligible well below Nyquist and severe near
it. At the common 16 kHz voice sample rate, Nyquist is 8 kHz — *below* the 12.2 kHz pole pair, so that
whole section collapses and the filter is no longer A-weighting in any meaningful sense.
**Incident:** the plan said "16 kHz mono" (plenty for speech, and cheap). The first response check
against IEC 61672-1 Table 3 was nonsense above 4 kHz. Moved to 48 kHz — where the same table now
matches within 0.6 dB up to 4 kHz and 1.0 dB at 8 kHz — and added
`AWeighting.minimumRecommendedSampleRate` so the mistake cannot be made silently again.
**Residual, deliberately accepted:** even at 48 kHz the response at 16 kHz reads **−13.1 dB against a
nominal −6.6 dB — about 6.5 dB low**, because 16 kHz is fs/3 and the warp bites. This is fine and the
test asserts it as a one-sided bound: IEC 61672-1 leaves the *lower* tolerance at 16 kHz effectively
unbounded for both classes, aircraft noise has no meaningful content up there, and under-reading is
conservative for a complaint. Reading *above* nominal would not be acceptable, so the test still
checks that side tightly.

## Ask the OS for the *unprocessed* mic, or you are measuring the AGC (2026-08-19)
**Mechanism:** the default capture path on both platforms is tuned for voice calls — automatic gain
control, noise suppression and echo cancellation are on. AGC pulls loud sounds *down* and quiet ones
*up*, which is precisely the dynamic range a noise measurement exists to record. A 90 dB flyover over
a 38 dB background can come back looking like a 15 dB event.
**Rule:** `AndroidAudioSource.unprocessed` (falls back to `mic`, never `voiceCommunication`), all
three processing flags off, and **block Bluetooth mic routing** on both platforms — a headset mic is
a different transducer in a different place, so any calibration offset is meaningless and the level
is not the level at the user's location.

## `sdkmanager --licenses` must be driven from Bash, not PowerShell (2026-08-19)
**Mechanism:** the licence prompt reads raw stdin. PowerShell's pipeline hands the process objects and
line-terminates differently, so `"y" * 10 | sdkmanager --licenses` either hangs or accepts nothing,
and `flutter doctor` keeps reporting unaccepted licences with no useful error.
**Fix:** run it from the Bash tool: `yes | sdkmanager --licenses`. Generally, for any tool that reads
interactive stdin on Windows, reach for Bash rather than PowerShell.

## `require_trailing_commas` and `dart format` fight each other (2026-08-19)
**Mechanism:** since Dart 3.7's "tall" formatter, `dart format` *removes* trailing commas where it
decides an argument list fits on one line. The `require_trailing_commas` lint then demands them back.
**Incident:** `dart fix --apply` added 13 commas, `dart format` deleted the same 13, and the next
`flutter analyze` reported the same 13 infos — a loop with no fixed point. Removed the lint from
`analysis_options.yaml` with a comment saying why, so nobody re-adds it.

## Dart `const` maps cannot be keyed by `double` (2026-08-19)
**Mechanism:** a `const` map key must have primitive equality. `double` does not — `==` on doubles is
not the identity relation the const canonicaliser needs (think `0.0`/`-0.0`, `NaN`). The error is
`const_map_key_not_primitive_equality`, once per entry, which reads like ten separate problems.
**Fix:** `const List<(double, double)>` of records, iterated with
`for (final (double f, double expected) in table)`. Same ergonomics, no allocation, compiles.

## Flutter's `<queries>` block is a singleton (2026-08-19)
**Mechanism:** Android package-visibility filtering (API 30+) means the mail composer will not be
found unless `SENDTO`/`mailto` is declared in `<queries>`. The Flutter template already ships a
`<queries>` block for `PROCESS_TEXT`. Adding a *second* one is a manifest-merger failure at build
time, not an analyze-time error, so it surfaces late.
**Rule:** merge new intents into the existing `<queries>` element; never add another.

## Write large markdown with the Write tool, not a Bash heredoc (2026-08-19)
**Mechanism:** long heredocs through the Bash tool on Windows hit quoting and line-ending trouble and
fail in ways that are tedious to diagnose. Surgical edits via a `python - <<'PY'` heredoc are fine and
are the better tool for a targeted substitution; whole-file authoring is not.

## Timestamp the button press before awaiting anything (2026-08-19)
**Mechanism:** a GPS fix can take 200 ms on a warm receiver and 30 s on a cold one; an ADS-B query is
a network round trip. If the "event time" is read *after* those awaits, the recording window and the
flight-search window both slide by an unbounded, invisible amount — and the matcher then scores
candidates against a time the user never experienced.
**Rule:** `capture()` sets `pressedAt = DateTime.now()` on its first line, before touching GPS, audio
or the network, and everything downstream is expressed relative to that instant. Related: the `Snap`
is written to the database *before* the flight lookup runs, so a dead network loses the identification
but never the measurement.
