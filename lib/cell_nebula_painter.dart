import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// Animated, DNA-free cellular-universe background for BioNexus.
/// Pass the existing AnimationController as [repaint].
class CellNebulaPainter extends CustomPainter {
  CellNebulaPainter(Listenable repaint) : super(repaint: repaint);

  static final Stopwatch _clock = Stopwatch()..start();

  static final List<_NebulaCell> _cells = List.generate(12, (i) {
    final n = i + 1.0;
    double f(double x) => x - x.floorToDouble();
    return _NebulaCell(
      f(math.sin(n * 12.9898) * 43758.5453),
      f(math.sin(n * 78.233) * 12345.6789),
      f(math.sin(n * 39.425) * 9876.5432),
      f(math.sin(n * 3.17) * 5432.1) * math.pi * 2,
      .82 + .36 * f(math.sin(n * 5.5) * 777.7),
    );
  })..sort((a, b) => a.depth.compareTo(b.depth));

  @override
  void paint(Canvas canvas, Size size) {
    final t = _clock.elapsedMilliseconds / 1000.0;
    final bounds = Offset.zero & size;

    canvas.drawRect(
      bounds,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF080510), Color(0xFF10091B), Color(0xFF090611)],
          stops: [0, .52, 1],
        ).createShader(bounds),
    );

    _drawGlow(canvas, Offset(size.width * .18, size.height * .20),
        size.width * .72, const Color(0xFF7137B8), .16);
    _drawGlow(canvas, Offset(size.width * .86, size.height * .76),
        size.width * .80, const Color(0xFFB51C9C), .19);
    _drawGlow(canvas, Offset(size.width * .52, size.height * .45),
        size.width * .48, const Color(0xFF087E91), .075);

    _drawDust(canvas, size, t);
    for (final cell in _cells) {
      _drawCell(canvas, size, cell, t);
    }
  }

  void _drawGlow(Canvas canvas, Offset center, double radius, Color color, double alpha) {
    final rect = Rect.fromCircle(center: center, radius: radius);
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..shader = RadialGradient(
          colors: [color.withValues(alpha: alpha), color.withValues(alpha: 0)],
        ).createShader(rect),
    );
  }

  void _drawDust(Canvas canvas, Size size, double t) {
    final fill = Paint()..style = PaintingStyle.fill;
    for (var i = 1; i <= 36; i++) {
      double f(double x) => x - x.floorToDouble();
      final x0 = f(math.sin(i * 21.7) * 31415.9);
      final y0 = f(math.sin(i * 9.31) * 27182.8);
      final z = f(math.sin(i * 4.77) * 1618.0);
      final x = x0 * size.width + math.sin(t * .12 + i) * (3 + 5 * z);
      final y = (y0 * size.height - t * (2 + 3 * z)) % size.height;
      final color = i % 4 == 0 ? const Color(0xFF63E8E5) : const Color(0xFFF18ADB);
      fill.color = color.withValues(alpha: .10 + .22 * z);
      canvas.drawCircle(Offset(x, y), .6 + 1.4 * z, fill);
    }
  }

  void _drawCell(Canvas canvas, Size size, _NebulaCell c, double t) {
    final radius = 22 + 112 * c.depth;
    final span = size.height + radius * 2.4;
    final y = ((c.fy * span - t * (2.0 + 4.0 * c.depth)) % span) - radius * .7;
    final x = c.fx * size.width +
        math.sin(t * .11 + c.phase) * (10 + 22 * c.depth);
    final opacity = .30 + .68 * c.depth;
    final blur = c.depth < .24 ? 4.0 : 0.0;
    final center = Offset(x, y);
    final r = radius;

    final path = Path();
    const points = 36;
    for (var i = 0; i <= points; i++) {
      final angle = i / points * math.pi * 2;
      final wobble = 1 +
          .055 * math.sin(3 * angle + t * .28 + c.phase) +
          .035 * math.sin(5 * angle - t * .20 + c.phase * 1.6);
      final px = x + r * wobble * math.cos(angle) * c.aspect;
      final py = y + r * wobble * math.sin(angle) / c.aspect;
      if (i == 0) {
        path.moveTo(px, py);
      } else {
        path.lineTo(px, py);
      }
    }
    path.close();

    final cellRect = Rect.fromCircle(center: center, radius: r * 1.25);
    final body = Paint()
      ..shader = RadialGradient(
        center: const Alignment(-.38, -.42),
        radius: 1,
        colors: [
          const Color(0xFFFFC6F4).withValues(alpha: .46 * opacity),
          const Color(0xFFEC65D0).withValues(alpha: .31 * opacity),
          const Color(0xFF922A9F).withValues(alpha: .24 * opacity),
          const Color(0xFF251039).withValues(alpha: .16 * opacity),
        ],
        stops: const [0, .38, .72, 1],
      ).createShader(cellRect);
    if (blur > 0) body.maskFilter = ui.MaskFilter.blur(ui.BlurStyle.normal, blur);
    canvas.drawPath(path, body);

    final membrane = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0 + 1.5 * c.depth
      ..color = const Color(0xFFF18ADB).withValues(alpha: .48 * opacity);
    if (blur > 0) membrane.maskFilter = ui.MaskFilter.blur(ui.BlurStyle.normal, blur * .7);
    canvas.drawPath(path, membrane);

    // A restrained cyan arc gives the cells a cool glass-like edge.
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: r * .91),
      math.pi * 1.10 + c.phase * .12,
      math.pi * (.30 + .10 * c.depth),
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = 1.2 + 1.4 * c.depth
        ..color = const Color(0xFF63E8E5).withValues(alpha: .42 * opacity),
    );

    // Soft membrane reflection.
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: r * .80),
      math.pi * 1.12,
      math.pi * .34,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = 1.4 + c.depth
        ..color = Colors.white.withValues(alpha: .26 * opacity),
    );

    final nucleus = center +
        Offset(math.cos(t * .15 + c.phase) * r * .17,
            math.sin(t * .13 + c.phase) * r * .13);
    canvas.drawCircle(
      nucleus,
      r * .30,
      Paint()..color = const Color(0xFFB51C9C).withValues(alpha: .22 * opacity),
    );
    canvas.drawCircle(
      nucleus,
      r * .30,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = const Color(0xFFFFC6F4).withValues(alpha: .30 * opacity),
    );

    for (var j = 0; j < 5; j++) {
      final a = c.phase + j * 1.42 + t * .055;
      final d = r * (.43 + .075 * j);
      final p = center + Offset(math.cos(a) * d, math.sin(a) * d * .78);
      final dotR = r * (.025 + .006 * (j % 3));
      canvas.drawCircle(
        p,
        dotR,
        Paint()..color = (j.isEven ? const Color(0xFF63E8E5) : Colors.white)
            .withValues(alpha: .22 * opacity),
      );
    }
  }

  @override
  bool shouldRepaint(covariant CellNebulaPainter oldDelegate) => false;
}

class _NebulaCell {
  final double fx, fy, depth, phase, aspect;
  const _NebulaCell(this.fx, this.fy, this.depth, this.phase, this.aspect);
}
