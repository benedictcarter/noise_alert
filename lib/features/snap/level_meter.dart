import 'package:flutter/material.dart';

import '../../data/audio/recorder_service.dart';

/// The live A-weighted level, sized and shaped to sit on top of the trace.
///
/// This was once a 110-point number, a progress bar and a 30–110 scale stacked
/// above the chart: three ways of saying the same thing, taking half the screen
/// to say it. The chart underneath already plots magnitude against time and
/// carries its own decibel axis, so the bar and the scale were the drawing's
/// job done twice, worse. What is left is the one thing a trace reads badly —
/// the number, right now, legible at arm's length while an aeroplane is
/// overhead.
///
/// Drawn on its own translucent plate rather than straight onto the chart. It
/// sits in the top-left corner, which on a fixed 30–110 dB axis is the 100+
/// region and therefore empty on all but a clipping recording — but "almost
/// always empty" is not "always", and a number that becomes unreadable exactly
/// when the aircraft is loudest would be the wrong number to lose.
class LevelMeter extends StatelessWidget {
  const LevelMeter({super.key, required this.reading, required this.running});

  final MeterReading? reading;
  final bool running;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final double? level = reading?.levelDb;
    final bool clipping = reading?.clipping ?? false;
    final Color? colour = clipping ? theme.colorScheme.error : null;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Container(
          padding: const EdgeInsets.fromLTRB(10, 2, 10, 4),
          decoration: BoxDecoration(
            color: theme.colorScheme.surface.withValues(alpha: 0.78),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: <Widget>[
              Text(
                !running
                    ? '—'
                    : level == null
                        ? '…'
                        : level.toStringAsFixed(0),
                style: theme.textTheme.displayMedium?.copyWith(
                  fontWeight: FontWeight.w300,
                  fontSize: 56,
                  height: 1,
                  color: colour,
                ),
              ),
              const SizedBox(width: 6),
              Padding(
                padding: const EdgeInsets.only(bottom: 7),
                child: Text(
                  'dB(A)',
                  style: theme.textTheme.titleSmall?.copyWith(color: colour),
                ),
              ),
            ],
          ),
        ),
        if (clipping)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: theme.colorScheme.surface.withValues(alpha: 0.78),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                child: Text(
                  'At maximum — the true level is higher.',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.error),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
