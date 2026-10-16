import 'dart:async';

import 'package:flutter/material.dart';

import '../app_state.dart';
import '../models.dart';
import '../share_text.dart';
import '../strings.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'auth_screens.dart';
import 'play_screen.dart';
import 'profile_screen.dart';
import 'rankings_screen.dart';
import 'result_screen.dart';
import 'solutions_screen.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    final pages = [
      TodayTab(onOpenRankings: () => setState(() => _tab = 1)),
      const RankingsScreen(),
      const ProfileScreen(),
    ];
    return Scaffold(
      body: SafeArea(child: IndexedStack(index: _tab, children: pages)),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: [
          NavigationDestination(
              icon: const Icon(Icons.local_movies_outlined),
              selectedIcon: const Icon(Icons.local_movies_rounded),
              label: tr('tab_today')),
          NavigationDestination(
              icon: const Icon(Icons.emoji_events_outlined),
              selectedIcon: const Icon(Icons.emoji_events_rounded),
              label: tr('tab_rankings')),
          NavigationDestination(
              icon: const Icon(Icons.person_outline_rounded),
              selectedIcon: const Icon(Icons.person_rounded),
              label: tr('tab_profile')),
        ],
      ),
    );
  }
}

class TodayTab extends StatefulWidget {
  final VoidCallback onOpenRankings;
  const TodayTab({super.key, required this.onOpenRankings});

  @override
  State<TodayTab> createState() => _TodayTabState();
}

class _TodayTabState extends State<TodayTab> {
  TodayInfo? _today;
  Object? _error;
  bool _loading = true;
  Timer? _clock;

  @override
  void initState() {
    super.initState();
    _load();
    _clock = Timer.periodic(const Duration(seconds: 30), (_) {
      if (!mounted) return;
      final t = _today;
      final nowUtc = DateTime.now().toUtc();
      if (t != null && DateTime.utc(nowUtc.year, nowUtc.month, nowUtc.day).isAfter(t.date)) {
        _load();
      } else {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _clock?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final t = await AppState.instance.api.today();
      if (t.profile != null) AppState.instance.setProfile(t.profile!);
      if (mounted) setState(() => _today = t);
    } catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _play() async {
    final t = _today!;
    if (t.status == 'finished') {
      await Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => ResultScreen(onOpenRankings: widget.onOpenRankings),
      ));
    } else {
      await Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => PlayScreen(jokersLeft: t.jokersLeft, onOpenRankings: widget.onOpenRankings),
      ));
    }
    _load();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading && _today == null) return const Center(child: CircularProgressIndicator());
    if (_error != null && _today == null) {
      return ErrorView(message: tr('error_generic'), onRetry: _load);
    }
    final t = _today!;
    final state = AppState.instance;
    final profile = state.profile;
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.accent.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.local_movies_rounded, color: AppColors.accent, size: 24),
              ),
              const SizedBox(width: 12),
              Text(tr('app_name'),
                  style: const TextStyle(
                      fontSize: 22, fontWeight: FontWeight.w800, letterSpacing: -0.4)),
              const Spacer(),
              if (profile != null) _StreakChip(profile.streakCurrent),
            ],
          ),
          const SizedBox(height: 22),
          _ChallengeCard(today: t, onPlay: t.available ? _play : null),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _InfoTile(
                  icon: Icons.contrast_rounded,
                  value: '${t.jokersLeft}/3',
                  label: tr('jokers_left'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _InfoTile(
                  icon: Icons.schedule_rounded,
                  value: formatCountdown(untilNextChallenge()),
                  label: tr('new_challenge_in', {'t': ''}).trim(),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (state.isGuest)
            Card(
              child: ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                leading: const Icon(Icons.person_add_alt_1_rounded, color: AppColors.amber),
                title: Text(tr('guest_banner'),
                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                trailing: const Icon(Icons.chevron_right_rounded, color: AppColors.textMuted),
                onTap: () async {
                  await Navigator.of(context)
                      .push(MaterialPageRoute(builder: (_) => const AccountScreen()));
                  _load();
                },
              ),
            ),
          Card(
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              leading: const Icon(Icons.lightbulb_outline_rounded, color: AppColors.amber),
              title: Text(tr('yesterday_solutions'),
                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
              trailing: const Icon(Icons.chevron_right_rounded, color: AppColors.textMuted),
              onTap: () => Navigator.of(context)
                  .push(MaterialPageRoute(builder: (_) => const SolutionsScreen())),
            ),
          ),
        ],
      ),
    );
  }
}

class _ChallengeCard extends StatelessWidget {
  final TodayInfo today;
  final VoidCallback? onPlay;
  const _ChallengeCard({required this.today, required this.onPlay});

  @override
  Widget build(BuildContext context) {
    final title = today.title == null ? tr('today_challenge') : Strings.pick(today.title);
    final d = today.date;
    final buttonLabel = switch (today.status) {
      'in_progress' => tr('continue'),
      'finished' => tr('see_result'),
      _ => tr('play'),
    };
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: AppColors.heroGradient,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AppColors.accent.withValues(alpha: 0.3), width: 1.2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.3),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.accent.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  today.available && today.kind != 'general'
                      ? (today.kind == 'special' ? tr('special_day') : tr('spotlight_day'))
                      : 'DIDACCINE',
                  style: const TextStyle(
                      color: AppColors.accent,
                      fontWeight: FontWeight.w800,
                      fontSize: 11,
                      letterSpacing: 1.2),
                ),
              ),
              const Spacer(),
              Text(
                '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}',
                style: const TextStyle(
                    color: AppColors.textMuted, fontSize: 13, fontWeight: FontWeight.w600),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(title,
              style: const TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.5,
                  color: AppColors.text)),
          const SizedBox(height: 8),
          if (!today.available)
            Text(tr('no_challenge'), style: const TextStyle(color: AppColors.textMuted))
          else ...[
            Text(
                tr('questions_points', {
                  'max': today.maxPoints > 0 ? today.maxPoints : (today.game?.maxPoints ?? 18)
                }),
                style: const TextStyle(
                    color: AppColors.text, fontWeight: FontWeight.w700, fontSize: 14)),
            const SizedBox(height: 4),
            Text(tr('rules_short'),
                style: const TextStyle(color: AppColors.textMuted, fontSize: 13, height: 1.35)),
            if (today.game != null && today.status == 'finished') ...[
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: AppColors.background.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.border),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.Workspace_premium_rounded, color: AppColors.gold, size: 20),
                    const SizedBox(width: 8),
                    Text(
                      tr('points_of', {'p': today.game!.totalPoints, 'max': today.game!.maxPoints}),
                      style: const TextStyle(
                          fontSize: 18, fontWeight: FontWeight.w800, color: AppColors.text),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 20),
            FilledButton.icon(
              icon: Icon(today.status == 'finished'
                  ? Icons.bar_chart_rounded
                  : Icons.play_arrow_rounded),
              onPressed: onPlay,
              label: Text(buttonLabel),
            ),
          ],
        ],
      ),
    );
  }
}

class _StreakChip extends StatelessWidget {
  final int streak;
  const _StreakChip(this.streak);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: AppColors.border, width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.local_fire_department_rounded, color: AppColors.accent, size: 18),
          const SizedBox(width: 4),
          Text('$streak', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
        ],
      ),
    );
  }
}

class _InfoTile extends StatelessWidget {
  final IconData icon;
  final String value;
  final String label;
  const _InfoTile({required this.icon, required this.value, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.border, width: 1)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: AppColors.amber, size: 20),
          const SizedBox(height: 10),
          Text(value,
              style: const TextStyle(
                  fontSize: 20, fontWeight: FontWeight.w800, letterSpacing: -0.3)),
          const SizedBox(height: 2),
          Text(label, style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
        ],
      ),
    );
  }
}
