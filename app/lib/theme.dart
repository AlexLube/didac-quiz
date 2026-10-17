import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Estética «sala de cine»: negro terciopelo, dorados de marquesina,
/// rojo butaca y luces que se mueven despacio por el fondo.
class AppColors {
  static const background = Color(0xFF060509);
  static const backgroundTop = Color(0xFF14101C);
  static const surface = Color(0xFF15121D);
  static const surfaceHigh = Color(0xFF221D2E);
  static const border = Color(0xFF332C42);
  static const accent = Color(0xFFF2C14E); // dorado de marquesina
  static const amber = accent;
  static const goldDeep = Color(0xFFC8902E);
  static const curtain = Color(0xFFD7263D); // rojo terciopelo
  static const curtainDeep = Color(0xFF7A0E1E);
  static const gold = Color(0xFFFFD978);
  static const success = Color(0xFF2DD4A0);
  static const error = Color(0xFFFF4D5E);
  static const text = Color(0xFFFBF6EC);
  static const textMuted = Color(0xFFA59EB4);

  static const easy = Color(0xFF5BC0FF);
  static const medium = Color(0xFFF2C14E);
  static const hard = Color(0xFFFF5C7A);

  static Color forDifficulty(int d) => d == 1 ? easy : (d == 2 ? medium : hard);

  static const goldGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFFFFE9A8), Color(0xFFF2C14E), Color(0xFFC8902E)],
  );

  static const curtainGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xFFB0182E), Color(0xFF5E0A17)],
  );

  static const heroGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF2A1B2E), Color(0xFF120E19)],
  );

  static const backgroundGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [backgroundTop, background],
  );
}

/// Tipografías: Bebas Neue para los rótulos de cartelera y Outfit para el resto.
class AppFonts {
  static const display = 'Bebas';
  static const body = 'Outfit';

  static TextStyle marquee(double size, {Color color = AppColors.text, double spacing = 1.5}) =>
      TextStyle(fontFamily: display, fontSize: size, letterSpacing: spacing, height: 1, color: color);
}

/// Fondo de sala de cine: degradado, dos focos que barren despacio y viñeta.
/// En pantallas anchas (web) centra el contenido con proporción de móvil.
class CinemaBackground extends StatefulWidget {
  final Widget child;
  const CinemaBackground({super.key, required this.child});

  @override
  State<CinemaBackground> createState() => _CinemaBackgroundState();
}

class _CinemaBackgroundState extends State<CinemaBackground> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(seconds: 18))..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(gradient: AppColors.backgroundGradient),
      child: Stack(
        children: [
          Positioned.fill(
            child: RepaintBoundary(
              child: AnimatedBuilder(
                animation: _c,
                builder: (context, _) => CustomPaint(painter: _SpotlightPainter(_c.value)),
              ),
            ),
          ),
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: widget.child,
            ),
          ),
        ],
      ),
    );
  }
}

class _SpotlightPainter extends CustomPainter {
  final double t;
  _SpotlightPainter(this.t);

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final a = t * 2 * math.pi;
    void beam(double x, double angle, Color color) {
      final origin = Offset(x, -h * 0.05);
      final path = Path()
        ..moveTo(origin.dx, origin.dy)
        ..lineTo(origin.dx + math.sin(angle - 0.18) * h * 1.2, h * 1.1)
        ..lineTo(origin.dx + math.sin(angle + 0.18) * h * 1.2, h * 1.1)
        ..close();
      canvas.drawPath(
        path,
        Paint()
          ..shader = RadialGradient(
            center: Alignment.topCenter,
            radius: 1.1,
            colors: [color.withValues(alpha: 0.10), color.withValues(alpha: 0.0)],
          ).createShader(Rect.fromLTWH(0, 0, w, h))
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 30),
      );
    }

    beam(w * 0.15, 0.35 + 0.18 * math.sin(a), AppColors.gold);
    beam(w * 0.85, -0.35 + 0.18 * math.sin(a + 2.1), const Color(0xFFFFC2D0));
    // Resplandor rojo del telón, abajo
    canvas.drawRect(
      Rect.fromLTWH(0, h * 0.6, w, h * 0.4),
      Paint()
        ..shader = RadialGradient(
          center: Alignment.bottomCenter,
          radius: 1.0,
          colors: [AppColors.curtain.withValues(alpha: 0.10), Colors.transparent],
        ).createShader(Rect.fromLTWH(0, h * 0.6, w, h * 0.4)),
    );
    // Viñeta
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = RadialGradient(
          radius: 1.0,
          colors: [Colors.transparent, Colors.black.withValues(alpha: 0.45)],
          stops: const [0.6, 1.0],
        ).createShader(Offset.zero & size),
    );
  }

  @override
  bool shouldRepaint(covariant _SpotlightPainter old) => old.t != t;
}

ThemeData buildTheme() {
  final base = ThemeData(
    useMaterial3: true,
    fontFamily: AppFonts.body,
    brightness: Brightness.dark,
    colorScheme: ColorScheme.fromSeed(
      seedColor: AppColors.accent,
      brightness: Brightness.dark,
      surface: AppColors.surface,
    ),
  );
  return base.copyWith(
    scaffoldBackgroundColor: Colors.transparent,
    canvasColor: AppColors.surface,
    dialogTheme: DialogThemeData(
      backgroundColor: AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: const BorderSide(color: AppColors.border, width: 1),
      ),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: AppColors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(
        fontFamily: AppFonts.display,
        fontSize: 28,
        letterSpacing: 1.4,
        color: AppColors.text,
      ),
    ),
    cardTheme: CardThemeData(
      color: AppColors.surface,
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: AppColors.border, width: 1),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.accent,
        foregroundColor: const Color(0xFF1A1206),
        disabledBackgroundColor: AppColors.surfaceHigh,
        disabledForegroundColor: AppColors.textMuted,
        minimumSize: const Size.fromHeight(52),
        elevation: 0,
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, letterSpacing: 0.2),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size.fromHeight(50),
        foregroundColor: AppColors.text,
        side: const BorderSide(color: AppColors.border, width: 1.2),
        textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: AppColors.accent),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.surface,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: AppColors.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: AppColors.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: AppColors.accent, width: 1.5),
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: AppColors.background,
      surfaceTintColor: Colors.transparent,
      indicatorColor: AppColors.accent.withValues(alpha: 0.18),
      indicatorShape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      height: 68,
      iconTheme: WidgetStateProperty.resolveWith(
        (states) => IconThemeData(
          color: states.contains(WidgetState.selected) ? AppColors.accent : AppColors.textMuted,
          size: 22,
        ),
      ),
      labelTextStyle: WidgetStateProperty.resolveWith(
        (states) => TextStyle(
          fontWeight: states.contains(WidgetState.selected) ? FontWeight.w700 : FontWeight.w500,
          fontSize: 11,
          color: states.contains(WidgetState.selected) ? AppColors.accent : AppColors.textMuted,
        ),
      ),
    ),
    sliderTheme: base.sliderTheme.copyWith(
      activeTrackColor: AppColors.accent,
      inactiveTrackColor: AppColors.surfaceHigh,
      thumbColor: AppColors.accent,
      trackHeight: 6,
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: SegmentedButton.styleFrom(
        selectedBackgroundColor: AppColors.accent,
        selectedForegroundColor: const Color(0xFF1A1206),
        side: const BorderSide(color: AppColors.border),
      ),
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(color: AppColors.accent),
  );
}
