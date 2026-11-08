import 'dart:convert';
import 'dart:io';
import 'dart:ui' show ImageFilter;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

// Visual effects shared by the whole app. Everything here respects the
// "3D effects & animations" switch in Settings, so low-end phones can run in
// a simple, fast mode.

final ValueNotifier<bool> fxEnabled = ValueNotifier<bool>(true);

/// Which look the app uses.
enum ThemeStyle { emerald, cells }

final ValueNotifier<ThemeStyle> themeStyle = ValueNotifier<ThemeStyle>(ThemeStyle.emerald);

Future<File> _fxFile() async {
  final d = await getApplicationSupportDirectory();
  return File('${d.path}/bionexus_fx.json');
}

Future<void> _saveFx() async {
  try {
    final f = await _fxFile();
    await f.writeAsString(jsonEncode({'fx': fxEnabled.value, 'style': themeStyle.value.name}), flush: true);
  } catch (e) {
    debugPrint('Could not save fx setting: $e');
  }
}

Future<void> loadFx() async {
  try {
    final f = await _fxFile();
    if (!await f.exists()) return;
    final m = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
    fxEnabled.value = m['fx'] != false;
    final i = ThemeStyle.values.indexWhere((s) => s.name == m['style']);
    if (i >= 0) themeStyle.value = ThemeStyle.values[i];
  } catch (e) {
    debugPrint('Could not load fx setting: $e');
  }
}

Future<void> setFx(bool v) async {
  fxEnabled.value = v;
  await _saveFx();
}

Future<void> setThemeStyle(ThemeStyle s) async {
  themeStyle.value = s;
  await _saveFx();
}

/// Emerald palette used across the app.
class Emerald {
  static const Color c900 = Color(0xFF064E3B);
  static const Color c700 = Color(0xFF047857);
  static const Color c600 = Color(0xFF059669);
  static const Color c500 = Color(0xFF10B981);
  static const Color c400 = Color(0xFF34D399);
  static const Color c200 = Color(0xFFA7F3D0);
  static LinearGradient get hero => themeStyle.value == ThemeStyle.cells
      ? const LinearGradient(
          colors: [Color(0xFF2E1065), Color(0xFF6D28D9), Color(0xFF0891B2), Color(0xFF10B981)],
          stops: [0.0, 0.38, 0.72, 1.0],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        )
      : const LinearGradient(
          colors: [c900, c700, c500],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        );
}

/// Frosted-glass card. Blur is only used when effects are on (and [blur] is true).
class GlassCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;
  final VoidCallback? onTap;
  final bool blur;
  final Color? tint;
  final EdgeInsetsGeometry? margin;

  const GlassCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(14),
    this.radius = 20,
    this.onTap,
    this.blur = true,
    this.tint,
    this.margin,
  });

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final fx = fxEnabled.value;
    final cells = themeStyle.value == ThemeStyle.cells;
    final base = cells
        ? const Color(0xFF1C0F33).withValues(alpha: .50)
        : (dark ? Colors.white.withValues(alpha: .07) : Colors.white.withValues(alpha: .72));
    final border = cells
        ? const Color(0xFF63E8E5).withValues(alpha: .24)
        : (dark ? Colors.white.withValues(alpha: .14) : Colors.white.withValues(alpha: .9));
    final r = BorderRadius.circular(radius);

    Widget inner = Container(
      decoration: BoxDecoration(
        color: tint ?? base,
        borderRadius: r,
        border: Border.all(color: border),
      ),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius: r,
          onTap: onTap,
          child: Padding(padding: padding, child: child),
        ),
      ),
    );

    if (fx && blur) {
      inner = ClipRRect(
        borderRadius: r,
        child: BackdropFilter(filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14), child: inner),
      );
    }

    return Container(
      margin: margin,
      decoration: fx
          ? BoxDecoration(
              borderRadius: r,
              boxShadow: [
                BoxShadow(
                  color: cells ? const Color(0xFFB51C9C).withValues(alpha: .20) : Colors.black.withValues(alpha: dark ? .28 : .08),
                  blurRadius: 18,
                  offset: const Offset(0, 8),
                ),
              ],
            )
          : null,
      child: inner,
    );
  }
}

/// A number that counts up when it appears.
class AnimatedCount extends StatelessWidget {
  final int value;
  final TextStyle? style;
  final Duration duration;
  const AnimatedCount(this.value, {super.key, this.style, this.duration = const Duration(milliseconds: 1100)});

  @override
  Widget build(BuildContext context) {
    if (!fxEnabled.value) return Text('$value', style: style);
    return TweenAnimationBuilder<int>(
      tween: IntTween(begin: 0, end: value),
      duration: duration,
      curve: Curves.easeOutCubic,
      builder: (context, v, _) => Text('$v', style: style),
    );
  }
}

/// A moving highlight over a grey box while something is loading.
class ShimmerBox extends StatefulWidget {
  final double? width;
  final double? height;
  final double radius;
  const ShimmerBox({super.key, this.width, this.height, this.radius = 14});

  @override
  State<ShimmerBox> createState() => _ShimmerBoxState();
}

class _ShimmerBoxState extends State<ShimmerBox> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1300))..repeat();

  @override
  void initState() {
    super.initState();
    if (!fxEnabled.value) _c.stop();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final base = dark ? Colors.white.withValues(alpha: .07) : Colors.black.withValues(alpha: .06);
    final light = dark ? Colors.white.withValues(alpha: .18) : Colors.black.withValues(alpha: .12);
    final r = BorderRadius.circular(widget.radius);
    if (!fxEnabled.value) {
      return Container(width: widget.width, height: widget.height, decoration: BoxDecoration(color: base, borderRadius: r));
    }
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) => Container(
        width: widget.width,
        height: widget.height,
        decoration: BoxDecoration(
          borderRadius: r,
          gradient: LinearGradient(
            colors: [base, light, base],
            stops: const [0.0, 0.5, 1.0],
            begin: Alignment(-1.6 + 3.2 * _c.value, 0),
            end: Alignment(-0.6 + 3.2 * _c.value, 0),
          ),
        ),
      ),
    );
  }
}

/// Page route with a soft fade, slide and scale. Plain route when effects are off.
Route<T> fxRoute<T>(WidgetBuilder builder) {
  if (!fxEnabled.value) return MaterialPageRoute<T>(builder: builder);
  return PageRouteBuilder<T>(
    transitionDuration: const Duration(milliseconds: 340),
    reverseTransitionDuration: const Duration(milliseconds: 260),
    pageBuilder: (context, animation, secondary) => builder(context),
    transitionsBuilder: (context, animation, secondary, child) {
      final curved = CurvedAnimation(parent: animation, curve: Curves.easeOutCubic, reverseCurve: Curves.easeInCubic);
      return FadeTransition(
        opacity: curved,
        child: SlideTransition(
          position: Tween<Offset>(begin: const Offset(0, 0.05), end: Offset.zero).animate(curved),
          child: ScaleTransition(scale: Tween<double>(begin: 0.98, end: 1.0).animate(curved), child: child),
        ),
      );
    },
  );
}


/// Frosted-glass band behind every app bar (drawn between the background and the pages).
class GlassTopStrip extends StatelessWidget {
  const GlassTopStrip({super.key});

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final cells = themeStyle.value == ThemeStyle.cells;
    final fx = fxEnabled.value;
    final height = MediaQuery.of(context).padding.top + kToolbarHeight;
    final tint = cells
        ? const Color(0xFF10091B).withValues(alpha: fx ? .58 : .96)
        : (dark
            ? const Color(0xFF08120F).withValues(alpha: fx ? .50 : .96)
            : Colors.white.withValues(alpha: fx ? .60 : .97));
    Widget bar = Container(
      height: height,
      decoration: BoxDecoration(
        color: tint,
        border: Border(
          bottom: BorderSide(color: (cells ? const Color(0xFF63E8E5) : Emerald.c500).withValues(alpha: .20)),
        ),
      ),
    );
    if (fx) {
      bar = ClipRect(child: BackdropFilter(filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16), child: bar));
    }
    return IgnorePointer(child: bar);
  }
}
