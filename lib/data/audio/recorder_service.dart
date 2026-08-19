import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:record/record.dart';

import '../../core/constants.dart';
import 'a_weighting.dart';
import 'ring_buffer.dart';

/// A live A-weighted level reading for the on-screen meter.
class MeterReading {
  const MeterReading({required this.levelDb, required this.clipping});

  final double levelDb;
  final bool clipping;
}

/// Owns the microphone while the snap screen is open.
///
/// Keeps a rolling [PcmRingBuffer] so that pressing the button can reach
/// backwards in time, and publishes a smoothed level for the meter.
class RecorderService {
  RecorderService({AudioRecorder? recorder, double? calibrationOffsetDb})
      : _recorder = recorder ?? AudioRecorder(),
        calibrationOffsetDb =
            calibrationOffsetDb ?? CalibrationDefaults.fullScaleDbSpl,
        _buffer = PcmRingBuffer.forSeconds(
          AudioConfig.ringBufferSeconds,
          AudioConfig.sampleRate.toDouble(),
        ),
        _weighting = AWeighting(AudioConfig.sampleRate.toDouble());

  final AudioRecorder _recorder;
  final PcmRingBuffer _buffer;
  final AWeighting _weighting;

  StreamSubscription<Uint8List>? _subscription;
  final StreamController<MeterReading> _meter =
      StreamController<MeterReading>.broadcast();

  // Exponential (fast, 125 ms) mean-square for the live meter.
  double _runningMeanSquare = 0;
  bool _clipping = false;
  DateTime _lastEmit = DateTime.fromMillisecondsSinceEpoch(0);

  /// Wall-clock time corresponding to sample position 0 of the ring buffer.
  DateTime? _streamStart;

  bool get isRunning => _subscription != null;
  PcmRingBuffer get buffer => _buffer;
  Stream<MeterReading> get meterStream => _meter.stream;
  /// Only affects the on-screen meter; each snap is analysed with the offset
  /// in force at the time of the press.
  double calibrationOffsetDb;

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
          // different sensitivity would silently invalidate the calibration.
          manageBluetooth: false,
        ),
        iosConfig: IosRecordConfig(
          // Same reason — the default options allow Bluetooth routing.
          categoryOptions: <IosAudioCategoryOption>[],
        ),
      ),
    );

    _buffer.clear();
    _runningMeanSquare = 0;
    _weighting.reset();
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

  Future<void> dispose() async {
    await stop();
    await _meter.close();
    await _recorder.dispose();
  }

  void _onChunk(Uint8List bytes) {
    _buffer.addPcm16Bytes(bytes);

    const double tau = 0.125;
    final double alpha = 1 - math.exp(-1 / (AudioConfig.sampleRate * tau));
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
              ? calibrationOffsetDb - 200
              : 10 * math.log(_runningMeanSquare) / math.ln10 +
                  calibrationOffsetDb,
          clipping: _clipping,
        ),
      );
    }
  }

  /// Sample position in the ring buffer corresponding to wall-clock [time].
  ///
  /// Derived from the sample count rather than the clock, so it stays aligned
  /// with the audio even if chunk delivery is bursty.
  int samplePositionAt(DateTime time) {
    final DateTime? start = _streamStart;
    if (start == null) return 0;
    final int fromClock =
        (time.difference(start).inMicroseconds * AudioConfig.sampleRate / 1e6)
            .round();
    return math.min(fromClock, _buffer.totalWritten);
  }

  /// Extracts the analysis window around [pressTime], waiting for the post-roll
  /// to actually be recorded first.
  Future<Float64List> captureEventWindow(DateTime pressTime) async {
    final int postRollSamples =
        (AudioConfig.postRollSeconds * AudioConfig.sampleRate).round();
    final int pressPosition = samplePositionAt(pressTime);
    final int targetEnd = pressPosition + postRollSamples;

    while (_buffer.totalWritten < targetEnd && isRunning) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }

    final int preRollSamples =
        (AudioConfig.preRollSeconds * AudioConfig.sampleRate).round();
    final int windowSamples = preRollSamples + postRollSamples;
    final int end = math.min(targetEnd, _buffer.totalWritten);
    return _buffer.readEndingAt(end, windowSamples);
  }
}
