import 'package:flutter_test/flutter_test.dart';
import 'package:noise_alert/features/chart/level_chart.dart';

void main() {
  // The user drags a marker along the trace to say when the flyover was at its
  // worst. Getting this mapping wrong does not throw and does not look wrong on
  // screen -- it just quietly puts a different time in the letter than the one
  // the finger was over.
  group('turning a horizontal position into a time', () {
    const double width = 334; // 300 px of plot after the axis gutter.
    const double total = 60;

    test('the left edge of the plot is zero, not the left edge of the widget',
        () {
      expect(
        LevelChartPainter.secondsAt(LevelChartPainter.axisGutter, width, total),
        0,
      );
      // The gutter holds the dB labels; a press there is still the start.
      expect(LevelChartPainter.secondsAt(0, width, total), 0);
    });

    test('the right edge is the end of the recording', () {
      expect(LevelChartPainter.secondsAt(width, width, total), total);
    });

    test('the middle of the plot is the middle of the recording', () {
      final double mid =
          LevelChartPainter.axisGutter + (width - LevelChartPainter.axisGutter) / 2;
      expect(LevelChartPainter.secondsAt(mid, width, total), closeTo(30, 0.01));
    });

    test('a drag past either end clamps instead of running off the trace', () {
      expect(LevelChartPainter.secondsAt(-500, width, total), 0);
      expect(LevelChartPainter.secondsAt(9999, width, total), total);
    });

    test('a zero-width or zero-length chart is zero rather than NaN', () {
      // Reachable during the first layout pass, and a NaN here would be stored
      // as the marked moment.
      expect(LevelChartPainter.secondsAt(10, 0, total), 0);
      expect(LevelChartPainter.secondsAt(10, width, 0), 0);
    });

    test('with the axes hidden the plot starts at the widget edge', () {
      expect(LevelChartPainter.secondsAt(0, width, total, showAxes: false), 0);
      expect(
        LevelChartPainter.secondsAt(width / 2, width, total, showAxes: false),
        closeTo(30, 0.01),
      );
    });
  });
}
