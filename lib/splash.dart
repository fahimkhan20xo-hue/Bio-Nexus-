import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Shows the opening screen at once, loads the data behind it, then fades into
/// the real app.
///
/// [init] loads everything the app needs. The splash stays at least
/// [minShow] so the animation is not just a flash.
class BootApp extends StatefulWidget {
  final Future<void> Function() init;
  final Widget Function() builder;
  final Duration minShow;
  const BootApp({
    super.key,
    required this.init,
    required this.builder,
    this.minShow = const Duration(milliseconds: 900),
  });

  @override
  State<BootApp> createState() => _BootAppState();
}

class _BootAppState extends State<BootApp> {
  bool _ready = false;
  bool _leaving = false; // the logo fades out first, then the screen opens into the app
  Object? _error;

  @override
  void initState() {
    super.initState();
    _run();
  }

  Future<void> _run() async {
    setState(() => _error = null);
    // widget tests must not be left waiting on a timer
    final wait = Platform.environment.containsKey('FLUTTER_TEST') ? Future<void>.value() : Future<void>.delayed(widget.minShow);
    try {
      await widget.init();
    } catch (e, st) {
      debugPrint('Start-up failed: $e\n$st');
      if (mounted) setState(() => _error = e);
      return;
    }
    await wait;
    if (!mounted) return;
    // 1) the logo and texts fade away (the dark background stays)
    setState(() => _leaving = true);
    await Future<void>.delayed(Platform.environment.containsKey('FLUTTER_TEST') ? Duration.zero : const Duration(milliseconds: 280));
    // 2) only then the plain dark screen fades into the app, so no logo is left on top of it
    if (mounted) setState(() => _ready = true);
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.ltr,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 550),
        switchInCurve: Curves.easeOut,
        child: _ready
            ? KeyedSubtree(key: const ValueKey('app'), child: widget.builder())
            : _SplashApp(key: const ValueKey('splash'), error: _error, leaving: _leaving, onRetry: _run),
      ),
    );
  }
}

const Color _mint = Color(0xFF8DD6B0);
const Color _bgTop = Color(0xFF050D0B);
const Color _bgBottom = Color(0xFF0B2019);

class _SplashApp extends StatelessWidget {
  final Object? error;
  final bool leaving;
  final VoidCallback onRetry;
  const _SplashApp({super.key, required this.error, required this.leaving, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF10B981), brightness: Brightness.dark),
        scaffoldBackgroundColor: _bgTop,
      ),
      home: _SplashScreen(error: error, leaving: leaving, onRetry: onRetry),
    );
  }
}

class _SplashScreen extends StatefulWidget {
  final Object? error;
  final bool leaving;
  final VoidCallback onRetry;
  const _SplashScreen({required this.error, required this.leaving, required this.onRetry});

  @override
  State<_SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<_SplashScreen> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 2400))..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [_bgTop, _bgBottom]),
        ),
        child: Stack(children: [
          // slowly moving DNA strand behind everything
          Positioned.fill(
            child: AnimatedBuilder(
              animation: _c,
              builder: (context, _) => CustomPaint(painter: _DnaPainter(_c.value)),
            ),
          ),
          SafeArea(
            child: AnimatedOpacity(
              opacity: widget.leaving ? 0 : 1,
              duration: const Duration(milliseconds: 250),
              child: Column(children: [
              const Spacer(flex: 5),
              // logo with orbiting dots
              TweenAnimationBuilder<double>(
                tween: Tween<double>(begin: .4, end: 1),
                duration: const Duration(milliseconds: 1100),
                curve: Curves.elasticOut,
                builder: (context, v, child) => Transform.scale(scale: v, child: child),
                child: SizedBox(
                  width: 190,
                  height: 190,
                  child: AnimatedBuilder(
                    animation: _c,
                    builder: (context, _) => CustomPaint(
                      painter: _OrbitPainter(_c.value),
                      child: Center(child: _Logo(pulse: _c.value)),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 26),
              TweenAnimationBuilder<double>(
                tween: Tween<double>(begin: 0, end: 1),
                duration: const Duration(milliseconds: 900),
                curve: Curves.easeOutCubic,
                builder: (context, v, child) => Opacity(
                  opacity: v,
                  child: Transform.translate(offset: Offset(0, 14 * (1 - v)), child: child),
                ),
                child: Column(children: [
                  Text('BioNexus', style: text.displaySmall?.copyWith(fontWeight: FontWeight.bold, color: Colors.white)),
                  const SizedBox(height: 8),
                  Text(
                    'EXPLORE LIFE. DISCOVER SCIENCE.',
                    style: text.labelMedium?.copyWith(letterSpacing: 2.2, color: _mint.withValues(alpha: .85)),
                  ),
                ]),
              ),
              const Spacer(flex: 4),
              if (widget.error != null) ...[
                const Icon(Icons.error_outline, color: Colors.orangeAccent),
                const SizedBox(height: 8),
                Text('Could not start the app.', style: text.bodyMedium),
                const SizedBox(height: 8),
                FilledButton(onPressed: widget.onRetry, child: const Text('Try again')),
              ] else ...[
                SizedBox(
                  width: 150,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(minHeight: 3, color: _mint, backgroundColor: Colors.white12),
                  ),
                ),
                const SizedBox(height: 12),
                Text('Loading species…', style: text.bodySmall?.copyWith(color: Colors.white54)),
              ],
              const SizedBox(height: 34),
              ]),
            ),
          ),
        ]),
      ),
    );
  }
}

/// The app icon: a mint rounded square with a microscope, softly glowing.
class _Logo extends StatelessWidget {
  final double pulse; // 0..1, loops
  const _Logo({required this.pulse});

  @override
  Widget build(BuildContext context) {
    final glow = .30 + .18 * math.sin(pulse * math.pi * 2);
    return Container(
      width: 104,
      height: 104,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(30),
        gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFFA7E6C4), Color(0xFF5CC79A)]),
        boxShadow: [BoxShadow(color: _mint.withValues(alpha: glow), blurRadius: 42, spreadRadius: 2)],
      ),
      child: const Icon(Icons.biotech, size: 62, color: Color(0xFF0B2B22)),
    );
  }
}

/// Three dots circling the logo, like cells under a microscope.
class _OrbitPainter extends CustomPainter {
  final double t;
  _OrbitPainter(this.t);

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.width / 2 - 8;
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = _mint.withValues(alpha: .14),
    );
    for (var i = 0; i < 3; i++) {
      final a = t * math.pi * 2 + i * math.pi * 2 / 3;
      final p = c + Offset(math.cos(a), math.sin(a)) * r;
      final fade = .55 + .45 * math.sin(a + 1.2);
      canvas.drawCircle(p, 9, Paint()..color = _mint.withValues(alpha: .18 * fade)..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6));
      canvas.drawCircle(p, 4.5 + 1.5 * fade, Paint()..color = _mint.withValues(alpha: .55 + .4 * fade));
    }
  }

  @override
  bool shouldRepaint(_OrbitPainter old) => old.t != t;
}

/// A faint, slowly drifting DNA double helix.
class _DnaPainter extends CustomPainter {
  final double t;
  _DnaPainter(this.t);

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final amp = size.width * .30;
    const steps = 26;
    final phase = t * math.pi * 2;
    final strand = Paint()
      ..strokeWidth = 2
      ..color = _mint.withValues(alpha: .10);
    final rung = Paint()
      ..strokeWidth = 1.2
      ..color = _mint.withValues(alpha: .06);
    Offset? prevA, prevB;
    for (var i = 0; i <= steps; i++) {
      final y = size.height * i / steps;
      final a = phase + i * .55;
      final pa = Offset(cx + math.sin(a) * amp, y);
      final pb = Offset(cx - math.sin(a) * amp, y);
      if (prevA != null) canvas.drawLine(prevA, pa, strand);
      if (prevB != null) canvas.drawLine(prevB, pb, strand);
      if (i.isEven) canvas.drawLine(pa, pb, rung);
      canvas.drawCircle(pa, 3, Paint()..color = _mint.withValues(alpha: .10 + .06 * math.cos(a)));
      canvas.drawCircle(pb, 3, Paint()..color = _mint.withValues(alpha: .10 - .06 * math.cos(a)));
      prevA = pa;
      prevB = pb;
    }
  }

  @override
  bool shouldRepaint(_DnaPainter old) => old.t != t;
}
