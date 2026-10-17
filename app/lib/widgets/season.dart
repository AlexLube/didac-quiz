import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

/// Colores de la marquesina según la época del año. Fuera de las fechas
/// señaladas se usa el tema «estreno»: dorado champán con un toque violeta.
class SeasonTheme {
  final String id;
  final List<Color> bulbs; // colores de las bombillas, en orden
  final Color tag; // fondo de la etiqueta «En cartel»
  final Color glow;
  const SeasonTheme(this.id, {required this.bulbs, required this.tag, required this.glow});

  static const estreno = SeasonTheme('estreno',
      bulbs: [Color(0xFFF2D8A0), Color(0xFFB9A6FF)], tag: Color(0xFF6D5BD0), glow: Color(0xFF8E7CFF));
  static const navidad = SeasonTheme('navidad',
      bulbs: [Color(0xFFFF5A5F), Color(0xFFFFF1D6), Color(0xFF3CC184)],
      tag: Color(0xFFC62A3A), glow: Color(0xFFFF5A5F));
  static const halloween = SeasonTheme('halloween',
      bulbs: [Color(0xFFFF8A2A), Color(0xFF9B6BFF)], tag: Color(0xFFE0641A), glow: Color(0xFFFF8A2A));
  static const sanValentin = SeasonTheme('sanvalentin',
      bulbs: [Color(0xFFFF6F9C), Color(0xFFFFC7D6)], tag: Color(0xFFD6336C), glow: Color(0xFFFF6F9C));
  static const verano = SeasonTheme('verano',
      bulbs: [Color(0xFF4FD8C8), Color(0xFFFFB27A)], tag: Color(0xFF169C8E), glow: Color(0xFF4FD8C8));
  static const vueltaAlCole = SeasonTheme('vueltaalcole',
      bulbs: [Color(0xFFFFD25A), Color(0xFF6CB6FF)], tag: Color(0xFF2F7FD8), glow: Color(0xFF6CB6FF));

  static const all = [estreno, navidad, halloween, sanValentin, verano, vueltaAlCole];

  /// Tema para una fecha (calendario de España).
  static SeasonTheme forDate(DateTime d) {
    final md = d.month * 100 + d.day;
    if (md >= 1201 || md <= 106) return navidad; // 1 dic – Reyes
    if (md >= 1024 && md <= 1101) return halloween;
    if (md >= 207 && md <= 214) return sanValentin;
    if (md >= 901 && md <= 915) return vueltaAlCole;
    if (md >= 701 && md <= 831) return verano;
    return estreno;
  }

  /// En la web se puede forzar con ?tema=halloween para probarlo.
  static SeasonTheme get current {
    if (kIsWeb) {
      final forced = Uri.base.queryParameters['tema'];
      for (final t in all) {
        if (t.id == forced) return t;
      }
    }
    return forDate(DateTime.now());
  }
}
