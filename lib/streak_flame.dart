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
    final sway = math.sin(t * _two);
    final sway2 = math.sin(t * _two + 1.3);
    final wob = math.sin(t * _two * 2 + .7);

    // soft glow behind the flame
    final pulse = .75 + .25 * math.sin(t * _two * 2);
    canvas.drawCircle(
      Offset(cx, baseY - tall * .42),
      wide * .95,
      Paint()
        ..color = level.glow.withValues(alpha: .24 * pulse)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, wide * .45),
    );

    // outer, middle and inner flame
    canvas.drawPath(
      _flame(cx, baseY, wide, tall * (1 + .03 * wob), sway, wob),
      Paint()..shader = ui.Gradient.linear(Offset(cx, baseY), Offset(cx, baseY - tall), [level.bottom, level.top]),
    );
    canvas.drawPath(
      _flame(cx, baseY - tall * .02, wide * .68, tall * .72 * (1 - .04 * wob), sway2, -wob),
      Paint()..color = level.mid,
    );
    canvas.drawPath(
      _flame(cx, baseY - tall * .03, wide * .36, tall * .42 * (1 + .05 * wob), sway, wob),
      Paint()..color = level.core,
    );

    // sparks rising from the top
    for (var i = 0; i < level.sparks; i++) {
      final ph = (t + i / level.sparks) % 1.0;
      final x = cx + math.sin(ph * _two + i * 2.1) * wide * .45;
      final y = baseY - tall * (.55 + ph * .45);
      canvas.drawCircle(
        Offset(x, y),
        wide * .05 * (1 - ph) + .6,
        Paint()..color = level.mid.withValues(alpha: (1 - ph).clamp(0.0, 1.0)),
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
