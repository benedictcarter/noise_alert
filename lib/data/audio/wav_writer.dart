import 'dart:io';
import 'dart:typed_data';

import 'biquad.dart';

/// Writes mono 16-bit PCM WAV files.
///
/// Clips are decimated to [clipSampleRate] before writing. Aircraft noise is
/// overwhelmingly below 4 kHz, so 16 kHz loses nothing audible while cutting
/// the email attachment from ~960 kB to ~320 kB for a 10 s clip, which matters
/// when the recipient is a council mailbox with an attachment size limit.
class WavWriter {
  const WavWriter({this.clipSampleRate = 16000});

  final int clipSampleRate;

  /// Writes [samples] (normalised -1..1, at [sourceSampleRate]) to [path].
  Future<File> write({
    required String path,
    required Float64List samples,
    required double sourceSampleRate,
  }) async {
    final int factor = (sourceSampleRate / clipSampleRate).round();
    final Int16List pcm = factor > 1
        ? _decimate(samples, sourceSampleRate, factor)
        : _toPcm16(samples);
    final int outRate = factor > 1
        ? (sourceSampleRate / factor).round()
        : sourceSampleRate.round();

    final File file = File(path);
    await file.parent.create(recursive: true);
    await file.writeAsBytes(_wavBytes(pcm, outRate), flush: true);
    return file;
  }

  Int16List _toPcm16(Float64List samples) {
    final Int16List out = Int16List(samples.length);
    for (int i = 0; i < samples.length; i++) {
      out[i] = _clampToInt16(samples[i]);
    }
    return out;
  }

  Int16List _decimate(
      Float64List samples, double sourceSampleRate, int factor) {
    final double cutoff = clipSampleRate / 2 * 0.9;
    // Two cascaded Butterworth sections: ~24 dB/octave, enough to keep
    // aliasing below the noise floor for this bandwidth ratio.
    final BiquadCascade antiAlias = BiquadCascade(<Biquad>[
      lowPassBiquad(cutoffHz: cutoff, sampleRate: sourceSampleRate),
      lowPassBiquad(cutoffHz: cutoff, sampleRate: sourceSampleRate),
    ]);

    final Int16List out = Int16List(samples.length ~/ factor);
    int w = 0;
    for (int i = 0; i < samples.length; i++) {
      final double y = antiAlias.process(samples[i]);
      if (i % factor == 0 && w < out.length) {
        out[w++] = _clampToInt16(y);
      }
    }
    return out;
  }

  static int _clampToInt16(double v) {
    final int s = (v * 32767).round();
    if (s > 32767) return 32767;
    if (s < -32768) return -32768;
    return s;
  }

  Uint8List _wavBytes(Int16List pcm, int sampleRate) {
    const int channels = 1;
    const int bitsPerSample = 16;
    final int dataBytes = pcm.length * 2;
    final int byteRate = sampleRate * channels * bitsPerSample ~/ 8;
    final int blockAlign = channels * bitsPerSample ~/ 8;

    final BytesBuilder builder = BytesBuilder();
    void ascii(String s) => builder.add(s.codeUnits);
    void u32(int v) => builder
        .add(Uint8List(4)..buffer.asByteData().setUint32(0, v, Endian.little));
    void u16(int v) => builder
        .add(Uint8List(2)..buffer.asByteData().setUint16(0, v, Endian.little));

    ascii('RIFF');
    u32(36 + dataBytes);
    ascii('WAVE');
    ascii('fmt ');
    u32(16);
    u16(1); // PCM
    u16(channels);
    u32(sampleRate);
    u32(byteRate);
    u16(blockAlign);
    u16(bitsPerSample);
    ascii('data');
    u32(dataBytes);

    final Uint8List pcmBytes = Uint8List(dataBytes);
    final ByteData view = ByteData.sublistView(pcmBytes);
    for (int i = 0; i < pcm.length; i++) {
      view.setInt16(i * 2, pcm[i], Endian.little);
    }
    builder.add(pcmBytes);

    return builder.toBytes();
  }
}
