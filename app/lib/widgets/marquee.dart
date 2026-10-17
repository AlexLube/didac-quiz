import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../theme.dart';

/// Texto con degradado dorado (rótulos de cartelera).
class GoldText extends StatelessWidget {
  final String text;
  final TextStyle style;
  final TextAlign? textAlign;
  final Gradient gradient;
  const GoldText(this.text,
      {super.key, required this.style, this.textAlign, this.gradient = AppColors.goldGradient});

  @override
  Widget build(BuildContext context) {
    return ShaderMask(
      blendMode: BlendMode.srcIn,
      shaderCallback: (r) => gradient.createShader(r),
      child: Text(text, style: style, textAlign: textAlign),
    );
  }
}

/// Marco de marquesina: bombillas alrededor que se encienden en cadena.
class MarqueeFrame extends StatefulWidget {
  final Widget child;
  final double radius;
  final double spacing;
  const MarqueeFrame({super.key, required this.child, this.radius = 26, this.spacing = 22});

  @override
  State<MarqueeFrame> createState() => _MarqueeFrameState();
}

class _MarqueeFrameState extends State<MarqueeFrame> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1600))..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(widget.radius),
        gradient: AppColors.curtainGradient,
        boxShadow: [
          BoxShadow(color: AppColors.curtain.withValues(alpha: 0.35), blurRadius: 32, spreadRadius: -6),
          BoxShadow(color: Colors.black.withValues(alpha: 0.6), blurRadius: 24, offset: const Offset(0, 14)),
        ],
      ),
      child: Stack(
        children: [
          Positioned.fill(
            child: RepaintBoundary(
              child: AnimatedBuilder(
                animation: _c,
                builder: (context, _) => CustomPaint(
                  painter: _BulbsPainter(_c.value, widget.radius, widget.spacing),
                ),
              ),
            ),
          ),
          Padding(padding: const EdgeInsets.all(14), child: widget.child),
        ],
      ),
    );
  }
}

class _BulbsPainter extends CustomPainter {
  final double t;
  final double radius;
  final double spacing;
  _BulbsPainter(this.t, this.radius, this.spacing);

  @override
  void paint(Canvas canvas, Size size) {
    const inset = 7.0;
    final rect = Rect.fromLTWH(inset, inset, size.width - 2 * inset, size.height - 2 * inset);
    final path = Path()..addRRect(RRect.fromRectAndRadius(rect, Radius.circular(radius - inset)));
    final metric = path.computeMetrics().first;
    final n = (metric.length / spacing).floor();
    final phase = (t * 3).floor() % 3;
    for (var i = 0; i < n; i++) {
      final pos = metric.getTangentForOffset(i * metric.length / n)!.position;
      final on = i % 3 == phase;
      final glow = Paint()
        ..color = AppColors.gold.withValues(alpha: on ? 0.55 : 0.12)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5);
      canvas.drawCircle(pos, on ? 6 : 4, glow);
      canvas.drawCircle(pos, 2.6,
          Paint()..color = on ? const Color(0xFFFFF4D2) : const Color(0xFF8A6A2A));
    }
  }

  @override
  bool shouldRepaint(covariant _BulbsPainter old) => old.t != t;
}

/// Encoge un poco al pulsar (sensación táctil).
class Pressable extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  const Pressable({super.key, required this.child, this.onTap});

  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null;
    return GestureDetector(
      onTapDown: enabled ? (_) => setState(() => _down = true) : null,
      onTapCancel: enabled ? () => setState(() => _down = false) : null,
      onTapUp: enabled ? (_) => setState(() => _down = false) : null,
      onTap: widget.onTap,
      child: AnimatedScale(
        scale: _down ? 0.96 : 1,
        duration: const Duration(milliseconds: 110),
        child: widget.child,
      ),
    );
  }
}

/// Botón principal dorado con un brillo que lo recorre.
class GlowButton extends StatefulWidget {
  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  const GlowButton({super.key, required this.label, this.icon, this.onPressed});

  @override
  State<GlowButton> createState() => _GlowButtonState();
}

class _GlowButtonState extends State<GlowButton> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 2600))..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onPressed != null;
    return Semantics(
      button: true,
      label: widget.label,
      child: Pressable(
        onTap: widget.onPressed,
        child: AnimatedBuilder(
          animation: _c,
          builder: (context, child) {
            final x = -1.5 + 3.5 * _c.value;
            return Container(
              height: 58,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(18),
                gradient: enabled ? AppColors.goldGradient : null,
                color: enabled ? null : AppColors.surfaceHigh,
                boxShadow: enabled
                    ? [BoxShadow(color: AppColors.accent.withValues(alpha: 0.45), blurRadius: 22, spreadRadius: -4)]
                    : null,
              ),
              foregroundDecoration: enabled
                  ? BoxDecoration(
                      borderRadius: BorderRadius.circular(18),
                      gradient: LinearGradient(
                        begin: Alignment(x - 0.4, -1),
                        end: Alignment(x + 0.4, 1),
                        colors: [Colors.white.withValues(alpha: 0), Colors.white.withValues(alpha: 0.35),
                          Colors.white.withValues(alpha: 0)],
                      ),
                    )
                  : null,
              child: child,
            );
          },
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (widget.icon != null) ...[
                Icon(widget.icon, color: enabled ? const Color(0xFF241705) : AppColors.textMuted, size: 26),
                const SizedBox(width: 8),
              ],
              Text(widget.label.toUpperCase(),
                  style: AppFonts.marquee(26,
                      color: enabled ? const Color(0xFF241705) : AppColors.textMuted, spacing: 2)),
            ],
          ),
        ),
      ),
    );
  }
}

/// Tarjeta de cristal ahumado.
class GlassCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final Color? borderColor;
  const GlassCard({super.key, required this.child, this.padding = const EdgeInsets.all(16), this.onTap,
    this.borderColor});

  @override
  Widget build(BuildContext context) {
    final card = ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Colors.white.withValues(alpha: 0.07), Colors.white.withValues(alpha: 0.025)],
            ),
            border: Border.all(color: borderColor ?? Colors.white.withValues(alpha: 0.09)),
          ),
          child: child,
        ),
      ),
    );
    return onTap == null ? card : Pressable(onTap: onTap, child: card);
  }
}

/// Rótulo de sección: «— LOGROS —».
class SectionTitle extends StatelessWidget {
  final String text;
  final Widget? trailing;
  const SectionTitle(this.text, {super.key, this.trailing});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 6, bottom: 10),
      child: Row(
        children: [
          Container(width: 18, height: 2, color: AppColors.accent),
          const SizedBox(width: 8),
          GoldText(text.toUpperCase(), style: AppFonts.marquee(22, spacing: 2)),
          const Spacer(),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

/// Nivel de un logro según sus puntos: bronce, plata, oro, platino, diamante.
enum MedalTier { bronze, silver, gold, platinum, diamond }

MedalTier tierForPoints(int points) => points >= 80
    ? MedalTier.diamond
    : points >= 55
        ? MedalTier.platinum
        : points >= 30
            ? MedalTier.gold
            : points >= 15
                ? MedalTier.silver
                : MedalTier.bronze;

List<Color> tierColors(MedalTier t) => switch (t) {
      MedalTier.bronze => const [Color(0xFFF0B27A), Color(0xFF9C5A2C)],
      MedalTier.silver => const [Color(0xFFF2F4F8), Color(0xFF8C94A3)],
      MedalTier.gold => const [Color(0xFFFFE9A8), Color(0xFFC8902E)],
      MedalTier.platinum => const [Color(0xFFD6FFF6), Color(0xFF3FA79A)],
      MedalTier.diamond => const [Color(0xFFE3D5FF), Color(0xFF7B5CFF)],
    };

/// Medalla redonda de un logro, con brillo si está conseguido.
class Medal extends StatelessWidget {
  final IconData icon;
  final MedalTier tier;
  final bool unlocked;
  final double size;
  final double progress; // 0..1 para los bloqueados
  const Medal({super.key, required this.icon, required this.tier, required this.unlocked, this.size = 64,
    this.progress = 0});

  @override
  Widget build(BuildContext context) {
    final c = tierColors(tier);
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          if (!unlocked)
            SizedBox(
              width: size,
              height: size,
              child: CircularProgressIndicator(
                value: progress.clamp(0, 1),
                strokeWidth: 3,
                backgroundColor: AppColors.surfaceHigh,
                valueColor: AlwaysStoppedAnimation(c[1].withValues(alpha: 0.9)),
              ),
            ),
          Container(
            width: size - 8,
            height: size - 8,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: unlocked
                  ? LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: c)
                  : const LinearGradient(colors: [Color(0xFF26212F), Color(0xFF17131E)]),
              boxShadow: unlocked
                  ? [BoxShadow(color: c[0].withValues(alpha: 0.45), blurRadius: 16, spreadRadius: -2)]
                  : null,
              border: Border.all(
                  color: unlocked ? Colors.white.withValues(alpha: 0.5) : AppColors.border, width: 1.4),
            ),
            child: Icon(unlocked ? icon : Icons.lock_rounded,
                size: size * 0.42,
                color: unlocked ? const Color(0xFF1B1407).withValues(alpha: 0.85) : AppColors.textMuted),
          ),
        ],
      ),
    );
  }
}

/// Destellos que giran detrás de un elemento (logro nuevo, gran resultado).
class Sunburst extends StatefulWidget {
  final double size;
  final Color color;
  const Sunburst({super.key, this.size = 220, this.color = AppColors.gold});

  @override
  State<Sunburst> createState() => _SunburstState();
}

class _SunburstState extends State<Sunburst> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(seconds: 12))..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) => Transform.rotate(
          angle: _c.value * 2 * math.pi,
          child: CustomPaint(size: Size.square(widget.size), painter: _RaysPainter(widget.color)),
        ),
      ),
    );
  }
}

class _RaysPainter extends CustomPainter {
  final Color color;
  _RaysPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.width / 2;
    final paint = Paint()
      ..shader = RadialGradient(colors: [color.withValues(alpha: 0.35), color.withValues(alpha: 0)])
          .createShader(Rect.fromCircle(center: c, radius: r));
    for (var i = 0; i < 12; i++) {
      final a = i * math.pi / 6;
      final path = Path()
        ..moveTo(c.dx, c.dy)
        ..lineTo(c.dx + r * math.cos(a - 0.11), c.dy + r * math.sin(a - 0.11))
        ..lineTo(c.dx + r * math.cos(a + 0.11), c.dy + r * math.sin(a + 0.11))
        ..close();
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _RaysPainter old) => false;
}
