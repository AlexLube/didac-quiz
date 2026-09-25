import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../app_state.dart';
import '../models.dart';
import '../services/ads.dart';
import '../services/api.dart';
import '../share_text.dart';
import '../strings.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'auth_screens.dart';

class ResultScreen extends StatefulWidget {
  final bool justFinished;
  final VoidCallback onOpenRankings;
  const ResultScreen({super.key, this.justFinished = false, required this.onOpenRankings});

  @override
  State<ResultScreen> createState() => _ResultScreenState();
}

class _ResultScreenState extends State<ResultScreen> {
  GameSummary? _game;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      // Intersticial al terminar el reto, antes de ver el resultado.
      if (widget.justFinished) await Ads.showInterstitial();
      final g = await AppState.instance.api.gameSummary();
      await AppState.instance.refreshProfile();
      if (mounted) setState(() => _game = g);
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  Future<void> _share() async {
    final g = _game;
    if (g == null) return;
    final text = buildShareText(g, streak: AppState.instance.profile?.streakCurrent ?? 0);
    await SharePlus.instance.share(ShareParams(text: text));
  }

  Future<void> _restoreStreak() async {
    final earned = await Ads.showRewarded();
    if (!mounted) return;
    if (!earned) {
      showSnack(context, tr('ad_not_available'));
      return;
    }
    try {
      final p = await AppState.instance.api.restoreStreak();
      AppState.instance.setProfile(p);
      if (mounted) {
        setState(() {});
        showSnack(context, tr('streak_restored'));
      }
    } on ApiError catch (e) {
      if (mounted) showSnack(context, e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(tr('your_result'))),
      body: SafeArea(child: _body()),
    );
  }

  Widget _body() {
    if (_error != null) return ErrorView(message: tr('error_generic'), onRetry: _load);
    final g = _game;
    if (g == null) return const Center(child: CircularProgressIndicator());
    final state = AppState.instance;
    final profile = state.profile;
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            gradient: AppColors.heroGradient,
            borderRadius: BorderRadius.circular(24),
          ),
          child: Column(
            children: [
              TweenAnimationBuilder<int>(
                tween: IntTween(begin: 0, end: g.totalPoints),
                duration: const Duration(milliseconds: 1200),
                curve: Curves.easeOutCubic,
                builder: (context, v, _) => Text(
                  '$v',
                  style: const TextStyle(fontSize: 72, fontWeight: FontWeight.w900, color: Colors.white),
                ),
              ),
              Text(tr('points_of', {'p': g.totalPoints, 'max': g.maxPoints}),
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
              const SizedBox(height: 16),
              _AnswerGrid(g),
              const SizedBox(height: 16),
              Text('${tr('total_time')}: ${formatDuration(g.totalMs)}',
                  style: const TextStyle(color: Colors.white70)),
              if (profile != null && profile.streakCurrent > 0)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text('🔥 ${tr('streak')}: ${profile.streakCurrent} ${tr('days')}',
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        FilledButton.icon(
          onPressed: _share,
          icon: const Icon(Icons.ios_share_rounded),
          label: Text(tr('share')),
        ),
        const SizedBox(height: 12),
        if (state.isGuest)
          OutlinedButton.icon(
            onPressed: () async {
              await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const AccountScreen()));
              if (mounted) setState(() {});
            },
            icon: const Icon(Icons.person_add_alt_1_rounded),
            label: Text(tr('create_account_to_rank')),
          )
        else
          OutlinedButton.icon(
            onPressed: () {
              Navigator.of(context).popUntil((r) => r.isFirst);
              widget.onOpenRankings();
            },
            icon: const Icon(Icons.emoji_events_rounded),
            label: Text(tr('see_rankings')),
          ),
        if (profile != null && profile.canRestoreStreak && profile.streakLost != null) ...[
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Text(tr('streak_lost', {'n': profile.streakLost!})),
                  const SizedBox(height: 8),
                  TextButton.icon(
                    onPressed: _restoreStreak,
                    icon: const Icon(Icons.play_circle_rounded),
                    label: Text(tr('restore_streak')),
                  ),
                ],
              ),
            ),
          ),
        ],
        const SizedBox(height: 20),
        Text(tr('solutions_tomorrow'),
            textAlign: TextAlign.center, style: const TextStyle(color: AppColors.textMuted)),
      ],
    );
  }
}

class _AnswerGrid extends StatelessWidget {
  final GameSummary game;
  const _AnswerGrid(this.game);

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
                false => AppColors.error,
                null => Colors.black26,
              },
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              '${byPos[i]?.points ?? 0}',
              style: const TextStyle(fontWeight: FontWeight.w900, color: Colors.white),
            ),
          ),
      ],
    );
  }
}
