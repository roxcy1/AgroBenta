import 'package:flutter/material.dart';

/// The bottom navigation glyphs of the approved mobile proposal.
///
/// The proposal draws its five destinations as thin, round-capped line icons
/// on a 24-unit grid, and a selected tab keeps the same outline in brand green
/// rather than switching to a filled glyph. Material's icon font has no set
/// that matches those shapes, so they are stroked here from the proposal's own
/// path data. No package is involved: this is a [CustomPainter] over
/// `dart:ui` paths.
enum NavGlyph { home, browse, messages, transactions, profile, listings }

/// One [NavGlyph], sized and coloured by the ambient [IconTheme] unless
/// overridden, so it drops into a `NavigationDestination` like an [Icon].
class NavLineIcon extends StatelessWidget {
  const NavLineIcon(this.glyph, {this.size, this.color, super.key});

  final NavGlyph glyph;

  /// Defaults to the ambient icon size, then 24.
  final double? size;

  /// Defaults to the ambient icon colour.
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final IconThemeData theme = IconTheme.of(context);
    final double side = size ?? theme.size ?? 24;
    return SizedBox.square(
      dimension: side,
      child: CustomPaint(
        painter: _NavGlyphPainter(
          glyph: glyph,
          color: color ?? theme.color ?? const Color(0xFF000000),
        ),
      ),
    );
  }
}

class _NavGlyphPainter extends CustomPainter {
  const _NavGlyphPainter({required this.glyph, required this.color});

  final NavGlyph glyph;
  final Color color;

  /// The proposal's grid: every path below is written in 24x24 units.
  static const double _grid = 24;

  /// The proposal's stroke width on that grid.
  static const double _stroke = 1.9;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / _grid, size.height / _grid);
    canvas.drawPath(
      _pathFor(glyph),
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = _stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  static Path _pathFor(NavGlyph glyph) {
    switch (glyph) {
      case NavGlyph.home:
        // A roof, the walls and a door.
        return Path()
          ..moveTo(3, 11)
          ..lineTo(12, 4)
          ..lineTo(21, 11)
          ..moveTo(5, 10)
          ..lineTo(5, 20)
          ..lineTo(19, 20)
          ..lineTo(19, 10)
          ..moveTo(10, 20)
          ..lineTo(10, 14)
          ..lineTo(14, 14)
          ..lineTo(14, 20);
      case NavGlyph.browse:
        // A magnifier.
        return Path()
          ..addOval(Rect.fromCircle(center: const Offset(11, 11), radius: 7))
          ..moveTo(20, 20)
          ..lineTo(16.4, 16.4);
      case NavGlyph.messages:
        // A round speech bubble with its tail at the lower left.
        return Path()
          ..moveTo(21, 12)
          ..arcToPoint(
            const Offset(9.4, 19.1),
            radius: const Radius.circular(8),
          )
          ..lineTo(4, 20)
          ..lineTo(5, 15.4)
          ..arcToPoint(
            const Offset(21, 12),
            radius: const Radius.circular(8),
            largeArc: true,
          )
          ..close();
      case NavGlyph.transactions:
        // Two arrows passing each other.
        return Path()
          ..moveTo(7, 4)
          ..lineTo(3, 8)
          ..lineTo(7, 12)
          ..moveTo(3, 8)
          ..lineTo(17, 8)
          ..moveTo(17, 20)
          ..lineTo(21, 16)
          ..lineTo(17, 12)
          ..moveTo(21, 16)
          ..lineTo(7, 16);
      case NavGlyph.profile:
        // A head and shoulders.
        return Path()
          ..addOval(Rect.fromCircle(center: const Offset(12, 8), radius: 4))
          ..moveTo(4, 21)
          ..cubicTo(5, 16.8, 8.2, 14.7, 12, 14.7)
          ..cubicTo(15.8, 14.7, 19, 16.8, 20, 21);
      case NavGlyph.listings:
        // A market stall: awning, walls and a doorway.
        return Path()
          ..moveTo(4, 9)
          ..lineTo(20, 9)
          ..lineTo(18.5, 4)
          ..lineTo(5.5, 4)
          ..close()
          ..moveTo(5, 9)
          ..lineTo(5, 20)
          ..lineTo(19, 20)
          ..lineTo(19, 9)
          ..moveTo(9, 20)
          ..lineTo(9, 14)
          ..lineTo(15, 14)
          ..lineTo(15, 20);
    }
  }

  @override
  bool shouldRepaint(_NavGlyphPainter oldDelegate) =>
      oldDelegate.glyph != glyph || oldDelegate.color != color;
}
