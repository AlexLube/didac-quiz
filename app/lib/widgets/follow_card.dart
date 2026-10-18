import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config.dart';
import '../services/achievements.dart';
import '../strings.dart';
import '../theme.dart';
import 'marquee.dart';
import 'unlock_dialog.dart';

/// Tarjeta «Únete a la comunidad»: botones a Instagram y Facebook.
/// Visitar cada red da una medalla especial (sin puntos: Meta no permite
/// premiar seguir y no se puede comprobar si alguien sigue de verdad).
class FollowCard extends StatefulWidget {
  /// Si es true, la tarjeta desaparece cuando ya tiene las dos medallas.
  final bool hideWhenDone;
  const FollowCard({super.key, this.hideWhenDone = false});

  @override
  State<FollowCard> createState() => _FollowCardState();
}

class _FollowCardState extends State<FollowCard> {
  @override
  void initState() {
    super.initState();
    if (!Achievements.instance.loaded) Achievements.instance.load();
  }

  @override
  Widget build(BuildContext context) {
    final ach = Achievements.instance;
    return ListenableBuilder(
      listenable: ach,
      builder: (context, _) {
        final done = ach.isFan;
        if (done && widget.hideWhenDone) return const SizedBox.shrink();
        final guest = Supabase.instance.client.auth.currentUser == null;
        return GlassCard(
          borderColor: AppColors.gold.withValues(alpha: 0.45),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const Icon(Icons.favorite_rounded, color: AppColors.gold, size: 22),
              const SizedBox(width: 10),
              Expanded(
                child: Text(tr(done ? 'follow_done' : 'follow_title'),
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
              ),
            ]),
            if (!done) ...[
              const SizedBox(height: 6),
              Text(tr('follow_text'), style: const TextStyle(color: AppColors.textMuted, height: 1.35)),
            ],
            const SizedBox(height: 12),
            const FollowButtons(),
            if (guest && !done) ...[
              const SizedBox(height: 8),
              Text(tr('follow_guest'), style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
            ],
          ]),
        );
      },
    );
  }
}

/// Botones de Instagram y Facebook. Con [only] se muestra solo uno.
class FollowButtons extends StatelessWidget {
  final String? only;
  final VoidCallback? onDone;
  const FollowButtons({super.key, this.only, this.onDone});

  static const _networks = {
    'instagram': ('Instagram', Icons.camera_alt_rounded, [Color(0xFFF58529), Color(0xFFDD2A7B), Color(0xFF8134AF)]),
    'facebook': ('Facebook', Icons.facebook_rounded, [Color(0xFF1877F2), Color(0xFF0F5BC4)]),
  };

  Future<void> _open(BuildContext context, String network) async {
    final url = network == 'instagram' ? Config.instagramUrl : Config.facebookUrl;
    await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    final fresh = await Achievements.instance.claimSocial(network);
    onDone?.call();
    if (fresh.isNotEmpty && context.mounted) await showAchievementsUnlocked(context, fresh);
  }

  @override
  Widget build(BuildContext context) {
    final unlocked = Achievements.instance.unlocked;
    final list = _networks.entries.where((e) => only == null || e.key == only).toList();
    return Row(children: [
      for (final (i, e) in list.indexed) ...[
        if (i > 0) const SizedBox(width: 10),
        Expanded(
          child: _NetworkButton(
            label: e.value.$1,
            icon: e.value.$2,
            colors: e.value.$3,
            done: unlocked.contains('social_${e.key}'),
            onTap: () => _open(context, e.key),
          ),
        ),
      ],
    ]);
  }
}

class _NetworkButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final List<Color> colors;
  final bool done;
  final VoidCallback onTap;
  const _NetworkButton(
      {required this.label, required this.icon, required this.colors, required this.done, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Ink(
          height: 46,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            gradient: LinearGradient(colors: colors),
          ),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(icon, color: Colors.white, size: 20),
            const SizedBox(width: 8),
            Text(label, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
            if (done) ...[
              const SizedBox(width: 6),
              const Icon(Icons.check_circle_rounded, color: Colors.white, size: 18),
            ],
          ]),
        ),
      ),
    );
  }
}
