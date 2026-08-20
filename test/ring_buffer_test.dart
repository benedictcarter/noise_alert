import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:noise_alert/data/audio/ring_buffer.dart';

/// Little-endian PCM16 bytes for the given sample values.
Uint8List _pcm(List<int> values) {
  final ByteData data = ByteData(values.length * 2);
  for (int i = 0; i < values.length; i++) {
    data.setInt16(i * 2, values[i], Endian.little);
  }
  return data.buffer.asUint8List();
}

void main() {
  test('reads back what was written, normalised to ±1', () {
    final PcmRingBuffer buffer = PcmRingBuffer(capacitySamples: 10);
    buffer.addPcm16Bytes(_pcm(<int>[0, 16384, -16384, 32767]));

    expect(buffer.totalWritten, 4);
    final Float64List out = buffer.readLatest(4);
    expect(out[0], closeTo(0, 1e-9));
    expect(out[1], closeTo(0.5, 1e-4));
    expect(out[2], closeTo(-0.5, 1e-4));
    expect(out[3], closeTo(1.0, 1e-4));
  });

  test('wraps, keeping the most recent samples', () {
    final PcmRingBuffer buffer = PcmRingBuffer(capacitySamples: 4);
    buffer.addPcm16Bytes(_pcm(<int>[1000, 2000, 3000, 4000, 5000, 6000]));

    expect(buffer.totalWritten, 6);
    expect(buffer.availableSamples, 4);
    expect(buffer.isFull, isTrue);

    final Float64List out = buffer.readLatest(4);
    // 1000 and 2000 have been overwritten; 3000..6000 survive in order.
    expect(out[0] * 32768, closeTo(3000, 1));
    expect(out[3] * 32768, closeTo(6000, 1));
  });

  test('reading a window that ends in the past picks the right slice', () {
    // This is what a button press does: reach backwards from a known sample
    // position rather than from "now".
    final PcmRingBuffer buffer = PcmRingBuffer(capacitySamples: 100);
    buffer.addPcm16Bytes(_pcm(List<int>.generate(50, (int i) => i * 100)));

    final Float64List out = buffer.readEndingAt(30, 10);
    expect(out.length, 10);
    expect(out.first * 32768, closeTo(2000, 1)); // sample 20
    expect(out.last * 32768, closeTo(2900, 1)); // sample 29
  });

  test('history that was never recorded comes back as silence, not garbage',
      () {
    // Pressing the button five seconds after opening the screen must not
    // fabricate a pre-roll out of whatever was in memory.
    final PcmRingBuffer buffer = PcmRingBuffer(capacitySamples: 100);
    buffer.addPcm16Bytes(_pcm(<int>[5000, 5000, 5000]));

    final Float64List out = buffer.readEndingAt(3, 10);
    expect(out.length, 10);
    for (int i = 0; i < 7; i++) {
      expect(out[i], 0, reason: 'sample $i predates the recording');
    }
    expect(out[9] * 32768, closeTo(5000, 1));
  });

  test('clear resets the timeline', () {
    final PcmRingBuffer buffer = PcmRingBuffer(capacitySamples: 8);
    buffer.addPcm16Bytes(_pcm(<int>[1, 2, 3]));
    buffer.clear();

    expect(buffer.totalWritten, 0);
    expect(buffer.availableSamples, 0);
  });
}
