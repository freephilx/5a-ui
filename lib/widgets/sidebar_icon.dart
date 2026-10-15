import 'package:flutter/material.dart';

// Rounded, consistently weighted navigation symbols on a 24 dp grid.
enum SidebarSymbol { overview, server, cloud, settings, pane }

class SidebarIcon extends StatelessWidget {
  const SidebarIcon({super.key, required this.symbol, this.fill = 0});

  final SidebarSymbol symbol;
  final double fill;

  @override
  Widget build(BuildContext context) => CustomPaint(
    size: const Size.square(24),
    painter: _SidebarIconPainter(
      symbol,
      fill,
      Theme.of(context).colorScheme.onSurfaceVariant,
    ),
  );
}

class _SidebarIconPainter extends CustomPainter {
  const _SidebarIconPainter(this.symbol, this.fill, this.color);

  final SidebarSymbol symbol;
  final double fill;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 24, size.height / 24);
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.7
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final solid = Paint()..color = color;
    void box(Rect rect, double radius, {bool filled = true}) {
      final shape = RRect.fromRectAndRadius(rect, Radius.circular(radius));
      if (filled) {
        canvas.drawRRect(shape, Paint()..color = color.withValues(alpha: fill));
      }
      canvas.drawRRect(shape, stroke);
    }

    void line(double x1, double y1, double x2, double y2) =>
        canvas.drawLine(Offset(x1, y1), Offset(x2, y2), stroke);

    switch (symbol) {
      case SidebarSymbol.overview:
        for (final rect in const [
          Rect.fromLTRB(3.5, 3.5, 10.5, 11.5),
          Rect.fromLTRB(13.5, 3.5, 20.5, 9.5),
          Rect.fromLTRB(3.5, 14.5, 10.5, 20.5),
          Rect.fromLTRB(13.5, 12.5, 20.5, 20.5),
        ]) {
          box(rect, 2);
        }
      case SidebarSymbol.server:
        // Keep the status lights legible as cutouts in the selected symbol.
        canvas.saveLayer(const Rect.fromLTWH(0, 0, 24, 24), Paint());
        for (final y in [3.5, 13.5]) {
          box(Rect.fromLTWH(3.5, y, 17, 7), 2.5);
          canvas.drawCircle(
            Offset(7.2, y + 3.5),
            1.1,
            fill > 0.5 ? (Paint()..blendMode = BlendMode.clear) : solid,
          );
        }
        canvas.restore();
      case SidebarSymbol.cloud:
        final cloud = Path()
          ..moveTo(6.5, 19)
          ..cubicTo(0.5, 19, 0.5, 10.5, 6, 10)
          ..cubicTo(6, 2.5, 17, 2.5, 18, 10)
          ..cubicTo(24, 10, 24, 19, 18, 19)
          ..close();
        canvas.drawPath(cloud, Paint()..color = color.withValues(alpha: fill));
        canvas.drawPath(cloud, stroke);
      case SidebarSymbol.settings:
        stroke.strokeWidth += fill * 0.5;
        for (final row in [(6.0, 8.0), (12.0, 16.0), (18.0, 10.0)]) {
          line(3.5, row.$1, row.$2 - 2.2, row.$1);
          line(row.$2 + 2.2, row.$1, 20.5, row.$1);
          final circle = Offset(row.$2, row.$1);
          canvas.drawCircle(circle, 2.2, stroke);
          canvas.drawCircle(
            circle,
            2.2,
            Paint()..color = color.withValues(alpha: fill),
          );
        }
      case SidebarSymbol.pane:
        box(const Rect.fromLTRB(3, 4.5, 21, 19.5), 3.5, filled: false);
        final divider = 8.5 + 3 * fill;
        line(divider, 4.5, divider, 19.5);
        for (final y in [8.5, 11.0, 13.5]) {
          line(5.5, y, divider - 2.5, y);
        }
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_SidebarIconPainter oldDelegate) =>
      symbol != oldDelegate.symbol ||
      fill != oldDelegate.fill ||
      color != oldDelegate.color;
}
