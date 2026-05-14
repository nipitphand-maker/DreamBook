import 'package:dreambook/core/models/models.dart';
import 'package:dreambook/core/theme/design_tokens.dart';
import 'package:flutter/material.dart';

/// Bar-sparkline showing feed times across today.
///
/// x-axis = hour of day (0–24 h window).
/// y-axis = oz per feed (proportional to bar height).
/// Breast feeds with no oz get half the max height.
class FeedSparkline extends StatelessWidget {
  const FeedSparkline({super.key, required this.feeds, this.height = 48});

  final List<Feed> feeds;
  final double height;

  @override
  Widget build(BuildContext context) {
    if (feeds.isEmpty) return SizedBox(height: height);
    return SizedBox(
      height: height,
      child: CustomPaint(
        painter: _SparklinePainter(
          feeds: feeds,
          color: AppColors.lavender700,
        ),
        child: const SizedBox.expand(),
      ),
    );
  }
}

class _SparklinePainter extends CustomPainter {
  _SparklinePainter({required this.feeds, required this.color});

  final List<Feed> feeds;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final maxOz = feeds
        .map((f) => f.oz ?? 2.0)
        .fold<double>(2.0, (a, b) => a > b ? a : b);

    final paint = Paint()
      ..color = color
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;

    final now = DateTime.now();
    final startOfDay = DateTime(now.year, now.month, now.day);
    const totalSeconds = 24 * 3600.0;

    for (final feed in feeds) {
      final sec = feed.startedAt
          .difference(startOfDay)
          .inSeconds
          .toDouble()
          .clamp(0, totalSeconds);
      final x = (sec / totalSeconds) * size.width;
      final oz = feed.oz ?? (maxOz * 0.5);
      final barH = (oz / maxOz) * size.height;
      canvas.drawLine(
        Offset(x, size.height),
        Offset(x, size.height - barH),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_SparklinePainter old) => old.feeds != feeds;
}
