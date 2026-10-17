import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../app_state.dart';
import '../models.dart';
import '../share_text.dart';
import '../strings.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../services/achievements.dart';
import '../widgets/marquee.dart';
import '../widgets/season.dart';
import '../widgets/unlock_dialog.dart';
import 'achievements_screen.dart';
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
  void initState() {
    super.initState();
    _celebrateNew();
  }

  /// Avisa de los logros conseguidos desde la última visita (también los ganados en la web).
  Future<void> _celebrateNew() async {
    final fresh = await Achievements.instance.takeNew();
    if (mounted && fresh.isNotEmpty) await showAchievementsUnlocked(context, fresh);
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      TodayTab(
        onOpenRankings: () => setState(() => _tab = 1),
        onOpenAchievements: () => setState(() => _tab = 2),
      ),
      const RankingsScreen(),
      const AchievementsScreen(),
      const ProfileScreen(),
    ];
    return Scaffold(
      extendBody: true,
      body: SafeArea(bottom: false, child: IndexedStack(index: _tab, children: pages)),
      bottomNavigationBar: _CinemaNavBar(
        index: _tab,
        onTap: (i) => setState(() => _tab = i),
        items: [
          (Icons.local_movies_rounded, tr('tab_today')),
          (Icons.leaderboard_rounded, tr('tab_rankings')),
          (Icons.military_tech_rounded, tr('tab_achievements')),
          (Icons.person_rounded, tr('tab_profile')),
        ],
      ),
    );
  }
}

/// Barra inferior flotante de cristal con indicador dorado.
class _CinemaNavBar extends StatelessWidget {
  final int index;
  final ValueChanged<int> onTap;
  final List<(IconData, String)> items;
  const _CinemaNavBar({required this.index, required this.onTap, required this.items});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
        child: GlassCard(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
          child: Row(
            children: [
              for (var i = 0; i < items.length; i++)
                Expanded(
                  child: Semantics(
                    button: true,
                    selected: i == index,
                    label: items[i].$2,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => onTap(i),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 260),
                        curve: Curves.easeOutCubic,
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(16),
                          gradient: i == index ? AppColors.goldGradient : null,
                          boxShadow: i == index
                              ? [BoxShadow(color: AppColors.accent.withValues(alpha: 0.35), blurRadius: 14)]
                              : null,
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(items[i].$1,
                                size: 22, color: i == index ? const Color(0xFF241705) : AppColors.textMuted),
                            const SizedBox(height: 2),
                            ExcludeSemantics(
                              child: Text(items[i].$2,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                      color: i == index ? const Color(0xFF241705) : AppColors.textMuted)),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class TodayTab extends StatefulWidget {
  final VoidCallback onOpenRankings;
  final VoidCallback onOpenAchievements;
  const TodayTab({super.key, required this.onOpenRankings, required this.onOpenAchievements});

  @override
  State<TodayTab> createState() => _TodayTabState();
}

class _TodayTabState extends State<TodayTab> {
  TodayInfo? _today;
  Map<String, dynamic>? _special;
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
      _loadSpecial();
      if (t.profile != null) AppState.instance.setProfile(t.profile!);
      if (mounted) setState(() => _today = t);
    } catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Fecha especial de hoy o la próxima de los 21 días siguientes.
  Future<void> _loadSpecial() async {
    try {
      final rows = asMapList(await Supabase.instance.client.from('special_dates').select());
      final now = DateTime.now();
      Map<String, dynamic>? best;
      for (var d = 0; d <= 21 && best == null; d++) {
        final day = now.add(Duration(days: d));
        final key = '${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}';
        final hit = rows.where((r) => r['date_key'] == key).firstOrNull;
        if (hit != null) best = {...hit, '_today': d == 0, '_in': d};
      }
      if (mounted) setState(() => _special = best);
    } catch (_) {}
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
        padding: const EdgeInsets.fromLTRB(18, 14, 18, 110),
        children: [
          Row(
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  GoldText('DIDACCINE', style: AppFonts.marquee(40, spacing: 3)),
                  Transform.translate(
                    offset: const Offset(0, -4),
                    child: Text('QUIZ  ·  ${tr('tagline').toUpperCase()}',
                        style: const TextStyle(
                            fontSize: 10.5, letterSpacing: 2.2, fontWeight: FontWeight.w700, color: AppColors.textMuted)),
                  ),
                ],
              ),
              const Spacer(),
              if (profile != null) _StreakChip(profile.streakCurrent),
            ],
          ),
          const SizedBox(height: 16),
          _ChallengeCard(today: t, onPlay: t.available ? _play : null),
          const SizedBox(height: 14),
          if (_special != null) ...[
            _SpecialBanner(_special!),
            const SizedBox(height: 14),
          ],
          Row(
            children: [
              Expanded(
                child: _InfoTile(
                  icon: Icons.contrast_rounded,
                  value: '${t.jokersLeft}/3',
                  label: tr('jokers_left'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _InfoTile(
                  icon: Icons.schedule_rounded,
                  value: formatCountdown(untilNextChallenge()),
                  label: tr('new_challenge_in', {'t': ''}).trim(),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          SectionTitle(tr('tab_achievements'),
              trailing: TextButton(onPressed: widget.onOpenAchievements, child: Text(tr('see_all')))),
          _AchievementsStrip(onTap: widget.onOpenAchievements),
          const SizedBox(height: 14),
          if (state.isGuest)
            GlassCard(
              borderColor: AppColors.accent.withValues(alpha: 0.45),
              onTap: () async {
                await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const AccountScreen()));
                _load();
              },
              child: Row(children: [
                const Icon(Icons.person_add_alt_1_rounded, color: AppColors.accent),
                const SizedBox(width: 12),
                Expanded(
                    child: Text(tr('guest_banner'),
                        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14, height: 1.3))),
                const Icon(Icons.chevron_right_rounded, color: AppColors.textMuted),
              ]),
            ),
          const SizedBox(height: 10),
          GlassCard(
            onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SolutionsScreen())),
            child: Row(children: [
              const Icon(Icons.lightbulb_rounded, color: AppColors.accent),
              const SizedBox(width: 12),
              Expanded(
                  child: Text(tr('yesterday_solutions'),
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14))),
              const Icon(Icons.chevron_right_rounded, color: AppColors.textMuted),
            ]),
          ),
        ],
      ),
    );
  }
}

/// Cartel del reto de hoy, enmarcado con bombillas de marquesina.
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
    final tag = today.available && today.kind != 'general'
        ? (today.kind == 'special' ? tr('special_day') : tr('spotlight_day'))
        : tr('now_showing');
    return MarqueeFrame(
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
        decoration: BoxDecoration(
          color: const Color(0xFF0B0910),
          borderRadius: BorderRadius.circular(15),
          border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: SeasonTheme.current.tag,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(tag.toUpperCase(),
                      style: const TextStyle(
                          color: Colors.white, fontWeight: FontWeight.w800, fontSize: 10.5, letterSpacing: 1.4)),
                ),
                const Spacer(),
                Text(
                  '${d.day.toString().padLeft(2, '0')}·${d.month.toString().padLeft(2, '0')}·${d.year}',
                  style: AppFonts.marquee(20, color: AppColors.textMuted),
                ),
              ],
            ),
            const SizedBox(height: 14),
            GoldText(title.toUpperCase(), style: AppFonts.marquee(44, spacing: 1.2)),
            const SizedBox(height: 10),
            if (!today.available)
              Text(tr('no_challenge'), style: const TextStyle(color: AppColors.textMuted))
            else ...[
              Wrap(spacing: 8, runSpacing: 8, children: [
                _Pill(Icons.quiz_rounded, tr('ten_questions')),
                _Pill(Icons.workspace_premium_rounded,
                    tr('up_to_points', {'max': today.maxPoints > 0 ? today.maxPoints : (today.game?.maxPoints ?? 18)})),
                _Pill(Icons.movie_filter_rounded, tr('with_media')),
              ]),
              if (today.game != null && today.status == 'finished') ...[
                const SizedBox(height: 16),
                Row(children: [
                  const Icon(Icons.stars_rounded, color: AppColors.gold, size: 26),
                  const SizedBox(width: 8),
                  Text(tr('points_of', {'p': today.game!.totalPoints, 'max': today.game!.maxPoints}),
                      style: AppFonts.marquee(30)),
                ]),
              ],
              const SizedBox(height: 18),
              GlowButton(
                icon: today.status == 'finished' ? Icons.bar_chart_rounded : Icons.play_arrow_rounded,
                label: buttonLabel,
                onPressed: onPlay,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  final IconData icon;
  final String text;
  const _Pill(this.icon, this.text);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 15, color: AppColors.accent),
        const SizedBox(width: 6),
        Text(text, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
      ]),
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
        gradient: streak > 0 ? AppColors.curtainGradient : null,
        color: streak > 0 ? null : AppColors.surface,
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
        boxShadow: streak > 0 ? [BoxShadow(color: AppColors.curtain.withValues(alpha: 0.4), blurRadius: 14)] : null,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.local_fire_department_rounded, color: AppColors.gold, size: 20),
          const SizedBox(width: 4),
          Text('$streak', style: AppFonts.marquee(24)),
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
    return GlassCard(
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
                color: AppColors.accent.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(12)),
            child: Icon(icon, color: AppColors.accent, size: 20),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(value, style: AppFonts.marquee(26)),
              Text(label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: AppColors.textMuted, fontSize: 11.5, height: 1.15)),
            ]),
          ),
        ],
      ),
    );
  }
}

/// Resumen de logros en el inicio: progreso y los últimos conseguidos.
class _AchievementsStrip extends StatelessWidget {
  final VoidCallback onTap;
  const _AchievementsStrip({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final ach = Achievements.instance;
    return ListenableBuilder(
      listenable: ach,
      builder: (context, _) {
        final unlocked = ach.progress.unlocked;
        final byId = {for (final a in ach.catalog) a.id: a};
        final recent = unlocked.reversed.map((id) => byId[id]).whereType<Achievement>().take(4).toList();
        // Siguiente logro: el pendiente más cercano a conseguirse.
        double r(Achievement a) => ach.progress.ratio(a).clamp(0, 0.999).toDouble();
        final next = ach.catalog.where((a) => !unlocked.contains(a.id)).toList()
          ..sort((a, b) => r(b).compareTo(r(a)));
        final total = ach.catalog.isEmpty ? 100 : ach.catalog.length;
        return GlassCard(
          onTap: onTap,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Text('${unlocked.length}', style: AppFonts.marquee(34, color: AppColors.accent)),
                Text(' / $total', style: AppFonts.marquee(22, color: AppColors.textMuted)),
                const SizedBox(width: 10),
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(99),
                    child: LinearProgressIndicator(
                      value: unlocked.length / total,
                      minHeight: 8,
                      backgroundColor: AppColors.surfaceHigh,
                      valueColor: const AlwaysStoppedAnimation(AppColors.accent),
                    ),
                  ),
                ),
              ]),
              if (recent.isNotEmpty) ...[
                const SizedBox(height: 14),
                Row(children: [
                  for (final a in recent)
                    Padding(
                      padding: const EdgeInsets.only(right: 10),
                      child: Medal(icon: a.icon, tier: tierForPoints(a.points), unlocked: true, size: 48),
                    ),
                ]),
              ],
              if (next.isNotEmpty) ...[
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.background.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Row(children: [
                    Medal(
                        icon: next.first.icon,
                        tier: tierForPoints(next.first.points),
                        unlocked: false,
                        size: 44,
                        progress: ach.progress.ratio(next.first)),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(tr('ach_next').toUpperCase(),
                            style: const TextStyle(color: AppColors.textMuted, fontSize: 11, letterSpacing: 1.2)),
                        Text(Strings.pick(next.first.title),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                      ]),
                    ),
                    Text('${ach.progress.current(next.first).clamp(0, next.first.target)}/${next.first.target}',
                        style: AppFonts.marquee(22, color: AppColors.accent)),
                  ]),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

/// Aviso de fecha especial (Navidad, Halloween...): +1 punto extra al jugar.
class _SpecialBanner extends StatelessWidget {
  final Map<String, dynamic> day;
  const _SpecialBanner(this.day);

  @override
  Widget build(BuildContext context) {
    final isToday = day['_today'] == true;
    final name = Strings.lang == 'es' ? day['name_es'] : day['name_en'];
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: isToday ? AppColors.curtainGradient : null,
        color: isToday ? null : AppColors.surface,
        border: Border.all(color: AppColors.gold.withValues(alpha: isToday ? 0.6 : 0.25)),
      ),
      child: Row(children: [
        Text(_emoji('${day['date_key']}'), style: const TextStyle(fontSize: 30)),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('$name', style: AppFonts.marquee(24)),
            Text(isToday ? tr('special_today', {'p': day['bonus_points']}) : tr('special_soon', {'d': day['_in']}),
                style: TextStyle(color: isToday ? Colors.white : AppColors.textMuted, fontSize: 12.5)),
          ]),
        ),
      ]),
    );
  }

  static String _emoji(String key) => switch (key) {
        '01-01' => '🎆',
        '02-14' => '💘',
        '10-31' => '🎃',
        '12-01' => '🎂',
        '12-25' => '🎄',
        '12-28' => '🎞️',
        _ => '⭐',
      };
}
