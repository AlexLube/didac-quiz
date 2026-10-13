import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models.dart';
import '../share_text.dart';
import '../strings.dart';
import '../theme.dart';

/// Barra de progreso en forma de tira de película: 10 fotogramas con perforaciones.
/// Los fotogramas ya jugados se colorean según los puntos obtenidos.
class FilmStrip extends StatelessWidget {
  final int current;
  final List<AnswerSummary> answers;
  const FilmStrip({super.key, required this.current, this.answers = const []});

  Color _frame(int i) {
    if (i == current) return AppColors.accent;
    if (i > current) return AppColors.surfaceHigh;
    final a = answers.where((x) => x.position == i).toList();
    if (a.isEmpty) return AppColors.gold;
    if (a.first.correct == true) return AppColors.success;
    return a.first.points > 0 ? AppColors.gold : AppColors.curtain;
  }

  @override
  Widget build(BuildContext context) {
    Widget holes() => Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            for (var i = 0; i < 24; i++)
              Container(
                width: 5,
                height: 4,
                decoration: BoxDecoration(
                    color: AppColors.background.withValues(alpha: 0.9), borderRadius: BorderRadius.circular(1)),
              ),
          ],
        );
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: const Color(0xFF0B0620),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border.withValues(alpha: 0.6)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          holes(),
          const SizedBox(height: 4),
          Row(
            children: [
              for (var i = 0; i < 10; i++)
                Expanded(
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    height: 16,
                    margin: const EdgeInsets.symmetric(horizontal: 2),
                    decoration: BoxDecoration(color: _frame(i), borderRadius: BorderRadius.circular(3)),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 4),
          holes(),
        ],
      ),
    );
  }
}

/// Entrada de cine con muescas y línea de corte: el resultado del día.
class TicketCard extends StatelessWidget {
  final GameSummary game;
  final int streak;
  final String? title;
  const TicketCard({super.key, required this.game, this.streak = 0, this.title});

  @override
  Widget build(BuildContext context) {
    final d = game.date;
    final date =
        '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
    return ClipPath(
      clipper: _TicketClipper(),
      child: Container(
        decoration: const BoxDecoration(gradient: AppColors.heroGradient),
        padding: const EdgeInsets.fromLTRB(24, 22, 24, 22),
        child: Column(
          children: [
            Row(
              children: [
                const Icon(Icons.movie_creation_rounded, color: Colors.white, size: 22),
                const SizedBox(width: 8),
                const Text('DIDACCINE QUIZ',
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, letterSpacing: 1.4)),
                const Spacer(),
                Text(date, style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.w700)),
              ],
            ),
            if (title != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(title!, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
                ),
              ),
            const SizedBox(height: 14),
            TweenAnimationBuilder<int>(
              tween: IntTween(begin: 0, end: game.totalPoints),
              duration: const Duration(milliseconds: 1200),
              curve: Curves.easeOutCubic,
              builder: (context, v, _) => Row(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text('$v',
                      style: const TextStyle(fontSize: 84, fontWeight: FontWeight.w900, color: Colors.white)),
                  Text(' / ${game.maxPoints}',
                      style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800, color: Colors.white70)),
                ],
              ),
            ),
            Text(tr('points_word'),
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, letterSpacing: 2)),
            const SizedBox(height: 16),
            _DashedLine(),
            const SizedBox(height: 16),
            _Grid(game),
            const SizedBox(height: 14),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.timer_outlined, color: Colors.white70, size: 18),
                const SizedBox(width: 4),
                Text(formatDuration(game.totalMs),
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
                if (streak > 1) ...[
                  const SizedBox(width: 16),
                  const Icon(Icons.local_fire_department_rounded, color: Colors.white, size: 20),
                  const SizedBox(width: 2),
                  Text('$streak', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Grid extends StatelessWidget {
  final GameSummary game;
  const _Grid(this.game);

  @override
  Widget build(BuildContext context) {
    final byPos = {for (final a in game.answers) a.position: a};
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 8,
      runSpacing: 8,
      children: [
        for (var i = 0; i < 10; i++)
          Container(
            width: 44,
            height: 44,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: switch (byPos[i]?.correct) {
                true => AppColors.success,
                false => (byPos[i]?.points ?? 0) > 0 ? AppColors.gold : AppColors.curtain,
                null => Colors.black26,
              },
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.white24, width: 1.5),
            ),
            child: Text('${byPos[i]?.points ?? 0}',
                style: TextStyle(
                    fontWeight: FontWeight.w900,
                    color: (byPos[i]?.correct == false && (byPos[i]?.points ?? 0) > 0)
                        ? Colors.black
                        : Colors.white)),
          ),
      ],
    );
  }
}

class _DashedLine extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      final n = (c.maxWidth / 12).floor();
      return Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          for (var i = 0; i < n; i++) Container(width: 6, height: 2, color: Colors.white38),
        ],
      );
    });
  }
}

class _TicketClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    const r = 16.0;
    final y = size.height * 0.40;
    final path = Path()
      ..addRRect(RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(26)));
    final notches = Path()
      ..addOval(Rect.fromCircle(center: Offset(0, y), radius: r))
      ..addOval(Rect.fromCircle(center: Offset(size.width, y), radius: r));
    return Path.combine(PathOperation.difference, path, notches);
  }

  @override
  bool shouldReclip(covariant CustomClipper<Path> oldClipper) => false;
}

/// Confeti sencillo para los buenos resultados.
class ConfettiBurst extends StatefulWidget {
  const ConfettiBurst({super.key});

  @override
  State<ConfettiBurst> createState() => _ConfettiBurstState();
}

class _ConfettiBurstState extends State<ConfettiBurst> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 3200))..forward();
  final _rng = math.Random(7);
  late final List<_Piece> _pieces = List.generate(70, (_) => _Piece(_rng));

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
        builder: (context, _) => CustomPaint(painter: _ConfettiPainter(_pieces, _c.value), size: Size.infinite),
      ),
    );
  }
}

class _Piece {
  final double x, speed, drift, size, phase;
  final Color color;
  _Piece(math.Random r)
      : x = r.nextDouble(),
        speed = 0.5 + r.nextDouble() * 0.7,
        drift = (r.nextDouble() - 0.5) * 0.25,
        size = 5 + r.nextDouble() * 6,
        phase = r.nextDouble() * 6.28,
        color = const [
          AppColors.accent,
          AppColors.gold,
          AppColors.curtain,
          Colors.white,
          Color(0xFF8E6BFF),
        ][r.nextInt(5)];
}

class _ConfettiPainter extends CustomPainter {
  final List<_Piece> pieces;
  final double t;
  _ConfettiPainter(this.pieces, this.t);

  @override
  void paint(Canvas canvas, Size size) {
    for (final p in pieces) {
      final y = -20 + (size.height + 40) * (t * p.speed);
      if (y > size.height) continue;
      final x = size.width * (p.x + p.drift * t) + math.sin(t * 9 + p.phase) * 12;
      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(t * 8 + p.phase);
      canvas.drawRect(Rect.fromCenter(center: Offset.zero, width: p.size, height: p.size * 0.6),
          Paint()..color = p.color.withValues(alpha: (1 - t).clamp(0.2, 1.0)));
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _ConfettiPainter old) => old.t != t;
}

/// Insignias ilustradas por rachas.
class BadgeRow extends StatelessWidget {
  final int bestStreak;
  const BadgeRow({super.key, required this.bestStreak});

  static const _levels = [
    (3, Icons.local_fire_department_rounded, 'badge_streak_3'),
    (7, Icons.theaters_rounded, 'badge_streak_7'),
    (30, Icons.emoji_events_rounded, 'badge_streak_30'),
    (100, Icons.workspace_premium_rounded, 'badge_streak_100'),
  ];

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (final (days, icon, key) in _levels)
          Expanded(
            child: Column(
              children: [
                Container(
                  width: 62,
                  height: 62,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: bestStreak >= days ? AppColors.heroGradient : null,
                    color: bestStreak >= days ? null : AppColors.surfaceHigh,
                    border: Border.all(
                        color: bestStreak >= days ? AppColors.gold : AppColors.border, width: 2.5),
                  ),
                  child: Icon(icon, size: 30, color: bestStreak >= days ? Colors.white : AppColors.textMuted),
                ),
                const SizedBox(height: 6),
                Text(tr(key),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: bestStreak >= days ? AppColors.text : AppColors.textMuted)),
              ],
            ),
          ),
      ],
    );
  }
}
