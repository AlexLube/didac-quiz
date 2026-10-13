import 'package:flutter/material.dart';

/// Estética de sala de cine, hermana de DidacCine Aula: violeta profundo, tarjetas
/// muy redondeadas con borde lila y naranja como color de acción; con personalidad
/// propia: platea oscura, rojo telón y detalles de claqueta y carrete.
class AppColors {
  static const background = Color(0xFF140C2E);
  static const backgroundTop = Color(0xFF241552);
  static const surface = Color(0xFF241947);
  static const surfaceHigh = Color(0xFF33266A);
  static const border = Color(0xFF5B4BA8);
  static const accent = Color(0xFFFF8A3D); // naranja de acción
  static const amber = accent; // compatibilidad con el código anterior
  static const curtain = Color(0xFFD7263D); // rojo telón
  static const gold = Color(0xFFF6C453);
  static const success = Color(0xFF2ECC71);
  static const error = Color(0xFFE74C3C);
  static const text = Color(0xFFFFFFFF);
  static const textMuted = Color(0xFFB9AEE0);

  static const easy = Color(0xFF4FC3F7);
  static const medium = Color(0xFFFFB84D);
  static const hard = Color(0xFFFF5C7A);

  static Color forDifficulty(int d) => d == 1 ? easy : (d == 2 ? medium : hard);

  static const heroGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF5A32B8), Color(0xFFB5307A), Color(0xFFFF8A3D)],
  );

  static const backgroundGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [backgroundTop, background],
  );
}

/// Fondo degradado compartido por todas las pantallas.
class CinemaBackground extends StatelessWidget {
  final Widget child;
  const CinemaBackground({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(gradient: AppColors.backgroundGradient),
      child: child,
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
        borderRadius: BorderRadius.circular(28),
        side: const BorderSide(color: AppColors.border, width: 1.5),
      ),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: AppColors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: AppColors.text),
    ),
    cardTheme: CardThemeData(
      color: AppColors.surface,
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: const BorderSide(color: AppColors.border, width: 1.5),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.accent,
        foregroundColor: Colors.black,
        disabledBackgroundColor: AppColors.surfaceHigh,
        disabledForegroundColor: AppColors.textMuted,
        minimumSize: const Size.fromHeight(56),
        textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size.fromHeight(52),
        foregroundColor: AppColors.text,
        side: const BorderSide(color: AppColors.border, width: 2),
        textStyle: const TextStyle(fontWeight: FontWeight.w800),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: AppColors.accent),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.surface,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(20),
        borderSide: const BorderSide(color: AppColors.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(20),
        borderSide: const BorderSide(color: AppColors.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(20),
        borderSide: const BorderSide(color: AppColors.accent, width: 2),
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: AppColors.background,
      surfaceTintColor: Colors.transparent,
      indicatorColor: AppColors.accent,
      indicatorShape: const StadiumBorder(),
      height: 72,
      iconTheme: WidgetStateProperty.resolveWith(
        (states) => IconThemeData(
          color: states.contains(WidgetState.selected) ? Colors.black : AppColors.textMuted,
        ),
      ),
      labelTextStyle: WidgetStateProperty.resolveWith(
        (states) => TextStyle(
          fontWeight: FontWeight.w800,
          fontSize: 12,
          color: states.contains(WidgetState.selected) ? AppColors.accent : AppColors.textMuted,
        ),
      ),
    ),
    sliderTheme: base.sliderTheme.copyWith(
      activeTrackColor: AppColors.accent,
      inactiveTrackColor: AppColors.surfaceHigh,
      thumbColor: AppColors.accent,
      trackHeight: 8,
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: SegmentedButton.styleFrom(
        selectedBackgroundColor: AppColors.accent,
        selectedForegroundColor: Colors.black,
        side: const BorderSide(color: AppColors.border),
      ),
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(color: AppColors.accent),
  );
}
