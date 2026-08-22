import 'package:flutter/material.dart';

import 'package:noise_alert/mic/recorder.dart';

/// The live A-weighted level, as a bare number laid over the trace.
///
/// This was once a 110-point number, a progress bar and a 30-110 scale stacked
/// above the chart: three ways of saying the same thing, taking half the screen
/// to say it. The chart underneath already plots magnitude against time and
/// carries its own decibel axis, so the bar and the scale were the drawing's
/// job done twice, worse. What is left is the one thing a trace reads badly:
/// the number, right now, legible at arm's length while an aeroplane is
/// overhead.
///
/// No unit beside it and no plate behind it. The unit is written down the
/// chart's own axis a centimetre away, and on the one screen whose entire job
/// is "is it loud", a person holding the phone under an aeroplane is reading
/// the number and nothing else. The letter is where dB(A) has to be spelled
/// out; this is not the letter.
///
/// It sits top-centre, which on a fixed 30-110 dB axis is the 100+ region and
/// therefore empty except on a recording that is clipping, and a clipping
/// reading turns red, which is the one case where the trace behind it is
/// telling the same story anyway.
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
      crossAxisAlignment: CrossAxisAlignment.center,
      children: <Widget>[
        Text(
          !running
              ? '-'
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
        if (clipping)
          Text(
            'At maximum. The true level is higher.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.error),
          ),
      ],
    );
  }
}
