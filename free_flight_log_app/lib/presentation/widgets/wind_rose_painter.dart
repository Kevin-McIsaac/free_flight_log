import 'package:flutter/material.dart';
import 'dart:math';
import '../../services/logging_service.dart';

class WindRosePainter extends CustomPainter {
  final List<String> launchableDirections;
  final ThemeData theme;

  // 8 cardinal and intercardinal directions
  static const List<String> _allDirections = [
    'N', 'NE', 'E', 'SE', 'S', 'SW', 'W', 'NW'
  ];

  // Direction angles in degrees (North = 0°, clockwise)
  static const Map<String, double> _directionAngles = {
    'N': 0,
    'NE': 45,
    'E': 90,
    'SE': 135,
    'S': 180,
    'SW': 225,
    'W': 270,
    'NW': 315,
  };

  WindRosePainter({
    required this.launchableDirections,
    required this.theme,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 20; // Leave margin for labels

    LoggingService.debug('WindRosePainter painting with radius: $radius');
    LoggingService.debug('WindRosePainter received directions: $launchableDirections');

    // Draw background circle
    _drawBackground(canvas, center, radius);

    // Draw wind sectors
    _drawWindSectors(canvas, center, radius);

    // Draw compass ring and labels
    _drawCompassRing(canvas, center, radius);
    _drawDirectionLabels(canvas, center, radius);

    // Draw center point
    _drawCenterPoint(canvas, center);
  }

  void _drawBackground(Canvas canvas, Offset center, double radius) {
    final backgroundPaint = Paint()
      ..color = theme.colorScheme.surface
      ..style = PaintingStyle.fill;

    canvas.drawCircle(center, radius, backgroundPaint);
  }

  void _drawWindSectors(Canvas canvas, Offset center, double radius) {
    final sectorRadius = radius - 10;

    for (final direction in _allDirections) {
      final isLaunchable = launchableDirections.contains(direction);
      final angle = _directionAngles[direction]!;

      // Each sector spans 45 degrees (360° / 8 directions)
      final startAngle = _degreesToRadians(angle - 22.5);
      final sweepAngle = _degreesToRadians(45);

      final sectorPaint = Paint()
        ..color = isLaunchable
            ? Colors.green.withValues(alpha: 0.3)
            : Colors.grey.withValues(alpha: 0.1)
        ..style = PaintingStyle.fill;

      // Draw sector as a path
      final path = Path();
      path.moveTo(center.dx, center.dy);
      path.arcTo(
        Rect.fromCircle(center: center, radius: sectorRadius),
        startAngle,
        sweepAngle,
        false,
      );
      path.close();

      canvas.drawPath(path, sectorPaint);

      // Draw sector outline
      final outlinePaint = Paint()
        ..color = isLaunchable
            ? Colors.green.withValues(alpha: 0.6)
            : Colors.grey.withValues(alpha: 0.3)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1;

      canvas.drawPath(path, outlinePaint);
    }
  }

  void _drawCompassRing(Canvas canvas, Offset center, double radius) {
    final ringPaint = Paint()
      ..color = theme.colorScheme.outline
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;

    canvas.drawCircle(center, radius, ringPaint);
  }

  void _drawDirectionLabels(Canvas canvas, Offset center, double radius) {
    final labelRadius = radius + 15;

    for (final direction in _allDirections) {
      final angle = _directionAngles[direction]!;
      final isLaunchable = launchableDirections.contains(direction);

      // Calculate label position
      final radians = _degreesToRadians(angle - 90); // Subtract 90° to start from top
      final x = center.dx + labelRadius * cos(radians);
      final y = center.dy + labelRadius * sin(radians);

      // Create text painter
      final textPainter = TextPainter(
        text: TextSpan(
          text: direction,
          style: theme.textTheme.labelMedium?.copyWith(
            color: isLaunchable
                ? Colors.green.shade700
                : theme.colorScheme.onSurface.withValues(alpha: 0.7),
            fontWeight: isLaunchable ? FontWeight.bold : FontWeight.normal,
          ),
        ),
        textDirection: TextDirection.ltr,
      );

      textPainter.layout();

      // Center the text on the calculated position
      final offset = Offset(
        x - textPainter.width / 2,
        y - textPainter.height / 2,
      );

      textPainter.paint(canvas, offset);
    }
  }

  void _drawCenterPoint(Canvas canvas, Offset center) {
    final centerPaint = Paint()
      ..color = theme.colorScheme.primary
      ..style = PaintingStyle.fill;

    canvas.drawCircle(center, 4, centerPaint);
  }

  double _degreesToRadians(double degrees) {
    return degrees * pi / 180;
  }

  @override
  bool shouldRepaint(WindRosePainter oldDelegate) {
    return launchableDirections != oldDelegate.launchableDirections ||
           theme != oldDelegate.theme;
  }
}