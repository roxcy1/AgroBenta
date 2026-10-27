import 'package:flutter/material.dart';

import '../core/theme/app_colors.dart';

/// Paints the AgroBenta scenery: a sky gradient, a soft sun, three clouds and
/// three receding bands of hills in the brand greens.
///
/// Kept as a painter rather than an image so nothing has to be added to
/// `pubspec.yaml`, and so it scales to any banner size without a raster asset.
/// Shared by the auth screens' scenic header and the Home hero banner, both of
/// which need the same landscape with no logo or scenery asset in the project.
class RollingHillsPainter extends CustomPainter {
  const RollingHillsPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final Rect bounds = Offset.zero & size;

    canvas.drawRect(
      bounds,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[AppColors.skyTop, AppColors.skyBottom],
        ).createShader(bounds),
    );

    canvas.drawCircle(
      Offset(size.width * 0.82, size.height * 0.20),
      size.shortestSide * 0.10,
      Paint()..color = Colors.white.withValues(alpha: 0.60),
    );

    _drawCloud(
      canvas,
      Offset(size.width * 0.20, size.height * 0.20),
      size.shortestSide * 0.10,
    );
    _drawCloud(
      canvas,
      Offset(size.width * 0.58, size.height * 0.12),
      size.shortestSide * 0.075,
    );
    _drawCloud(
      canvas,
      Offset(size.width * 0.40, size.height * 0.34),
      size.shortestSide * 0.06,
    );

    _drawHill(
      canvas,
      size,
      baseY: 0.66,
      amplitude: 0.10,
      color: AppColors.primaryLight,
    );
    _drawHill(
      canvas,
      size,
      baseY: 0.78,
      amplitude: 0.12,
      color: AppColors.primary,
    );
    _drawHill(
      canvas,
      size,
      baseY: 0.92,
      amplitude: 0.14,
      color: AppColors.primaryDark,
    );
  }

  void _drawCloud(Canvas canvas, Offset center, double radius) {
    final Paint paint = Paint()..color = Colors.white.withValues(alpha: 0.85);
    canvas.drawCircle(center, radius, paint);
    canvas.drawCircle(
      center + Offset(radius * 0.9, radius * 0.18),
      radius * 0.7,
      paint,
    );
    canvas.drawCircle(
      center + Offset(-radius * 0.9, radius * 0.22),
      radius * 0.6,
      paint,
    );
  }

  void _drawHill(
    Canvas canvas,
    Size size, {
    required double baseY,
    required double amplitude,
    required Color color,
  }) {
    final double y = size.height * baseY;
    final double a = size.height * amplitude;
    final Path path = Path()
      ..moveTo(0, y)
      ..quadraticBezierTo(size.width * 0.22, y - a, size.width * 0.48, y)
      ..quadraticBezierTo(size.width * 0.74, y + a * 0.5, size.width, y - a * 0.4)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();

    canvas.drawPath(path, Paint()..color = color);
  }

  @override
  bool shouldRepaint(covariant RollingHillsPainter oldDelegate) => false;
}
