import 'package:flutter/material.dart';

/// Estética minimalista y moderna inspirada en DidacCine.com:
/// fondo negro cine profundo, tarjetas pizarra con bordes muy sutiles,
/// tipografía limpia y acentos ámbar/dorado cinematográfico.
class AppColors {
  static const background = Color(0xFF0A0C10);
  static const backgroundTop = Color(0xFF121620);
  static const surface = Color(0xFF161B26);
  static const surfaceHigh = Color(0xFF202736);
  static const border = Color(0xFF2A3246);
  static const accent = Color(0xFFF59E0B); // Ámbar cinematográfico moderno
  static const amber = accent;
  static const curtain = Color(0xFFE11D48); // Rojo carmesí moderno
  static const gold = Color(0xFFFBBF24);
  static const success = Color(0xFF10B981);
  static const error = Color(0xFFEF4444);
  static const text = Color(0xFFF8FAFC);
  static const textMuted = Color(0xFF94A3B8);

  static const easy = Color(0xFF38BDF8);
  static const medium = Color(0xFFFBBF24);
  static const hard = Color(0xFFF43F5E);

  static Color forDifficulty(int d) => d == 1 ? easy : (d == 2 ? medium : hard);

  static const heroGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF1E293B), Color(0xFF0F172A)],
  );

  static const backgroundGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [backgroundTop, background],
  );
}

/// Fondo minimalista compartido por todas las pantallas.
/// En pantallas anchas (Web / Desktop), centra el contenido con proporción móvil/tablet limpia.
class CinemaBackground extends StatelessWidget {
  final Widget child;
  const CinemaBackground({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(gradient: AppColors.backgroundGradient),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: child,
        ),
      ),
    );
  }
}

ThemeData buildTheme() {
  final base = ThemeData(
    useMaterial3: true,
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
        fontSize: 20,
        fontWeight: FontWeight.w800,
        letterSpacing: -0.3,
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
        foregroundColor: const Color(0xFF0A0C10),
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
        selectedForegroundColor: const Color(0xFF0A0C10),
        side: const BorderSide(color: AppColors.border),
      ),
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(color: AppColors.accent),
  );
}
