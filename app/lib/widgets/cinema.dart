import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models.dart';
import '../share_text.dart';
import '../strings.dart';
import '../theme.dart';

/// Barra de progreso minimalista de 10 pasos (estilo moderno).
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
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          for (var i = 0; i < 10; i++)
            Expanded(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                curve: Curves.easeOut,
                height: i == current ? 8 : 6,
                margin: const EdgeInsets.symmetric(horizontal: 2.5),
                decoration: BoxDecoration(
                  color: _frame(i),
                  borderRadius: BorderRadius.circular(99),
                  boxShadow: i == current
                      ? [BoxShadow(color: AppColors.accent.withValues(alpha: 0.4), blurRadius: 6)]
                      : null,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Tarjeta de resultados minimalista con estética de pase VIP de cine.
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
    return Container(
      decoration: BoxDecoration(
        gradient: AppColors.heroGradient,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AppColors.accent.withValues(alpha: 0.35), width: 1.2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.35),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      padding: const EdgeInsets.fromLTRB(24, 22, 24, 22),
      child: Column(
        children: [
          Row(
            children: [
              const Icon(Icons.local_movies_rounded, color: AppColors.accent, size: 20),
              const SizedBox(width: 8),
              const Text('DIDACCINE QUIZ',
                  style: TextStyle(
                      color: AppColors.text,
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.6)),
              const Spacer(),
              Text(date,
                  style: const TextStyle(
                      color: AppColors.textMuted, fontSize: 13, fontWeight: FontWeight.w600)),
            ],
          ),
          if (title != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(title!,
                    style: const TextStyle(color: AppColors.text, fontWeight: FontWeight.w700)),
              ),
            ),
          const SizedBox(height: 18),
          TweenAnimationBuilder<int>(
            tween: IntTween(begin: 0, end: game.totalPoints),
            duration: const Duration(milliseconds: 1000),
            curve: Curves.easeOutCubic,
            builder: (context, v, _) => Row(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text('$v',
                    style: const TextStyle(
                        fontSize: 72,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -2,
                        color: AppColors.text)),
                Text(' / ${game.maxPoints}',
                    style: const TextStyle(
                        fontSize: 24, fontWeight: FontWeight.w700, color: AppColors.textMuted)),
              ],
            ),
          ),
          Text(tr('points_word').toUpperCase(),
              style: const TextStyle(
                  color: AppColors.accent,
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 2.5)),
          const SizedBox(height: 20),
          Divider(color: AppColors.border.withValues(alpha: 0.8), height: 1),
          const SizedBox(height: 20),
          _Grid(game),
          const SizedBox(height: 18),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.timer_outlined, color: AppColors.textMuted, size: 17),
              const SizedBox(width: 5),
              Text(formatDuration(game.totalMs),
                  style: const TextStyle(color: AppColors.text, fontWeight: FontWeight.w700)),
              if (streak > 1) ...[
                const SizedBox(width: 18),
                const Icon(Icons.local_fire_department_rounded, color: AppColors.accent, size: 19),
                const SizedBox(width: 3),
                Text('$streak',
                    style: const TextStyle(color: AppColors.text, fontWeight: FontWeight.w800)),
              ],
            ],
          ),
        ],
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
            width: 42,
            height: 42,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: switch (byPos[i]?.correct) {
                true => AppColors.success.withValues(alpha: 0.2),
                false => (byPos[i]?.points ?? 0) > 0
                    ? AppColors.gold.withValues(alpha: 0.2)
                    : AppColors.curtain.withValues(alpha: 0.2),
                null => AppColors.surfaceHigh,
              },
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: switch (byPos[i]?.correct) {
                  true => AppColors.success,
                  false => (byPos[i]?.points ?? 0) > 0 ? AppColors.gold : AppColors.curtain,
                  null => AppColors.border,
                },
                width: 1.5,
              ),
            ),
            child: Text('${byPos[i]?.points ?? 0}',
                style: TextStyle(
                    fontWeight: FontWeight.w800,
                    color: switch (byPos[i]?.correct) {
                      true => AppColors.success,
                      false => (byPos[i]?.points ?? 0) > 0 ? AppColors.gold : AppColors.curtain,
                      null => AppColors.textMuted,
                    })),
          ),
      ],
    );
  }
}

/// Confeti sutil para los buenos resultados.
class ConfettiBurst extends StatefulWidget {
  const ConfettiBurst({super.key});

  @override
  State<ConfettiBurst> createState() => _ConfettiBurstState();
}

class _ConfettiBurstState extends State<ConfettiBurst> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 3200))..forward();
  final _rng = math.Random(7);
  late final List<_Piece> _pieces = List.generate(55, (_) => _Piece(_rng));

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
        builder: (context, _) =>
            CustomPaint(painter: _ConfettiPainter(_pieces, _c.value), size: Size.infinite),
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
        size = 5 + r.nextDouble() * 5,
        phase = r.nextDouble() * 6.28,
        color = const [
          AppColors.accent,
          AppColors.gold,
          AppColors.success,
          Colors.white,
        ][r.nextInt(4)];
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
      canvas.drawRect(
          Rect.fromCenter(center: Offset.zero, width: p.size, height: p.size * 0.6),
          Paint()..color = p.color.withValues(alpha: (1 - t).clamp(0.2, 1.0)));
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _ConfettiPainter old) => old.t != t;
}

/// Insignias minimalistas por rachas.
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
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: bestStreak >= days
                        ? AppColors.accent.withValues(alpha: 0.15)
                        : AppColors.surface,
                    border: Border.all(
                        color: bestStreak >= days ? AppColors.accent : AppColors.border,
                        width: 1.5),
                  ),
                  child: Icon(icon,
                      size: 26,
                      color: bestStreak >= days ? AppColors.accent : AppColors.textMuted),
                ),
                const SizedBox(height: 6),
                Text(tr(key),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: bestStreak >= days ? AppColors.text : AppColors.textMuted)),
              ],
            ),
          ),
      ],
    );
  }
}
