import 'dart:math' as math;
import 'dart:typed_data';

/// Fixed-capacity circular buffer of PCM16 samples.
///
/// The microphone runs continuously while the snap screen is open so that a
/// press captures the *approach* of the aircraft, not just whatever is left of
/// it. Without pre-roll the loudest part of a low overflight is usually already
/// gone by the time a human reacts to it.
class PcmRingBuffer {
  PcmRingBuffer({required this.capacitySamples})
      : _buffer = Int16List(capacitySamples);

  factory PcmRingBuffer.forSeconds(double seconds, double sampleRate) =>
      PcmRingBuffer(capacitySamples: (seconds * sampleRate).round());

  final int capacitySamples;
  final Int16List _buffer;

  int _writeIndex = 0;

  /// Total samples ever written; also the timeline position of the write head.
  int _totalWritten = 0;

  int get totalWritten => _totalWritten;
  int get availableSamples => math.min(_totalWritten, capacitySamples);
  bool get isFull => _totalWritten >= capacitySamples;

  void clear() {
    _writeIndex = 0;
    _totalWritten = 0;
  }

  void addPcm16Bytes(Uint8List bytes) {
    final int count = bytes.lengthInBytes ~/ 2;
    final ByteData view = ByteData.sublistView(bytes, 0, count * 2);
    for (int i = 0; i < count; i++) {
      _buffer[_writeIndex] = view.getInt16(i * 2, Endian.little);
      _writeIndex = (_writeIndex + 1) % capacitySamples;
      _totalWritten++;
    }
  }

  /// Reads [count] samples ending at absolute timeline position [endPosition]
  /// (exclusive). Positions older than the buffer holds are returned as zeros,
  /// so a snap taken before the buffer filled still yields a valid window.
  Float64List readEndingAt(int endPosition, int count) {
    final Float64List out = Float64List(count);
    final int oldestAvailable = math.max(0, _totalWritten - capacitySamples);
    for (int i = 0; i < count; i++) {
      final int pos = endPosition - count + i;
      if (pos < oldestAvailable || pos >= _totalWritten) continue;
      final int idx = pos % capacitySamples;
      out[i] = _buffer[idx] / 32768.0;
    }
    return out;
  }

  /// The most recent [count] samples.
  Float64List readLatest(int count) => readEndingAt(_totalWritten, count);
}
