import 'models.dart';

/// Texto para compartir el resultado sin revelar respuestas.
/// Ejemplo:
///   Didac-Quiz 25/09/2026 · 14/18
///   🟩🟩🟥🟩 🟩🟩🟩⬛ 🟩🟥
///   ⏱ 1:32 · 🔥 5
String buildShareText(GameSummary g, {int streak = 0, String lang = 'es'}) {
  String cell(AnswerSummary? a) {
    if (a == null || a.correct == null) return '⬛';
    return a.correct! ? '🟩' : '🟥';
  }

  final byPos = {for (final a in g.answers) a.position: a};
  final groups = [
    [0, 1, 2, 3],
    [4, 5, 6, 7],
    [8, 9],
  ].map((group) => group.map((p) => cell(byPos[p])).join()).join(' ');

  final d = g.date;
  final date = '${_two(d.day)}/${_two(d.month)}/${d.year}';
  final lines = [
    'Didac-Quiz $date · ${g.totalPoints}/${g.maxPoints}',
    groups,
    '⏱ ${formatDuration(g.totalMs)}${streak > 1 ? ' · 🔥 $streak' : ''}',
  ];
  return lines.join('\n');
}

String formatDuration(int ms) {
  final totalSeconds = (ms / 1000).round();
  final m = totalSeconds ~/ 60;
  final s = totalSeconds % 60;
  return '$m:${_two(s)}';
}

String _two(int n) => n.toString().padLeft(2, '0');

/// Tiempo hasta la próxima medianoche UTC (cuando sale el siguiente reto).
Duration untilNextChallenge([DateTime? now]) {
  final n = (now ?? DateTime.now()).toUtc();
  final next = DateTime.utc(n.year, n.month, n.day + 1);
  return next.difference(n);
}

String formatCountdown(Duration d) {
  final h = d.inHours;
  final m = d.inMinutes % 60;
  return '${h}h ${_two(m)}m';
}
