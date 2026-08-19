import 'package:flutter/material.dart';

import '../../data/audio/recorder_service.dart';

/// Big live A-weighted level, with a coarse scale underneath.
///
/// The scale runs 30–110 dB(A): below 30 is a very quiet bedroom and above 110
/// the handset is almost certainly clipping, so nothing outside that range is
/// worth the pixels.
class LevelMeter extends StatelessWidget {
  const LevelMeter({super.key, required this.reading, required this.running});

  final MeterReading? reading;
  final bool running;

  static const double _min = 30;
  static const double _max = 110;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final double? level = reading?.levelDb;
    final bool clipping = reading?.clipping ?? false;
    final double fraction =
        level == null ? 0 : ((level - _min) / (_max - _min)).clamp(0.0, 1.0);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(
          !running
              ? '—'
              : level == null
                  ? '…'
                  : level.toStringAsFixed(0),
          style: theme.textTheme.displayLarge?.copyWith(
            fontWeight: FontWeight.w300,
            fontSize: 110,
            height: 1,
            color: clipping ? theme.colorScheme.error : null,
          ),
        ),
        Text('dB(A) fast', style: theme.textTheme.titleMedium),
        const SizedBox(height: 24),
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: LinearProgressIndicator(
            value: fraction,
            minHeight: 14,
            backgroundColor: theme.colorScheme.surfaceContainerHighest,
            color:
                clipping ? theme.colorScheme.error : theme.colorScheme.primary,
          ),
        ),
        const SizedBox(height: 6),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: <Widget>[
            Text('${_min.round()}', style: theme.textTheme.bodySmall),
            Text('${_max.round()}', style: theme.textTheme.bodySmall),
          ],
        ),
        if (clipping)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(
              'Microphone at maximum — the true level is higher than shown.',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.error),
              textAlign: TextAlign.center,
            ),
          ),
      ],
    );
  }
}
