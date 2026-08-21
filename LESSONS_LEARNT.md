# Lessons Learnt

Non-obvious gotchas hit while building noise_alert. Append as they happen: mechanism first, then the
incident that taught it.

## Flightradar24 has no free tier: do not design around it (2026-08-19)
**Mechanism:** the FR24 API is an enterprise, quote-based product gated behind sales; there is no
self-serve key. Designing the matcher against it would have stalled the project at the first API call.
**What to use instead:** live community ADS-B (`adsb.lol`, `airplanes.live`: free, no key, ~1 req/s)
queried *at the moment of the snap*, with OpenSky (free, OAuth2 client-credentials, 4,000 credits/day)
as the fallback. OpenSky is the only free source that serves **historical** data, and only for the
last **1 hour**, which is exactly why the offline back-fill window is one hour and not one day.

## Sound arrives late, so "the plane at time T" is the wrong query (2026-08-19)
**Mechanism:** sound travels ~343 m/s. An aircraft at 3,000 ft slant range was overhead ~2.7 s before
you heard it; at 10,000 ft, ~9 s. Add human reaction time to press the button and the true overhead
moment can be 20-40 s before the timestamp. Querying the instantaneous position at T will regularly
name the wrong aircraft, and a complaint naming the wrong airline is worse than one naming none.
**Rule:** search T-45 s to T+10 s and score by closest approach, not by position at T.

## A-weighting needs 48 kHz, and still over-attenuates at 16 kHz (2026-08-19)
**Mechanism:** the A-weighting curve is a pole at 20.6 Hz (×2), 107.7 Hz, 737.9 Hz and 12,194 Hz (×2).
Realising it as biquads means a **bilinear transform**, which warps the analogue frequency axis onto
the digital one: `ω_d = 2·arctan(ω_a·T/2)`. The warp is negligible well below Nyquist and severe near
it. At the common 16 kHz voice sample rate, Nyquist is 8 kHz: *below* the 12.2 kHz pole pair, so that
whole section collapses and the filter is no longer A-weighting in any meaningful sense.
**Incident:** the plan said "16 kHz mono" (plenty for speech, and cheap). The first response check
against IEC 61672-1 Table 3 was nonsense above 4 kHz. Moved to 48 kHz: where the same table now
matches within 0.6 dB up to 4 kHz and 1.0 dB at 8 kHz, and added
`AWeighting.minimumRecommendedSampleRate` so the mistake cannot be made silently again.
**Residual, deliberately accepted:** even at 48 kHz the response at 16 kHz reads **-13.1 dB against a
nominal -6.6 dB: about 6.5 dB low**, because 16 kHz is fs/3 and the warp bites. This is fine and the
test asserts it as a one-sided bound: IEC 61672-1 leaves the *lower* tolerance at 16 kHz effectively
unbounded for both classes, aircraft noise has no meaningful content up there, and under-reading is
conservative for a complaint. Reading *above* nominal would not be acceptable, so the test still
checks that side tightly.

## Ask the OS for the *unprocessed* mic, or you are measuring the AGC (2026-08-19)
**Mechanism:** the default capture path on both platforms is tuned for voice calls: automatic gain
control, noise suppression and echo cancellation are on. AGC pulls loud sounds *down* and quiet ones
*up*, which is precisely the dynamic range a noise measurement exists to record. A 90 dB flyover over
a 38 dB background can come back looking like a 15 dB event.
**Rule:** `AndroidAudioSource.unprocessed` (falls back to `mic`, never `voiceCommunication`), all
three processing flags off, and **block Bluetooth mic routing** on both platforms: a headset mic is
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
`flutter analyze` reported the same 13 infos: a loop with no fixed point. Removed the lint from
`analysis_options.yaml` with a comment saying why, so nobody re-adds it.

## Dart `const` maps cannot be keyed by `double` (2026-08-19)
**Mechanism:** a `const` map key must have primitive equality. `double` does not: `==` on doubles is
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
flight-search window both slide by an unbounded, invisible amount, and the matcher then scores
candidates against a time the user never experienced.
**Rule:** `capture()` sets `pressedAt = DateTime.now()` on its first line, before touching GPS, audio
or the network, and everything downstream is expressed relative to that instant. Related: the `Snap`
is written to the database *before* the flight lookup runs, so a dead network loses the identification
but never the measurement.

## Dropping freezed means hand-writing `==`, or Riverpod over-rebuilds silently (2026-08-19)
**Mechanism:** `StateNotifier.state = x` only notifies listeners when `state != x`. Dart's default
`==` is identity, so a hand-written model always compares unequal to a fresh copy of itself: every
`copyWith` from a text field's `onChanged` looks like a genuine change and rebuilds every consumer of
that provider. Nothing fails; the app is just quietly doing far more work than it looks like, and the
settings form is the worst case because it fires per keystroke. freezed generates `==` for you, which
is why the trap only appears once you have decided not to use it.
**Incident:** a database test asserted `await db.loadProfile() == profile` and failed with
`Expected: <Instance of 'ComplainantProfile'>  Actual: <Instance of 'ComplainantProfile'>`: two
objects with identical fields. Added `==`/`hashCode` to `ComplainantProfile`, `RecipientSet` and
`AppSettings`.
**Rule:** every hand-written model that ends up in provider state needs `==` and `hashCode`, and the
cheapest way to notice a missing one is to assert value equality in a test.

## sqflite has no desktop binding: use `sqflite_common_ffi` in tests (2026-08-19)
**Mechanism:** `sqflite` is a plugin over the platform's own SQLite, so in the Dart test VM there is
no implementation at all and every call throws `MissingPluginException`. `sqflite_common_ffi` links
real SQLite through `dart:ffi`, so the tests exercise genuine SQL rather than a fake.
**Recipe:** `sqfliteFfiInit(); databaseFactory = databaseFactoryFfi;` at the top of `main()`, and open
with `inMemoryDatabasePath` so each test gets a clean schema with no temp files to clean up. This is
also why `AppDatabase.open` takes an `overridePath`: `getApplicationDocumentsDirectory()` is itself a
plugin call and would fail in tests.

## There is no plain `platforms;android-37` any more (only minor versions (2026-08-19)
**Mechanism:** Google now ships Android platforms with a minor version in the folder name)
`android-37.0`, `android-37.1`, `android-37.2-beta*`, and there is no bare `android-37` alias.
A plugin whose Gradle script sets `compileSdkVersion 37` (or whose AGP resolves a compileSdk it
inherited from an older template) asks the SDK for the hash string `android-37`, which cannot
resolve, and the build dies with a message that reads like a missing download rather than a naming
change: `Failed to find target with hash string 'android-37' in: C:\Android\sdk`.
**Incident:** the first release APK build failed on
`:permission_handler_android:compileReleaseJavaWithJavac`. `sdkmanager --list` confirmed only
`platforms;android-37.0` and friends exist, so no amount of installing would have produced
`android-37`. `permission_handler` was declared but never used (`record` and `geolocator` each
request their own runtime permission) so dropping it (with `share_plus`, also unused) fixed the
build outright.
**Rule:** when a plugin demands a platform hash that `sdkmanager --list` does not offer, check
whether you need the plugin at all before chasing the SDK. An unused dependency can still break a
build, because Gradle configures and compiles every module regardless of whether Dart imports it.

## Kotlin incremental compilation corrupts its own caches on Windows (2026-08-19)
**Mechanism:** the Kotlin incremental compiler memory-maps its lookup caches (`*.tab`) and, on
Windows, frequently fails to unmap them before closing, because Windows will not let a mapped file be
truncated or deleted while a view is open. The build then fails at the *end* of an otherwise
successful module compile with `Could not close incremental caches in
...\caches-jvm\jvm\kotlin: class-fq-name-to-source.tab, ...`.
**Incident:** two consecutive release builds failed this way: the first on
`:record_android:compileReleaseKotlin`, the second on `:audio_session:compileReleaseKotlin`.
**I misread the first failure as stale build state and ran `flutter clean`; it recurred on a
different module from a completely clean tree**, which is the tell that it is not stale state at all.
Setting `kotlin.incremental=false` in `android/gradle.properties` fixed it permanently, and costs
nothing on a release build, which recompiles everything anyway.
**Rule:** a build error naming a different module on each run is about the *machine*, not the
modules. `flutter clean` is the wrong reflex: it burns several minutes and proves nothing, because a
clean tree reproduces a genuinely environmental failure just as reliably.

## When ADB will not see a phone, MTP still can (2026-08-19)
**Mechanism:** ADB needs the handset to expose a dedicated ADB *USB interface*, which shows up on
Windows as a composite-device child ending `&MI_nn`. If the phone enumerates as a single-function
WPD/MTP device, there is no interface for any driver to bind to and no driver install can conjure
one: `adb devices` will stay empty however many times you toggle USB debugging.
**Incident:** an LG G7 ThinQ (`USB\VID_1004&PID_633E\...`) enumerated single-function WPD with no
`&MI_nn` children, and `Get-PnpDevice` history showed it had never presented an ADB interface under
any of its four historical PIDs. Restarting the adb server, revoking authorisations, re-toggling
developer mode, different ports and the Google USB driver all changed nothing. Android 10 was not the
cause.
**Workaround that does work:** sideload over MTP from PowerShell:
`(New-Object -ComObject Shell.Application).NameSpace(17)` lists portable devices; walk to
`Internal shared storage\Download` and `CopyHere($apkPath, 16)`, then the user taps the file in a
file manager. `Install unknown apps` must be granted to *the file manager doing the tapping*, not to
the APK. Slow and manual, but it unblocks on-device testing without ADB.

## FileProvider silently vetoes attachments from `getApplicationDocumentsDirectory()` (2026-08-20)
**Mechanism:** `flutter_email_sender` hands each attachment to
`FileProvider.getUriForFile(activity, packageName + ".file_provider", File(path))`, and the paths it
declares in its own `shared_file_paths.xml` are only `external-path`, `cache-path` and `files-path`.
On Android, path_provider maps `getApplicationDocumentsDirectory()` to `<data>/app_flutter` and
`getApplicationSupportDirectory()` to `<data>/files`. `files-path` means `<data>/files`, so
`app_flutter` is outside every declared root and `getUriForFile` throws
`IllegalArgumentException: Failed to find configured root`.
**Incident:** Ben reported that a complaint with no clip was formatted correctly, but a complaint
*with* a clip arrived as "a giant wall of text" with no attachment. The clip path was the cause, not
the body: the throw escaped into our blanket `catch`, which degraded to a `mailto:` URL, and Gmail
renders a long `mailto:` body as one unbroken block and cannot carry a file at all. Nothing in the
logs said "attachment": the visible symptom was entirely about formatting.
**Rule:** write anything intended for a share/attach intent to `getApplicationSupportDirectory()`
(or the cache dir), never the documents dir. And a catch-all fallback that changes *transport* will
mask the real error: the composer is now retried without attachments before `mailto:` is considered,
so the failure mode degrades one step at a time and is visible.

## A ring buffer zero-fills history it never recorded (2026-08-20)
**Mechanism:** `PcmRingBuffer.readEndingAt` returns a fixed-length window ending at a given sample
position. Before the buffer has been filled once, the samples "before" the recording started are
whatever the buffer was initialised to: zeros. Zeros are not quiet; they are digital silence, tens
of dB below any real room, and they drag an LAeq average down and make an L90 percentile meaningless.
**Incident:** found while building the home-screen widget, which fires a capture the instant the mic
opens. Every widget snap (and every ordinary snap taken within 30 s of opening the app) would have
computed its background from unrecorded silence and therefore *overstated* the rise above background
by tens of dB. That is the one direction of error that would discredit a complaint outright.
**Rule:** a ring buffer must report how much of the window is real, not just hand back the window.
`captureEventWindow` now returns an `EventWindow` carrying `preRollSamples`, and the analyser returns
`ambientLa90Db == null` below `minAmbientSeconds` of genuine pre-roll. Modelling "not measured" as a
null rather than a plausible number is the whole point: a nullable field forces every call site
(letter, review screen, excess calculation) to decide what to say, where a default would have
silently produced a confident wrong answer.

## The Bash tool on Windows eats one level of backslash in heredocs (2026-08-20)
**Mechanism:** a `python - <<'PY'` heredoc is quoted, so the shell should pass it through verbatim.
Through this tool on Windows it does not: one level of backslash escaping is stripped before Python
sees the script. `\\'` arrives as `\'`, and `\\n` arrives as a real
`\n`.
**Incident:** a generated Dart string ended up containing a bare apostrophe that unterminated the
literal, and another contained a literal newline inside a single-quoted string: both compile errors
in code that looked correct in the script. Debugging went to the Dart, not the shell, twice.
**Rule:** never rely on backslash escapes surviving a heredoc here. Build them arithmetically inside
Python (`BS = chr(92)`, then `BS + "n"`), pick a quote style that avoids the escape entirely, or
reword the text. The same trap applies to `'''` appearing inside a Python triple-quoted string when the
target language uses it too: Dart multi-line strings and Python ones collide, so use `chr(39) * 3`
and concatenate.


## Deleting a file over MTP hangs the copy behind an invisible dialog (2026-08-20)
**Mechanism:** the LG G7 exposes no ADB interface, so builds go over MTP via the Windows shell COM
API (`Shell.Application` → `NameSpace(17)` → the phone → `Download`). `Folder.InvokeVerb("delete")`
does not delete anything by itself; it asks Explorer to run the delete verb, and Explorer puts up a
confirmation dialog on the *interactive desktop*. A tool-driven session never sees that dialog and
never dismisses it, so the COM call blocks forever and takes the subsequent `CopyHere` with it.
**Incident:** replacing `noise_alert.apk` with a new build wedged the sideload task until it was
killed with TaskStop. Nothing on screen indicated a prompt was waiting.
**Rule:** never invoke a shell verb that can prompt from a non-interactive session. Copy each build
under a fresh name (`noise_alert_b2.apk`, `_b3`, `_b4`) and let the old ones accumulate; a few stale
APKs in `Download` cost less than a hung session. `CopyHere(src, 16)` (16 is "yes to all") is safe
because it answers the overwrite prompt in-process, but it still cannot answer a *delete* prompt.

## A Python patch script that slices at the last `}` silently truncates the file (2026-08-20)
**Mechanism:** the idiom used all session to append tests: `i = s.rstrip().rfind(NL + '}')` then
`s = s.rstrip()[:i] + NL + extra + '}' + NL`: assumes the closing brace of `main()` is the *last*
thing in the file. It discards everything after that index. Any top-level declaration written below
`main()` disappears, and it disappears from a file the script reports as successfully patched.
**Incident:** `test/database_test.dart` keeps `const String _v1SnapsTable` after `main()`. Appending
the recipient-CC tests deleted it, and the failure surfaced as `Undefined name '_v1SnapsTable'` at a
line 250 lines away from the edit. Recovered with `git show HEAD:test/database_test.dart`.
**Rule:** insert before the closing brace by *slicing and rejoining*, not by truncating
(`s[:i] + extra + s[i:]`) or anchor on a unique string near the insertion point. And prefer
keeping helper constants above `main()` so the file has no tail to lose.

## An unbounded recording turns per-sample analysis into an OOM (2026-08-20)
**Mechanism:** the analyzer was written when a capture was a fixed 50 s. It allocated the
A-weighted signal, the squared signal and a per-sample prefix sum (three `Float64List`s the length
of the recording, 24 bytes per sample) which is fine at 50 s (~58 MB) and fatal the moment the
user decides when to stop. Five minutes at 48 kHz is 14.4 M samples: ~345 MB of working arrays on a
phone, on top of the recording itself.
**Incident:** removing the 20 s auto-stop turned a bounded allocation into an unbounded one. Nothing
failed in test (the test tones are seconds long) the fault only exists on a real flyover someone
watches all the way out.
**Rule:** when a length becomes user-controlled, re-audit every allocation that is proportional to
it. The fix here is worth copying: sum A-weighted energy into fixed **25 ms blocks** in a single
pass and prefix-sum over *blocks* rather than samples. 25 ms was chosen because it divides the
125 ms statistical window, the 250 ms trace cadence and the 50 ms peak hop exactly, so no metric
changes its meaning; working memory drops to ~8 bytes per sample, and to 2 bytes when the source is
Int16 behind a `SampleSource` interface.

## A growing buffer spikes memory exactly when you cannot afford it (2026-08-20)
**Mechanism:** the two obvious ways to accumulate an unknown-length recording both peak at more than
they hold. A doubling `Int16List` copies old into new at every resize: 1.5x the final size at the
worst moment, and a list of chunks concatenated at the end peaks at 2x, because the chunks are
still alive while the joined array is being filled. Both spikes land *during* the recording or at
the instant it ends, which is the worst possible time on a phone that is also holding a camera-grade
audio stream and a map.
**Rule:** if there is a hard cap, allocate the cap up front. `Int16List(maxEventSeconds * rate *
1.1)` is claimed once at the press, when there is nothing else in flight, and handed out at the end
as an `Int16List.sublistView`, no copy, no spike, and the allocation either succeeds immediately or
fails before the user has been promised a recording. The 1.1 is headroom for a handset delivering
above the requested sample rate.

## One field meaning two things silently rewrites old records (2026-08-20)
**Mechanism:** `AcousticMetrics.preRollSeconds` meant both "how far into the trace the button press
sits" and "how many seconds of background we had to measure against". While the pre-roll was always
part of the capture those were the same number. The moment the recording started at the press they
diverged: the press is now at 0, but there were still 30 s of background. Reusing the field for
either meaning would have been wrong for the other, and (worse) would have silently re-drawn every
*stored* chart, moving the press marker on records the user had already read and sent.
**Rule:** when a field's two meanings come apart, split the field and give the *old* name the meaning
that stored data already carries. `preRollSeconds` kept the trace-offset meaning (now 0 for new
records), the new `ambientSeconds` carries the background length, and `fromJson` falls back to
`preRollSeconds` when `ambientSeconds` is absent, so a v1 record still marks its press in the right
place.

## Long heredocs to Bash fail where short ones work (2026-08-20)
**Mechanism:** `python - <<'PYEOF'` with a ~200-line body repeatedly died with
`unexpected EOF while looking for matching "'"`, while the same idiom at 30 lines worked all session.
Whatever the size threshold is (quoting, buffering, or the tool's own escaping) it is not
detectable from the script, and the failure blames a quote that is perfectly balanced.
**Rule:** write anything over ~100 lines to a `.py` file with the Write tool and run
`python <abs path>`. Costs one extra tool call and removes a whole class of unexplainable failure.
Related: a Dart `'$id.wav'` inside a *non-raw* Python string becomes `'\$id.wav'` and then never
matches the file: either use a raw string, or split the replacement so the `$` is not in it.

## A stale MTP session makes `CopyHere` a silent no-op (2026-08-20)
**Mechanism:** `Folder.CopyHere` over MTP is asynchronous and returns immediately with no status, no
handle and no exception. If the WPD session inside the long-running `explorer.exe` has gone stale
(the phone locked, or the USB mode dropped and came back) the call is simply discarded. The device
still enumerates perfectly: `Shell.Application` finds it, the store reports 43 GB free, the
`Download` folder lists its contents. Everything reads fine; only writes vanish.
**Incident:** six minutes of polling for a 53 MB APK that was never being written. Unlocking the
phone changed nothing. Replugging the cable fixed it and the same code copied in under 5 seconds.
**Rule:** never trust `CopyHere`: always poll the destination for the file afterwards, and when it
does not appear, **probe with a tiny file** before debugging anything else. A 5-byte text file that
also fails to land proves the fault is the transport, not the size, the path or the flags; a probe
that lands means the big copy is merely slow. Fix the transport by replugging the cable (which
rebuilds the WPD session), not by restarting Explorer. Two related traps already established: only
one of the two "G7 ThinQ" entries has children, and `.Size` on an MTP `FolderItem` returns 0: read
`GetDetailsOf($file, 2)` for the real size.

## A "no data" message that does not say *why* reads as "nothing was there" (2026-08-20)
**Mechanism:** the flight lookup asked live ADS-B feeds first and only fell back to history. A live
feed answers exactly one question (what is in the sky *right now*) so for a snap taken twenty
minutes ago it returns a list of aircraft the matcher correctly rejects, and the user is shown
"couldn't find anything". That sentence is true about the query and false about the world, and the
difference matters: one means "no aircraft was overhead", the other means "this app never looked".
**Incident:** Ben recorded at 14:49 with no wifi and retried at 14:57 with wifi. His conclusion was
that the app must be looking up the flight at "now" rather than at the time of the recording. It
was not: `snap.recordedAt` was threaded through correctly the whole way, but the message gave
him no way to tell those two possibilities apart, and the real cause (OpenSky credentials never
configured, so the only source that can see into the past was unavailable) was never mentioned.
**Rule:** branch on the question you can actually answer, and name the missing capability in the
message. Past snaps now skip the live query entirely and go straight to the retrospective source,
whose failure text says live feeds cannot see into the past and history needs an account. A
diagnostic the user can act on beats a diagnostic that is merely accurate.

## A default stored in the database is a default frozen on install day (2026-08-20)
**Mechanism:** `AppSettings.templateBody` defaults to `defaultBody` but is *written to storage* the
first time settings are saved. From then on the stored copy wins, forever. Every later change to
the default letter (a new token, a rewritten section) reaches new installs only. The handset
that has been used goes on mailing the old letter, which is precisely the handset whose output you
stop checking.
**Incident:** making the sound-level section degrade for an unmeasured recording replaced a
hard-coded table of `{laMax}`/`{laEq}`/`{ambient}` lines with a single `{measurementBlock}` token.
On a fresh install a silent microphone now produces "Sound level: not measured"; on Ben's handset
it would have produced "Maximum (LAmax, fast): not measured dB(A)" three times over, because his
stored letter still had the table in it.
**Rule:** when a user-editable default changes, keep the exact previous defaults in a list and
upgrade a stored value that matches one of them byte for byte. Matching the exact text is what
makes it safe: an edited letter matches nothing and is left alone, which is the point, because a
default that silently reapplies itself is not a default. The alternative (a version stamp) needs to
have been added before you needed it.

## Everything downstream of a sensor needs a "there was no reading" state (2026-08-20)
**Mechanism:** a failed measurement was an exception, so the capture threw and the snap was lost.
Turning it into `AcousticMetrics.unmeasured` fixed the capture and immediately created a subtler
bug: the fields are all zero, and every consumer printed them. The complaint then read
"Maximum (LAmax, fast): 0.0 dB(A) ... sampling at 0 kHz with IEC 61672 A-weighting": a formal
description of a measurement procedure that did not happen, which is far more damaging to a
complaint than an admitted gap.
**Rule:** a sentinel value is only half the fix. Add the predicate (`hasMeasurement`) *at the same
time*, and route every formatter through one helper that consults it, so the zero cannot leak into
output by being forgotten in one branch. Zero is a number; absence is not.

## A synchronous flag cleared before an awaited teardown is a lie for the duration of the await (2026-08-20)
**Mechanism:** `disarm()` set `_armed = false` and *then* awaited `recorder.stop()`. Between those
two statements the service reports "not armed" while the microphone stream is still very much alive.
An `arm()` arriving in that window therefore does the wrong thing twice over: it passes the
`if (_armed) return;` guard, and its `recorder.start()` hits `if (isRunning) return;` and does
nothing, because the old subscription has not been cancelled yet. The pending `stop()` then cancels
it. End state: `_armed == true`, microphone off, and nothing anywhere throws.
**Incident:** tapping the home-screen widget "frequently/always" produced an empty recording. That
path is exactly the race: the app is backgrounded (paused -> `disarm`), the widget is tapped, the
app resumes and calls `arm()` while the previous `stop()` is still unwinding. It was invisible in
tests because tests never interleave the two.
**Rule:** a boolean that mirrors the state of an async resource must not change before the resource
does. Either flip it *after* the await, or (better, and what was done here) keep the in-flight
transition in a field and have both `arm()` and `disarm()` await it before they look at the flag.
Serialising is worth more than ordering: it also makes arm-arm and disarm-disarm safe, which
ordering alone does not.

## A polling loop must distinguish "it stopped" from "it never started" (2026-08-20)
**Mechanism:** `awaitEventEnd()` was `while (isRunning && !_stopRequested && !_eventFull)`. Reading
it as "keep waiting while the stream is alive" is right for the case it was written for: a stream
that dies mid-recording has given you everything it is going to. But the same condition is false on
entry when the stream was never up, and the loop exits immediately, returning an empty window as if
the user had pressed STOP. One condition, two meanings, and the wrong one is silent.
**Incident:** the widget bug above. The empty window was reported to the user as "bad state: the
microphone recorded nothing" one millisecond after they pressed record.
**Rule:** when a loop guard doubles as an entry condition, latch the two apart explicitly (here a
`sawStream` flag: break only once the stream has been seen alive and then gone). And decide what the
never-started case should *do*: here it waits for the user's STOP and hands back an empty window,
because "no sound" must degrade to a complaint without a measurement, never to no complaint.

## Plain text has no bold, and that is usually the right answer anyway (2026-08-20)
**Mechanism:** the complaint is composed with `isHTML: false`, and the fallback path builds a
`mailto:` URI, which is plain text by specification. Making three figures bold therefore means
switching the body to HTML, keeping a second template in sync with the user-editable plain one,
HTML-escaping the address and free-text notes, and *still* sending plain text down the fallback.
The Unicode mathematical-bold alternative avoids all that but makes the numbers unsearchable,
unreadable to a screen reader, and liable to arrive as boxes at a council mail gateway: on a
formal complaint, looking broken costs more than looking flat.
**Rule:** when the ask is "make these stand out", check whether the real requirement is emphasis or
*findability*. Ben's was findability ("the human can scan the email to see if this is bonkers")
and an upper-case heading with three labelled lines at the top of the letter serves that better than
bold buried in the body, at no compatibility cost. Also: do not pad columns to align them. Mail
clients render plain text proportionally, so aligned columns arrive ragged.

## "Use the minimum, not the average" means L90, not the minimum (2026-08-20)
**Mechanism:** the complaint leads on peak-minus-background, so the background is subtracted from
the headline figure and any error in it lands in the number a council reads first. An *average*
background is wrong for the obvious reason: the aircraft is in it, and a mean over a recording
half-filled by a flyover sits a few dB below the flyover, so a 40 dB event reports as a 3 dB one.
But the *true minimum* is wrong too, and less obviously: it is one 125 ms block out of hundreds, so
a buffer underrun, a moment another app grabbed the microphone, or a lull between cars sets the
floor twenty to a hundred decibels below anything real, and the letter then claims a rise that is
self-evidently nonsense. A single bad block cannot be averaged away; it *is* the statistic.
**Incident:** Ben asked for "min = plausible background". Implemented literally as `min()`, the
first digital-silence block in a recording would have produced a rise of ~100 dB. The tenth
percentile (LA90, the level exceeded 90% of the time: the standard acoustic definition of
"background noise level") is what the instruction actually means: it is robust to a handful of bad
blocks and still finds the quiet street rather than the mean.
**Rule:** when a statistic feeds a number someone will argue with, prefer a percentile to an
extremum. Extrema have no averaging behind them, so every glitch in the pipeline is a candidate
answer. Corollary discovered here: taking the background from the *whole recording* rather than a
pre-roll captured before the button press also fixed record-on-open, which had left every normal
capture with no background at all: a recording that runs from before the aircraft until after it
has gone contains its own quiet street.

## Hedging a measurement is not the same as being honest about it (2026-08-20)
**Mechanism:** the letter used to carry "this handset has NOT been calibrated ... treat the absolute
values as indicative rather than as a formal measurement", plus an UNCALIBRATED caption on the
chart, plus a banner on the main screen, plus a calibration settings page. Each was individually
defensible. Together they told the recipient, before any figure, that the sender did not trust their
own evidence, which is an invitation to bin the complaint rather than read it.
**Incident:** Ben: "just remove all the uncalibrated crap". The replacement states the method once
and factually (handset, OS, sample rate, weighting) and then says what makes the comparison valid:
the peak and the background came off the same microphone in the same recording, so the gap between
them is like-for-like. Nothing is claimed that is not true, and nothing is conceded that was not
asked about.
**Rule:** honesty is stating what was done and what it means. Repeatedly apologising for the
limitations of the method is a different thing, and it costs credibility rather than earning it.
Say it once, in the place a reader checking the method would look.

## One MTP device can appear twice under `NameSpace(17)` (2026-08-20)
**Mechanism:** sideloading over MTP walks `Shell.Application`'s "This PC" namespace to find the
phone. An Android handset frequently enumerates as *two* entries with the same display name: one
real, one an empty shell (a stale or secondary MTP function). `@($pc.Items() | Where-Object { $_.Name
-eq 'G7 ThinQ' })[0]` picks whichever came first, and if that is the empty one, `.GetFolder` is null
and the script dies on "You cannot call a method on a null-valued expression".
**Incident:** cost twenty minutes chasing a phantom "phone not connected" while the phone was
plainly mounted in Explorer.
**Rule:** never index `[0]` into an MTP device match. Iterate every entry with the name and keep the
one whose `GetFolder.Items()` actually yields a child folder ("Internal shared storage"). The same
caution applies to `.Size` on MTP items, which returns 0: use `GetDetailsOf($file, 2)`.

## `Folder.CopyHere` is asynchronous and dies with the process (2026-08-20)
**Mechanism:** `Shell.Application`'s `CopyHere` queues a shell copy and returns immediately. The
transfer is driven by the calling process's shell COM apartment, so when a short-lived PowerShell
invocation exits a millisecond later, the copy is torn down before a byte moves: silently, with no
error and no partial file. Over MTP the file simply never appears.
**Incident:** a 53 MB APK "copied" to the handset's Download folder in one PowerShell call, then
polled for in a second call. Forty polls over two minutes found nothing. The copy had never started.
**Rule:** issue `CopyHere` and wait for the destination file to appear **in the same process**. Poll
`$dest.ParseName(name)` until it is non-null and `GetDetailsOf($file, 2)` returns a size (`.Size` is
0 on MTP items). Same caution as the two-device-entry gotcha above: Explorer's shell namespace is
convenient but every one of its affordances is asynchronous or lying.

## A diagnostic that is wrong more often than it is right is worse than none (2026-08-20)
**Mechanism:** the snap screen warned in red when the delivered sample rate drifted more than 2%
off the requested 48 kHz. The estimate is `samplesDelivered / wallClockSinceStreamStart`, and the
clock was stamped when `startStream()` *returned*: before the first sample arrives. Android's
AudioRecord cold start is 50-300 ms, so at the first check three seconds in, a 200 ms startup gap
reads as 6% of the audio missing: 44.8 kHz. The warning fires on a healthy microphone, every time,
and quietly stops firing as the recording lengthens and the fixed offset washes out.
**Incident:** Ben saw "Microphone is running at 45 kHz, not 48 kHz" and asked what the issue was.
There was none. Worse, 45 vs 48 kHz is acoustically irrelevant here: the A-weighting is redesigned
for whatever rate is actually measured, the error is identical in the peak and the background so it
cancels in the rise the letter leads on, and the real cliff is below ~32 kHz where the 12.2 kHz pole
pair collapses against Nyquist.
**Rule:** before shipping a warning, work out its false-positive rate on healthy hardware and what
the reader is supposed to *do* about it. This one had a false-positive rate near 100% and no action
attached. Deleted rather than fixed: the audience is largely pensioners who have opened the app
because a plane annoyed them, and a red line about kilohertz makes them close it. If a measurement
is only accurate after a settling period, do not expose it to the UI at all: expose it only where
the code can wait.

## An unknown template token prints itself, so deleting a field can print `{email}`

`ComplaintTemplate._substitute` resolves with `tokens[match.group(1)] ?? match.group(0)!`: an
unrecognised token is deliberately left standing as literal text, so a typo in a custom letter is
visible rather than silently swallowed. That is the right behaviour, and there is a test for it.

It also means **removing a field from the profile is not the same as removing its token**. Dropping
`email` from `ComplainantProfile` and deleting `'email'` from the token map would have been quietly
correct for every user on the stock letter, and would have posted a literal `{email}` in the sign-off
of every user who had ever edited theirs: the stored body is a string in the database, and nothing
migrates it.

The fix is to keep the token and resolve it to `''`. The rule generalises: **a token may be retired
from `tokenHelp`, but it can never be removed from the map** while any stored letter could still
contain it.

## `Geolocator.openAppSettings()` opens the app's whole settings page, microphone included

The microphone recovery flow needed a way to reach the OS permission screen, and `record` does not
offer one. Rather than add `permission_handler` for a single call, `LocationService.openAppSettings()`
wraps geolocator's: it opens the app entry, not a location-specific page, so it serves any
permission. Worth knowing before adding a second permissions plugin to this project.

## Android stops showing the permission dialog after two refusals, and never tells you

`record`'s `hasPermission()` both checks and prompts, which is convenient right up to the point
where the OS has decided the user means it. From the third call onwards the dialog does not appear
and the call simply returns false: indistinguishable, from Dart, from a user who tapped Deny again.

There is no API that reports "the system will no longer ask". So the recovery flow in
`_askForMic()` cannot branch on it: it explains, asks, and *if it is still refused afterwards*
offers the settings page. That costs one redundant dialog on the very first refusal and rescues
every refusal after it. Trying to be cleverer than this means guessing.

## Flutter ships a release build signed with the *debug* key, and that is a one-way door

`flutter create` writes this into `android/app/build.gradle.kts` and leaves it there:

```kotlin
release {
    // TODO: Add your own signing config for the release build.
    signingConfig = signingConfigs.getByName("debug")
}
```

`flutter build apk --release` then produces a perfectly working, installable, *debug-signed* APK.
Nothing warns you. It sideloads fine, it runs fine, and the TODO scrolls past in a file nobody opens
after the first week. v1.0.0 was tagged and about to be emailed to a community group before anyone
looked.

The reason it matters is not Play Protect's warning. It is that **Android refuses an update whose
signature differs from the installed copy**. There is no override, no migration and no re-signing an
installed app. Every person who installs a debug-signed build has to *uninstall* (losing every
recording in the app's private storage) before they can take a properly signed successor. The cost
of fixing it is ten minutes before distribution and infinite afterwards.

Two things that cost time while fixing it:

- `rootProject.file()` in `android/app/build.gradle.kts` resolves against **`android/`**, not the
  repo root. `storeFile=../flightpath-watch-release.jks` in `key.properties` therefore pointed one
  level above the repo. The error says only "Keystore file ... not found", with an absolute path that
  looks plausible enough to stare past.
- `keytool -printcert -jarfile app.apk` answers **"Not a signed jar file"** on a correctly signed
  APK. Modern APKs carry only an APK Signature Scheme v2/v3 block and no `META-INF` JAR signature,
  which is all `keytool` knows how to read. Verify with `apksigner verify --print-certs` from
  `$ANDROID_SDK/build-tools/<ver>/` instead, and note it needs `JAVA_HOME` set, which Android
  Studio's bundled JBR satisfies (`C:/Program Files/Android/Android Studio/jbr`).

The signing config is written to fall back to the debug key when `android/key.properties` is absent,
so a fresh clone and CI still build. That is deliberate, but it also means **the absence of the key
is silent**, exactly the failure this whole entry is about. Check `apksigner` output before shipping
any build to a human.

## MapLibre's `takeSnapshot` does not photograph the map you are looking at

Adding a map and then attaching a picture of it to the email looks like two lines of work:
`controller.takeSnapshot()`, write the bytes, done. It is not, and the way it fails is silent.

On **both** platforms the plugin hands the job to a separate renderer (Android's
`MapSnapshotter`, iOS's `MLNMapSnapshotter`) constructed from **the style URL and a camera
position, and nothing else**. It is not a screen capture and it is not connected to the live map
instance at all. Every GeoJSON source, every layer and every image you added at run time exists only
in the on-screen map's style object and is absent from the snapshotter's. You get back a perfectly
good picture of some streets with no aeroplane, no flight path and no marker on it, no error
anywhere, and if you only ever test with the map visible on screen it looks like it worked.

The consequence is architectural, not cosmetic: **anything that must appear in the emailed image has
to be painted in Dart**, which means owning the projection. Hence `MercatorView`, which reproduces
Web Mercator at MapLibre's own world size of `512 * 2^zoom` pixels (`util::tileSize` in the native
core, not 256, which is the figure most Mercator tutorials use and which puts everything at half
scale). Get that constant wrong and the overlay lands plausibly but consistently in the wrong street.

Three further traps in the same corner:

- **The returned image is not the size you asked for on iOS.** Android's snapshotter defaults to a
  pixel ratio of 1, so the PNG comes back at exactly the requested dimensions. iOS defaults to the
  screen scale, so the same request returns a 2× or 3× image. Do not assume either: decode the PNG,
  measure it, and derive the scale from `actualWidth / requestedWidth`. Everything downstream
  (stroke widths, type sizes, the projection's tile size) keys off that one number.
- **A snapshot taken before the tiles land is a grey rectangle.** Tiles are fetched lazily and
  `onStyleLoadedCallback` fires well before them. `await controller.waitUntilMapTilesAreLoaded()`
  first. And there is no "style failed" callback at all, so a style that never arrives has to be
  timed out or the user waits forever on a send that will not happen.
- **A platform view that is never laid out may never be created.** The hidden map that produces the
  basemap is scaled into a 1×1 pixel in the corner with a `FittedBox`, not hidden with `Offstage`,
  because an offstage platform view can sit there un-created indefinitely, and this one only has to
  get as far as loading its style.

Finally, on Android a data-driven `icon-rotate` reading a **null** property renders **nothing at
all** rather than falling back to zero. An aircraft that has not moved yet therefore vanishes from
the map entirely. Emit `0.0`, never null, for any property a style expression consumes.

## A Flutter plugin can demand a newer JDK than Flutter itself ships with

`maplibre_gl` 0.27.0 sets `JavaVersion.VERSION_21` and `JvmTarget.JVM_21` in its own
`build.gradle`. Flutter's tooling runs on Temurin 17, and the app is configured for 17 throughout,
so the release build died with:

```
Execution failed for task ':maplibre_gl:compileReleaseJavaWithJavac'
> error: invalid source release: 21
```

Nothing in the message names the plugin as the *source* of the 21: it reads like a misconfigured
project. The fix is to pull the one subproject back to 17 from the root `build.gradle.kts`, having
first checked that its sources actually use no feature past Java 8 (15 `.java` and 3 `.kt` files; no
records, no sealed types, no pattern-matching switch):

```kotlin
subprojects {
    if (name == "maplibre_gl") {
        pluginManager.withPlugin("com.android.library") {
            pluginManager.apply("org.jetbrains.kotlin.android")
        }
        afterEvaluate { /* set compileOptions and kotlin jvmTarget to 17 */ }
    }
}
```

Two ordering details that cost time:

- **Register the `afterEvaluate` outside `withPlugin`.** Callbacks run in the order they were
  queued, and AGP queues its own during plugin application. An `afterEvaluate` nested inside
  `pluginManager.withPlugin { }` is queued *after* AGP's and is overwritten by it.
- **This project has `android.builtInKotlin=false`**, so the Kotlin plugin must be applied to the
  subproject explicitly before its extension exists to configure. `extensions.findByType(...)`
  returning null is not an error here, which is why the `?.` matters: a plugin without Kotlin
  sources legitimately has no Kotlin extension.

