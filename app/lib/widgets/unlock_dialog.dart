import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/achievements.dart';
import '../strings.dart';
import '../theme.dart';
import 'cinema.dart';
import 'marquee.dart';

/// Celebra, uno detrás de otro, los logros recién conseguidos.
Future<void> showAchievementsUnlocked(BuildContext context, List<Achievement> list) async {
  for (final a in list.take(5)) {
    if (!context.mounted) return;
    HapticFeedback.heavyImpact();
    await showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: tr('close'),
      barrierColor: Colors.black.withValues(alpha: 0.88),
      transitionDuration: const Duration(milliseconds: 420),
      transitionBuilder: (context, anim, _, child) => ScaleTransition(
        scale: CurvedAnimation(parent: anim, curve: Curves.easeOutBack),
        child: FadeTransition(opacity: anim, child: child),
      ),
      pageBuilder: (ctx, _, __) => _UnlockCard(a: a, more: list.length > 1),
    );
  }
}

class _UnlockCard extends StatelessWidget {
  final Achievement a;
  final bool more;
  const _UnlockCard({required this.a, required this.more});

  @override
  Widget build(BuildContext context) {
    final tier = tierForPoints(a.points);
    final c = tierColors(tier);
    return Stack(
      children: [
        Positioned.fill(
          child: BackdropFilter(filter: ui.ImageFilter.blur(sigmaX: 8, sigmaY: 8), child: const SizedBox.expand()),
        ),
        const Positioned.fill(child: ConfettiBurst()),
        Center(
          child: Material(
            type: MaterialType.transparency,
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  GoldText(tr('ach_new').toUpperCase(),
                      style: AppFonts.marquee(30, spacing: 3), textAlign: TextAlign.center),
                  const SizedBox(height: 8),
                  Stack(alignment: Alignment.center, children: [
                    Sunburst(size: 260, color: c[0]),
                    TweenAnimationBuilder<double>(
                      tween: Tween(begin: 0.3, end: 1),
                      duration: const Duration(milliseconds: 900),
                      curve: Curves.elasticOut,
                      builder: (context, s, child) => Transform.scale(scale: s, child: child),
                      child: Medal(icon: a.icon, tier: tier, unlocked: true, size: 132),
                    ),
                  ]),
                  Text(Strings.pick(a.title), textAlign: TextAlign.center, style: AppFonts.marquee(40)),
                  const SizedBox(height: 6),
                  Text(Strings.pick(a.description),
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: AppColors.textMuted, fontSize: 15, height: 1.4)),
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(99),
                      gradient: LinearGradient(colors: c),
                    ),
                    child: Text('+${a.points} ${tr('pts')}',
                        style: AppFonts.marquee(26, color: const Color(0xFF241705))),
                  ),
                  const SizedBox(height: 22),
                  SizedBox(
                    width: 220,
                    child: GlowButton(
                      label: more ? tr('next') : tr('great'),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
