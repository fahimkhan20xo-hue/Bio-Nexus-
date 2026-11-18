import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'data.dart';
import 'fx.dart';

/// One step of the streak flame. The flame gets bigger and changes colour as
/// the streak grows. Level 0 is a burnt-out flame (no streak).
class StreakLevel {
  final int index;
  final int minDays;
  final double height, width; // flame size, as a share of the widget
  final int sparks;
  final Color bottom, top, mid, core, glow;
  final String en, bn, ja;
  const StreakLevel(
    this.index,
    this.minDays,
    this.height,
    this.width,
    this.sparks,
    this.bottom,
    this.top,
    this.mid,
    this.core,
    this.glow,
    this.en,
    this.bn,
    this.ja,
  );

  String name(Lang lang) => tr(lang, en, bn, ja);
  Color get color => index == 0 ? Colors.grey : top;
}

const List<StreakLevel> kStreakLevels = [
  StreakLevel(0, 0, .46, .30, 0, Color(0xFF616161), Color(0xFF9E9E9E), Color(0xFF9E9E9E), Color(0xFFBDBDBD), Color(0xFF757575), 'Out', 'নিভে গেছে', '消えた'),
  StreakLevel(1, 1, .50, .32, 0, Color(0xFFD84315), Color(0xFFFF7043), Color(0xFFFFA726), Color(0xFFFFE0B2), Color(0xFFFF7043), 'Spark', 'স্পার্ক', 'スパーク'),
  StreakLevel(2, 3, .62, .38, 0, Color(0xFFE65100), Color(0xFFFF9800), Color(0xFFFFC107), Color(0xFFFFF8E1), Color(0xFFFF9800), 'Flame', 'শিখা', 'ほのお'),
  StreakLevel(3, 7, .76, .46, 2, Color(0xFFEF6C00), Color(0xFFFFB300), Color(0xFFFFE082), Color(0xFFFFFDE7), Color(0xFFFFB300), 'Blaze', 'ব্লেজ', 'ブレイズ'),
  StreakLevel(4, 14, .86, .52, 4, Color(0xFFE53935), Color(0xFFFFD54F), Color(0xFFFFF176), Color(0xFFFFFFFF), Color(0xFFFF7043), 'Inferno', 'ইনফার্নো', 'インフェルノ'),
  StreakLevel(5, 30, .92, .56, 5, Color(0xFF1565C0), Color(0xFF4FC3F7), Color(0xFF81D4FA), Color(0xFFE1F5FE), Color(0xFF29B6F6), 'Legend', 'লিজেন্ড', '伝説'),
  StreakLevel(6, 100, .96, .60, 6, Color(0xFF6A1B9A), Color(0xFFE040FB), Color(0xFFCE93D8), Color(0xFFF3E5F5), Color(0xFFAB47BC), 'Mythic', 'মিথিক', '神話'),
];

StreakLevel streakLevelFor(int days) {
  var lv = kStreakLevels.first;
  for (final l in kStreakLevels) {
    if (days >= l.minDays) lv = l;
  }
  return lv;
}

/// The next level to reach, or null at the top.
StreakLevel? nextStreakLevel(int days) {
  for (final l in kStreakLevels) {
    if (l.minDays > days) return l;
  }
  return null;
}

/// An animated flame. It flickers, glows and (from Blaze up) throws sparks.
class StreakFlame extends StatefulWidget {
  final int days;
  final double size;
  final bool animate;
  const StreakFlame({super.key, required this.days, this.size = 80, this.animate = true});

  @override
  State<StreakFlame> createState() => _StreakFlameState();
}

class _StreakFlameState extends State<StreakFlame> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1800));

  bool get _moving => widget.animate && fxEnabled.value;

  @override
  void initState() {
    super.initState();
    if (_moving) _c.repeat();
  }

  @override
  void didUpdateWidget(StreakFlame old) {
    super.didUpdateWidget(old);
    if (_moving && !_c.isAnimating) _c.repeat();
    if (!_moving && _c.isAnimating) _c.stop();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final level = streakLevelFor(widget.days);
    Widget flame = SizedBox(
      width: widget.size,
      height: widget.size,
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) => CustomPaint(painter: _FlamePainter(_moving ? _c.value : .25, level)),
      ),
    );
    if (_moving) {
      // a little pop each time the level changes
      flame = TweenAnimationBuilder<double>(
        key: ValueKey(level.index),
        tween: Tween<double>(begin: .55, end: 1),
        duration: const Duration(milliseconds: 750),
        curve: Curves.elasticOut,
        builder: (context, v, child) => Transform.scale(scale: v, alignment: Alignment.bottomCenter, child: child),
        child: flame,
      );
    }
    return flame;
  }
}

/// Flame outlines, one per level (index 0 is unused: that level is the burnt-out flame).
/// x is -1..1 across the flame, y is 0 (bottom) to 1 (tip). `true` marks a sharp tip.
const List<List<_P>> _kShapes = [
  [],
  [
    _P(0.00, 0.00), _P(0.62, 0.04), _P(0.90, 0.28), _P(0.80, 0.52),
    _P(0.56, 0.72), _P(0.44, 0.90), _P(0.34, 1.00, true), _P(0.14, 0.80),
    _P(-0.10, 0.70), _P(-0.46, 0.54), _P(-0.86, 0.34), _P(-0.64, 0.06),
  ],
  [
    _P(0.00, 0.00), _P(0.62, 0.04), _P(0.92, 0.28), _P(0.84, 0.48),
    _P(0.70, 0.58, true), _P(0.88, 0.74, true), _P(0.58, 0.74), _P(0.40, 0.90),
    _P(0.22, 1.00, true), _P(0.06, 0.78), _P(-0.14, 0.68, true), _P(-0.40, 0.86, true),
    _P(-0.50, 0.58), _P(-0.88, 0.40), _P(-0.70, 0.08),
  ],
  [
    _P(0.00, 0.00), _P(0.64, 0.04), _P(0.94, 0.26), _P(0.86, 0.46),
    _P(0.72, 0.54, true), _P(0.92, 0.72, true), _P(0.62, 0.70), _P(0.50, 0.82),
    _P(0.34, 0.96, true), _P(0.18, 0.74, true), _P(0.04, 1.00, true), _P(-0.14, 0.76),
    _P(-0.34, 0.70, true), _P(-0.56, 0.88, true), _P(-0.58, 0.60), _P(-0.90, 0.44),
    _P(-0.72, 0.08),
  ],
  [
    _P(0.00, 0.00), _P(0.66, 0.03), _P(0.96, 0.24), _P(0.88, 0.42),
    _P(0.76, 0.50, true), _P(0.96, 0.66, true), _P(0.66, 0.66), _P(0.60, 0.80),
    _P(0.52, 0.90, true), _P(0.30, 0.74, true), _P(0.20, 1.00, true), _P(0.00, 0.74, true),
    _P(-0.22, 0.92, true), _P(-0.34, 0.66, true), _P(-0.62, 0.80, true), _P(-0.64, 0.54),
    _P(-0.94, 0.40), _P(-0.74, 0.08),
  ],
  [
    _P(0.00, 0.00), _P(0.66, 0.03), _P(0.98, 0.22), _P(0.90, 0.40),
    _P(0.80, 0.48, true), _P(1.00, 0.62, true), _P(0.72, 0.62), _P(0.66, 0.74),
    _P(0.70, 0.86, true), _P(0.46, 0.72, true), _P(0.50, 1.00, true), _P(0.20, 0.78),
    _P(0.02, 0.66, true), _P(-0.18, 0.90, true), _P(-0.34, 0.60, true), _P(-0.64, 0.76, true),
    _P(-0.66, 0.50), _P(-0.96, 0.38), _P(-0.76, 0.07),
  ],
  [
    _P(0.00, 0.00), _P(0.68, 0.03), _P(1.00, 0.22), _P(0.94, 0.38),
    _P(0.84, 0.46, true), _P(1.02, 0.60, true), _P(0.76, 0.60), _P(0.74, 0.72),
    _P(0.82, 0.84, true), _P(0.54, 0.70, true), _P(0.58, 0.94, true), _P(0.32, 0.72, true),
    _P(0.22, 1.00, true), _P(0.04, 0.72, true), _P(-0.14, 0.92, true), _P(-0.30, 0.62, true),
    _P(-0.52, 0.82, true), _P(-0.62, 0.52, true), _P(-0.84, 0.64, true), _P(-0.84, 0.40),
    _P(-1.00, 0.30), _P(-0.78, 0.07),
  ],
];

class _P {
  final double x, y;
  final bool sharp;
  const _P(this.x, this.y, [this.sharp = false]);
}

class _FlamePainter extends CustomPainter {
  final double t; // 0..1, loops
  final StreakLevel level;
  _FlamePainter(this.t, this.level);

  static const double _two = math.pi * 2;

  Path _flame(double cx, double baseY, double w, double h, double sway, double wob) {
    final tipX = cx + sway * w * .18;
    final tipY = baseY - h;
    final p = Path()..moveTo(cx, baseY);
    p.cubicTo(cx - w * .62, baseY - h * .05, cx - w * .55, baseY - h * .55 + wob * h * .03, tipX, tipY);
    p.cubicTo(cx + w * .55, baseY - h * .55 - wob * h * .03, cx + w * .62, baseY - h * .05, cx, baseY);
    p.close();
    return p;
  }

  /// One layer of the flame: the level's outline, moving with the wind.
  Path _layer(double cx, double baseY, double halfW, double tall, double sx, double sy, double time, double phase) {
    final pts = _kShapes[level.index];
    final n = pts.length;
    final xy = <Offset>[];
    for (var i = 0; i < n; i++) {
      final p = pts[i];
      final dx = math.sin(time * _two + p.y * 2.6 + phase + i * .35) * .10 * p.y * p.y;
      final dy = (p.sharp && p.y > .5) ? math.sin(time * _two * 2 + i) * .025 * p.y : 0.0;
      xy.add(Offset(cx + (p.x + dx) * halfW * sx, baseY - (p.y + dy) * tall * sy));
    }
    final path = Path()..moveTo(xy[0].dx, xy[0].dy);
    for (var i = 0; i < n; i++) {
      final p0 = xy[(i - 1 + n) % n], p1 = xy[i], p2 = xy[(i + 1) % n], p3 = xy[(i + 2) % n];
      final c1 = pts[i].sharp ? p1 : p1 + (p2 - p0) / 6;
      final c2 = pts[(i + 1) % n].sharp ? p2 : p2 - (p3 - p1) / 6;
      path.cubicTo(c1.dx, c1.dy, c2.dx, c2.dy, p2.dx, p2.dy);
    }
    return path..close();
  }

  Path _drop(Offset c, double s) {
    return Path()
      ..moveTo(c.dx, c.dy - s * 1.6)
      ..cubicTo(c.dx + s * .2, c.dy - s * .6, c.dx + s, c.dy - s * .2, c.dx, c.dy + s)
      ..cubicTo(c.dx - s, c.dy - s * .2, c.dx - s * .2, c.dy - s * .6, c.dx, c.dy - s * 1.6)
      ..close();
  }

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final cx = w / 2;
    final baseY = h * .94;
    if (level.index == 0) {
      _paintOut(canvas, size, cx, baseY);
      return;
    }
    final tall = h * level.height;
    final wide = w * level.width;

    // soft glow behind the flame
    final pulse = .75 + .25 * math.sin(t * _two * 2);
    canvas.drawCircle(
      Offset(cx, baseY - tall * .42),
      wide * .95,
      Paint()
        ..color = level.glow.withValues(alpha: .24 * pulse)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, wide * .45),
    );

    // four layers, like the flame icons: outer, middle, inner and core
    final halfW = wide / 2;
    const layers = [(1.0, 1.0), (.66, .70), (.40, .46), (.20, .24)];
    final colors = [level.bottom, level.top, level.mid, level.core];
    for (var k = 0; k < layers.length; k++) {
      canvas.drawPath(
        _layer(cx, baseY, halfW, tall, layers[k].$1, layers[k].$2, t + .13 * k, k * 1.1),
        Paint()..color = colors[k],
      );
    }

    // little flames floating up from the top
    for (var i = 0; i < level.sparks; i++) {
      final ph = (t + i / level.sparks) % 1.0;
      final x = cx + math.sin(ph * _two + i * 2.1) * wide * .42;
      final y = baseY - tall * (.60 + ph * .40);
      canvas.drawPath(
        _drop(Offset(x, y), wide * .05 * (1 - ph) + .8),
        Paint()..color = level.top.withValues(alpha: (1 - ph).clamp(0.0, 1.0)),
      );
    }
  }

  void _paintOut(Canvas canvas, Size size, double cx, double baseY) {
    final w = size.width, h = size.height;
    // ash
    canvas.drawOval(
      Rect.fromCenter(center: Offset(cx, baseY), width: w * .5, height: h * .1),
      Paint()..color = Colors.grey.withValues(alpha: .35),
    );
    // the burnt-out flame, only an outline
    canvas.drawPath(
      _flame(cx, baseY, w * .30, h * .46, 0, 0),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = w * .03
        ..color = Colors.grey.withValues(alpha: .55),
    );
    // a last faint ember
    final ember = .35 + .25 * math.sin(t * _two);
    canvas.drawCircle(Offset(cx, baseY - h * .03), w * .035, Paint()..color = const Color(0xFFFF5722).withValues(alpha: ember));
    // smoke
    for (var i = 0; i < 3; i++) {
      final ph = (t + i / 3) % 1.0;
      canvas.drawCircle(
        Offset(cx + math.sin(ph * 5 + i) * w * .06, baseY - h * .15 - ph * h * .55),
        w * (.04 + ph * .07),
        Paint()..color = Colors.grey.withValues(alpha: .28 * (1 - ph)),
      );
    }
  }

  @override
  bool shouldRepaint(_FlamePainter old) => old.t != t || old.level.index != level.index;
}
