import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:record/record.dart';

import 'package:noise_alert/mic/config.dart';
import 'package:noise_alert/mic/a_weighting.dart';
import 'package:noise_alert/mic/ring_buffer.dart';

/// A live A-weighted level reading for the on-screen meter.
class MeterReading {
  const MeterReading({required this.levelDb, required this.clipping});

  final double levelDb;
  final bool clipping;
}

/// Owns the microphone while the record screen is open.
///
/// The event itself starts at the button press. The rolling [PcmRingBuffer] is
/// kept for one other purpose: a snapshot of the street taken at the instant of
/// the press, which is the background the letter compares the event against.
/// Also publishes a smoothed level for the meter.
class RecorderService {
  RecorderService({AudioRecorder? recorder})
      : _recorder = recorder ?? AudioRecorder(),
        _buffer = PcmRingBuffer.forSeconds(
          AudioConfig.ringBufferSeconds,
          AudioConfig.sampleRate.toDouble(),
        ),
        _weighting = AWeighting(AudioConfig.sampleRate.toDouble());

  final AudioRecorder _recorder;
  final PcmRingBuffer _buffer;
  AWeighting _weighting;

  StreamSubscription<Uint8List>? _subscription;
  final StreamController<MeterReading> _meter =
      StreamController<MeterReading>.broadcast();

  // Exponential (fast, 125 ms) mean-square for the live meter.
  double _runningMeanSquare = 0;
  bool _clipping = false;
  DateTime _lastEmit = DateTime.fromMillisecondsSinceEpoch(0);

  /// Wall-clock time corresponding to sample position 0 of the ring buffer.
  DateTime? _streamStart;

  /// Set by [stopEventCapture]; ends the recording at the next poll.
  bool _stopRequested = false;

  /// The event being recorded, allocated at the press and sized for
  /// [AudioConfig.maxEventSeconds].
  ///
  /// Allocated whole rather than grown: a doubling buffer would need 1.5x the
  /// final size live at the moment it resizes, and a chunk list would need 2x
  /// to concatenate. One fixed allocation at the press has no such spike, and
  /// the finished recording is handed out as a view onto it.
  Int16List? _event;
  int _eventLength = 0;
  bool _eventFull = false;

  /// The background recorded before the press, snapshotted out of the ring the
  /// instant the button was hit. Not part of the event.
  Float64List _ambient = Float64List(0);

  /// Sample rate in force when the event started. Frozen so the length of the
  /// recording and the pitch of the saved clip cannot disagree.
  double _eventRate = AudioConfig.sampleRate.toDouble();

  bool get isRunning => _subscription != null;


  /// Seconds recorded so far in the current event, for the on-screen clock.
  double get eventSeconds => _eventLength / _eventRate;
  PcmRingBuffer get buffer => _buffer;
  Stream<MeterReading> get meterStream => _meter.stream;

  /// Only affects the on-screen meter; each snap is analysed with the offset
  /// in force at the time of the press.

  Future<bool> hasPermission() => _recorder.hasPermission();

  Future<void> start() async {
    if (isRunning) return;
    if (!await _recorder.hasPermission()) {
      throw StateError('Microphone permission not granted');
    }

    final Stream<Uint8List> stream = await _recorder.startStream(
      const RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: AudioConfig.sampleRate,
        numChannels: 1,
        // All three off. Automatic gain control is the enemy of a level
        // measurement: it quietly turns the loud thing we are trying to measure
        // back down again, and the result is neither the true level nor a
        // stable one.
        autoGain: false,
        echoCancel: false,
        noiseSuppress: false,
        androidConfig: AndroidRecordConfig(
          // UNPROCESSED bypasses the platform's signal-conditioning chain.
          // Devices that do not advertise support fall back to something close
          // to VOICE_RECOGNITION, which is still far flatter than the default.
          audioSource: AndroidAudioSource.unprocessed,
          // Never route to a Bluetooth headset: a different microphone with a
          // different sensitivity would silently shift the whole scale.
          manageBluetooth: false,
        ),
        iosConfig: IosRecordConfig(
          // Same reason: the default options allow Bluetooth routing.
          categoryOptions: <IosAudioCategoryOption>[],
        ),
      ),
    );

    _buffer.clear();
    _runningMeanSquare = 0;
    _meterRate = AudioConfig.sampleRate.toDouble();
    _weightingRetuned = false;
    _weighting = AWeighting(_meterRate);
    _streamStart = DateTime.now();

    _subscription = stream.listen(
      _onChunk,
      onError: (Object e, StackTrace s) {
        _meter.addError(e, s);
      },
    );
  }

  Future<void> stop() async {
    await _subscription?.cancel();
    _subscription = null;
    if (await _recorder.isRecording()) {
      await _recorder.stop();
    }
  }

  /// The A-weighting filter is designed for one specific sample rate, so it has
  /// to be rebuilt once we know what the hardware really gave us. Done once and
  /// not per chunk: rebuilding resets the filter state, which would notch the
  /// meter every time.
  double _meterRate = AudioConfig.sampleRate.toDouble();
  bool _weightingRetuned = false;

  void _retuneWeightingIfNeeded() {
    if (_weightingRetuned) return;
    final DateTime? start = _streamStart;
    if (start == null) return;
    if (DateTime.now().difference(start).inMicroseconds < _rateSettleMicros) {
      return;
    }
    _weightingRetuned = true;
    final double rate = effectiveSampleRate;
    if ((rate - _meterRate).abs() < 1) return;
    _meterRate = rate;
    _weighting = AWeighting(rate);
  }

  Future<void> dispose() async {
    await stop();
    await _meter.close();
    await _recorder.dispose();
  }

  void _onChunk(Uint8List bytes) {
    _buffer.addPcm16Bytes(bytes);
    _appendToEvent(bytes);
    _retuneWeightingIfNeeded();

    const double tau = 0.125;
    final double alpha = 1 - math.exp(-1 / (_meterRate * tau));
    final int count = bytes.lengthInBytes ~/ 2;
    final ByteData view = ByteData.sublistView(bytes, 0, count * 2);

    bool clipped = false;
    for (int i = 0; i < count; i++) {
      final int raw = view.getInt16(i * 2, Endian.little);
      if (raw >= 32700 || raw <= -32700) clipped = true;
      final double weighted = _weighting.process(raw / 32768.0);
      _runningMeanSquare += alpha * (weighted * weighted - _runningMeanSquare);
    }
    _clipping = clipped;

    final DateTime now = DateTime.now();
    if (now.difference(_lastEmit).inMilliseconds >=
        AudioConfig.meterIntervalMs) {
      _lastEmit = now;
      _meter.add(
        MeterReading(
          levelDb: _runningMeanSquare <= 0
              ? LevelReference.fullScaleDbSpl - 200
              : 10 * math.log(_runningMeanSquare) / math.ln10 +
                  LevelReference.fullScaleDbSpl,
          clipping: _clipping,
        ),
      );
    }
  }

  /// Samples per second the microphone is *actually* delivering.
  ///
  /// [AudioConfig.sampleRate] is what we asked for, not necessarily what we
  /// got. Android is free to hand back a different rate, commonly 44.1 kHz,
  /// and as little as 16 kHz for `unprocessed` on hardware that does not truly
  /// support it, and the plugin reports success either way. Measuring it is
  /// the only way to know, and everything downstream (window lengths, the
  /// A-weighting design, the WAV header on the clip) has to use the real figure
  /// or it describes audio that does not exist.
  ///
  /// Falls back to the configured rate until there is enough of the stream to
  /// divide by; a fraction of a second of delivery jitter would otherwise read
  /// as a wildly wrong rate.
  double get effectiveSampleRate {
    final DateTime? start = _streamStart;
    if (start == null) return AudioConfig.sampleRate.toDouble();
    final int elapsedUs = DateTime.now().difference(start).inMicroseconds;
    if (elapsedUs < _rateSettleMicros || _buffer.totalWritten <= 0) {
      return AudioConfig.sampleRate.toDouble();
    }
    return _buffer.totalWritten * 1e6 / elapsedUs;
  }

  static const int _rateSettleMicros = 2000000;

  /// Starts recording an event at this instant.
  ///
  /// Called the moment RECORD is pressed, and deliberately synchronous: the
  /// first sample of the event has to be the first sample after the press, so
  /// there is nothing here that can be awaited in between.
  ///
  /// The pre-roll is not part of the event. It is snapshotted out of the ring
  /// here and used for one thing only: the background level the letter
  /// compares the event against.
  void startEventCapture() {
    _stopRequested = false;
    _eventFull = false;
    _eventLength = 0;
    _eventRate = effectiveSampleRate;

    final int end = _buffer.totalWritten;
    final int wanted = (AudioConfig.preRollSeconds * _eventRate).round();
    // Only what was genuinely recorded. The ring pads un-recorded history with
    // zeroes, which is right for the ring and wrong for a background level:
    // digital silence is not quiet, it is absent, and an L90 taken over it
    // would sit tens of dB below anything real and inflate the quoted rise.
    final int available = math.min(end, _buffer.availableSamples);
    final int take = math.min(wanted, available);
    _ambient = take > 0 ? _buffer.readEndingAt(end, take) : Float64List(0);

    // Ten percent over the cap, so a microphone delivering slightly faster than
    // it claimed does not end the recording before the user does.
    _event = Int16List(
      (AudioConfig.maxEventSeconds * _eventRate * 1.1).round(),
    );
  }

  /// Ends the recording. The user's STOP, and nothing else.
  void stopEventCapture() => _stopRequested = true;

  void _appendToEvent(Uint8List bytes) {
    final Int16List? event = _event;
    if (event == null || _eventFull) return;

    final int count = bytes.lengthInBytes ~/ 2;
    final ByteData view = ByteData.sublistView(bytes, 0, count * 2);
    final int room = event.length - _eventLength;
    final int take = math.min(count, room);
    for (int i = 0; i < take; i++) {
      event[_eventLength + i] = view.getInt16(i * 2, Endian.little);
    }
    _eventLength += take;
    if (take < count || _eventLength >= event.length) _eventFull = true;
  }

  /// Waits for STOP and returns everything recorded since the press.
  ///
  /// Polled on a wall clock rather than counting samples: if the stream stalls
  /// outright, a sample count never arrives and the capture never ends, whereas
  /// a poll notices the stream dying and gives back what there is.
  ///
  /// The distinction between a stream that died and one that never started is
  /// the whole of this method's subtlety. A stream that dies mid-recording has
  /// given us everything it is going to, so the capture ends. A stream that was
  /// never running when the event opened must NOT end it: the recording would
  /// finish in the same millisecond it began, and the user, who pressed a
  /// button precisely because an aircraft was overhead, would be thrown to
  /// the review screen before they had let go of the phone. In that case we
  /// wait for their STOP like any other recording and hand back an empty
  /// window, which downstream turns into a complaint with no sound rather than
  /// into no complaint at all.
  Future<EventWindow> awaitEventEnd() async {
    bool sawStream = isRunning;
    while (!_stopRequested && !_eventFull) {
      if (isRunning) {
        sawStream = true;
      } else if (sawStream) {
        break;
      }
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }

    final Int16List? event = _event;
    final int length = _eventLength;
    final bool truncated = _eventFull;
    _event = null;
    _eventLength = 0;
    _eventFull = false;

    if (event == null || length <= 0) return EventWindow.empty();

    return EventWindow(
      samples: Int16List.sublistView(event, 0, length),
      ambient: _ambient,
      sampleRate: _eventRate,
      truncated: truncated,
    );
  }
}

/// The audio for one event, plus the background recorded before it.
///
/// The two are separate buffers, not two halves of one: the event starts at the
/// button press, and the background is whatever the microphone had already
/// heard. Only the background may be used for the ambient level, and how much
/// of it there was decides whether an ambient level can be quoted at all.
class EventWindow {
  const EventWindow({
    required this.samples,
    required this.ambient,
    required this.sampleRate,
    this.truncated = false,
  });

  EventWindow.empty()
      : samples = _noSamples,
        ambient = _noAmbient,
        sampleRate = 1,
        truncated = false;

  static final Int16List _noSamples = Int16List(0);
  static final Float64List _noAmbient = Float64List(0);

  /// Everything recorded from the press until STOP, as it arrived.
  final Int16List samples;

  /// Normalised background from before the press. Empty when there was none.
  final Float64List ambient;

  final double sampleRate;

  /// The recording hit [AudioConfig.maxEventSeconds] and was ended for the
  /// user. The measurement is still valid, it is just not the whole flyover.
  final bool truncated;

  double get ambientSeconds => ambient.length / sampleRate;
  bool get isEmpty => samples.isEmpty;
}
