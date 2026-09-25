import 'package:didac_quiz/models.dart';
import 'package:didac_quiz/share_text.dart';
import 'package:didac_quiz/strings.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final summaryJson = {
    'date': '2026-09-25',
    'finished': true,
    'position': 10,
    'total_points': 14,
    'max_points': 18,
    'total_ms': 92400,
    'answers': [
      for (var i = 0; i < 10; i++)
        {
          'position': i,
          'difficulty': i < 4 ? 1 : (i < 8 ? 2 : 3),
          'correct': i != 2 && i != 9,
          'points': i == 2 || i == 9 ? 0 : (i < 4 ? 1 : (i < 8 ? 2 : 3)),
          'elapsed_ms': 9240,
          'joker_used': false,
        }
    ],
  };

  test('el texto para compartir no revela respuestas', () {
    final g = GameSummary.fromJson(summaryJson);
    final text = buildShareText(g, streak: 5);
    expect(text, contains('Didac-Quiz 25/09/2026 · 14/18'));
    expect(text, contains('🟩🟩🟥🟩 🟩🟩🟩🟩 🟩🟥'));
    expect(text, contains('⏱ 1:32 · 🔥 5'));
  });

  test('cuenta atrás hasta la medianoche UTC', () {
    final d = untilNextChallenge(DateTime.utc(2026, 9, 25, 22, 30));
    expect(d, const Duration(hours: 1, minutes: 30));
    expect(formatCountdown(d), '1h 30m');
  });

  test('pregunta: comodín solo con 4 opciones de elección', () {
    final q = Question.fromJson({
      'position': 0,
      'id': 1,
      'format': 'choice',
      'difficulty': 2,
      'prompt': {'es': '¿Quién?', 'en': 'Who?'},
      'options': [
        {'es': 'A'},
        {'es': 'B'},
        {'es': 'C'},
        {'es': 'D'}
      ],
      'time_limit_ms': 20000,
      'remaining_ms': 15000,
      'removed_options': [],
    });
    expect(q.jokerAllowed, isTrue);
    expect(q.isOrder, isFalse);
  });

  test('textos en dos idiomas', () {
    Strings.lang = 'en';
    expect(tr('play'), 'Play');
    expect(Strings.pick({'es': 'Hola', 'en': 'Hello'}), 'Hello');
    Strings.lang = 'es';
    expect(tr('points_of', {'p': 3, 'max': 18}), '3 de 18 puntos');
    expect(tr('clave_inexistente'), 'clave_inexistente');
  });
}
