import 'package:flutter/material.dart';

import '../app_state.dart';
import '../services/achievements.dart';
import '../strings.dart';
import '../theme.dart';
import '../widgets/marquee.dart';
import 'auth_screens.dart';

/// Pestaña «Logros»: 100 logros en 5 familias y el Hall of Fame mensual.
class AchievementsScreen extends StatefulWidget {
  const AchievementsScreen({super.key});

  @override
  State<AchievementsScreen> createState() => _AchievementsScreenState();
}

class _AchievementsScreenState extends State<AchievementsScreen> {
  final _ach = Achievements.instance;
  String _family = 'all';

  @override
  void initState() {
    super.initState();
    _ach.load();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _ach,
      builder: (context, _) => DefaultTabController(
        length: 2,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 4),
              child: Row(
                children: [
                  GoldText(tr('tab_achievements').toUpperCase(), style: AppFonts.marquee(36, spacing: 2)),
                  const Spacer(),
                  IconButton(
                    tooltip: tr('retry'),
                    onPressed: _ach.load,
                    icon: const Icon(Icons.refresh_rounded, color: AppColors.textMuted),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Container(
                height: 44,
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppColors.border),
                ),
                child: TabBar(
                  dividerColor: Colors.transparent,
                  indicatorSize: TabBarIndicatorSize.tab,
                  indicator: BoxDecoration(gradient: AppColors.goldGradient, borderRadius: BorderRadius.circular(12)),
                  labelColor: const Color(0xFF241705),
                  unselectedLabelColor: AppColors.textMuted,
                  labelStyle: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
                  tabs: [Tab(text: tr('tab_achievements')), const Tab(text: 'Hall of Fame')],
                ),
              ),
            ),
            Expanded(
              child: TabBarView(children: [_achievements(), _hall()]),
            ),
          ],
        ),
      ),
    );
  }

  Widget _achievements() {
    if (!_ach.loaded) return const Center(child: CircularProgressIndicator());
    final unlocked = _ach.unlocked;
    final earned = _ach.catalog.where((a) => unlocked.contains(a.id)).fold<int>(0, (s, a) => s + a.points);
    final list = _ach.catalog.where((a) => _family == 'all' || a.family == _family).toList();
    final guest = AppState.instance.isGuest;
    return RefreshIndicator(
      onRefresh: _ach.load,
      child: CustomScrollView(
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
            sliver: SliverList.list(children: [
              _Summary(unlocked: unlocked.length, total: _ach.catalog.length, points: earned),
              if (guest) ...[
                const SizedBox(height: 12),
                GlassCard(
                  borderColor: AppColors.accent.withValues(alpha: 0.5),
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const AccountScreen())),
                  child: Row(children: [
                    const Icon(Icons.lock_open_rounded, color: AppColors.accent),
                    const SizedBox(width: 12),
                    Expanded(
                        child: Text(tr('ach_guest'),
                            style: const TextStyle(fontWeight: FontWeight.w600, height: 1.3))),
                    const Icon(Icons.chevron_right_rounded, color: AppColors.textMuted),
                  ]),
                ),
              ],
              const SizedBox(height: 16),
              SizedBox(
                height: 38,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: [
                    for (final f in ['all', ...achievementFamilies])
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ChoiceChip(
                          label: Text(f == 'all' ? tr('ach_all') : familyLabel(f)),
                          selected: _family == f,
                          showCheckmark: false,
                          selectedColor: AppColors.accent,
                          backgroundColor: AppColors.surface,
                          side: BorderSide(color: _family == f ? AppColors.accent : AppColors.border),
                          labelStyle: TextStyle(
                              fontWeight: FontWeight.w700,
                              color: _family == f ? const Color(0xFF241705) : AppColors.text),
                          onSelected: (_) => setState(() => _family = f),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
            ]),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 28),
            sliver: SliverGrid.builder(
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 130,
                mainAxisExtent: 156,
                crossAxisSpacing: 8,
                mainAxisSpacing: 8,
              ),
              itemCount: list.length,
              itemBuilder: (context, i) {
                final a = list[i];
                return _AchievementTile(
                  a: a,
                  unlocked: unlocked.contains(a.id),
                  progress: _ach.progress,
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _hall() {
    final hall = _ach.hall;
    if (hall.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.emoji_events_rounded, size: 64, color: AppColors.accent),
            const SizedBox(height: 12),
            GoldText(tr('hall_title').toUpperCase(), style: AppFonts.marquee(30), textAlign: TextAlign.center),
            const SizedBox(height: 8),
            Text(tr('hall_empty'),
                textAlign: TextAlign.center, style: const TextStyle(color: AppColors.textMuted, height: 1.4)),
          ]),
        ),
      );
    }
    final months = <String, List<HallEntry>>{};
    for (final h in hall) {
      months.putIfAbsent(h.yearMonth, () => []).add(h);
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
      children: [
        Text(tr('hall_hint'), style: const TextStyle(color: AppColors.textMuted, height: 1.4)),
        const SizedBox(height: 14),
        for (final e in months.entries) ...[
          SectionTitle(monthName(e.key)),
          Podium(entries: e.value),
          const SizedBox(height: 20),
        ],
      ],
    );
  }
}

String monthName(String yearMonth) {
  final parts = yearMonth.split('-');
  if (parts.length != 2) return yearMonth;
  final m = int.tryParse(parts[1]) ?? 1;
  final names = Strings.lang == 'es'
      ? ['enero', 'febrero', 'marzo', 'abril', 'mayo', 'junio', 'julio', 'agosto', 'septiembre', 'octubre',
          'noviembre', 'diciembre']
      : ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October',
          'November', 'December'];
  return '${names[(m - 1).clamp(0, 11)]} ${parts[0]}';
}

class _Summary extends StatelessWidget {
  final int unlocked;
  final int total;
  final int points;
  const _Summary({required this.unlocked, required this.total, required this.points});

  @override
  Widget build(BuildContext context) {
    final f = total == 0 ? 0.0 : unlocked / total;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: AppColors.heroGradient,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AppColors.accent.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 86,
            height: 86,
            child: Stack(alignment: Alignment.center, children: [
              SizedBox(
                width: 86,
                height: 86,
                child: TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0, end: f),
                  duration: const Duration(milliseconds: 1200),
                  curve: Curves.easeOutCubic,
                  builder: (context, v, _) => CircularProgressIndicator(
                    value: v,
                    strokeWidth: 8,
                    strokeCap: StrokeCap.round,
                    backgroundColor: AppColors.surfaceHigh,
                    valueColor: const AlwaysStoppedAnimation(AppColors.accent),
                  ),
                ),
              ),
              Column(mainAxisSize: MainAxisSize.min, children: [
                Text('$unlocked', style: AppFonts.marquee(32)),
                Text('/ $total', style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
              ]),
            ]),
          ),
          const SizedBox(width: 18),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(tr('ach_unlocked_label'), style: const TextStyle(color: AppColors.textMuted, fontSize: 13)),
              const SizedBox(height: 2),
              GoldText('+$points ${tr('pts')}', style: AppFonts.marquee(34)),
              const SizedBox(height: 4),
              Text(tr('ach_points_hint'),
                  style: const TextStyle(color: AppColors.textMuted, fontSize: 12, height: 1.3)),
            ]),
          ),
        ],
      ),
    );
  }
}

class _AchievementTile extends StatelessWidget {
  final Achievement a;
  final bool unlocked;
  final AchievementProgress progress;
  const _AchievementTile({required this.a, required this.unlocked, required this.progress});

  @override
  Widget build(BuildContext context) {
    final tier = tierForPoints(a.points);
    final c = tierColors(tier);
    return GestureDetector(
      onTap: () => showAchievementDetail(context, a, unlocked, progress),
      child: Container(
        padding: const EdgeInsets.fromLTRB(8, 12, 8, 8),
        decoration: BoxDecoration(
          color: unlocked ? c[1].withValues(alpha: 0.12) : AppColors.surface.withValues(alpha: 0.75),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: unlocked ? c[0].withValues(alpha: 0.5) : AppColors.border),
        ),
        child: Column(
          children: [
            Medal(icon: a.icon, tier: tier, unlocked: unlocked, size: 62, progress: progress.ratio(a)),
            const SizedBox(height: 8),
            Text(Strings.pick(a.title),
                maxLines: 2,
                textAlign: TextAlign.center,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: 12.5,
                    height: 1.15,
                    fontWeight: FontWeight.w700,
                    color: unlocked ? AppColors.text : AppColors.textMuted)),
            const Spacer(),
            Text(
              unlocked ? '+${a.points} ${tr('pts')}' : '${progress.current(a).clamp(0, a.target)}/${a.target}',
              style: TextStyle(
                  fontSize: 11.5, fontWeight: FontWeight.w800, color: unlocked ? c[0] : AppColors.textMuted),
            ),
          ],
        ),
      ),
    );
  }
}

void showAchievementDetail(BuildContext context, Achievement a, bool unlocked, AchievementProgress p) {
  final tier = tierForPoints(a.points);
  showModalBottomSheet<void>(
    context: context,
    builder: (ctx) => Padding(
      padding: const EdgeInsets.fromLTRB(24, 28, 24, 32),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Stack(alignment: Alignment.center, children: [
          if (unlocked) Sunburst(size: 170, color: tierColors(tier)[0]),
          Medal(icon: a.icon, tier: tier, unlocked: unlocked, size: 96, progress: p.ratio(a)),
        ]),
        const SizedBox(height: 10),
        Text(Strings.pick(a.title), textAlign: TextAlign.center, style: AppFonts.marquee(32)),
        const SizedBox(height: 6),
        Text(Strings.pick(a.description),
            textAlign: TextAlign.center, style: const TextStyle(color: AppColors.textMuted, height: 1.4)),
        const SizedBox(height: 16),
        if (!unlocked) ...[
          ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: LinearProgressIndicator(
              value: p.ratio(a).clamp(0, 1),
              minHeight: 10,
              backgroundColor: AppColors.surfaceHigh,
              valueColor: const AlwaysStoppedAnimation(AppColors.accent),
            ),
          ),
          const SizedBox(height: 6),
          Text('${p.current(a).clamp(0, a.target)} / ${a.target}',
              style: const TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 10),
        ],
        Text(
          unlocked ? tr('ach_got', {'p': a.points}) : tr('ach_reward', {'p': a.points}),
          style: const TextStyle(color: AppColors.accent, fontWeight: FontWeight.w800),
        ),
      ]),
    ),
  );
}

/// Podio de oro, plata y bronce de un mes.
class Podium extends StatelessWidget {
  final List<HallEntry> entries;
  const Podium({super.key, required this.entries});

  @override
  Widget build(BuildContext context) {
    HallEntry? at(int p) => entries.where((e) => e.position == p).firstOrNull;
    const heights = {1: 118.0, 2: 88.0, 3: 66.0};
    const colors = {
      1: [Color(0xFFFFE9A8), Color(0xFFC8902E)],
      2: [Color(0xFFF2F4F8), Color(0xFF8C94A3)],
      3: [Color(0xFFF0B27A), Color(0xFF9C5A2C)],
    };
    Widget column(int p) {
      final e = at(p);
      return Expanded(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            if (p == 1) const Icon(Icons.workspace_premium_rounded, color: AppColors.gold, size: 30),
            Text(e?.alias ?? '—',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
            Text(e == null ? '' : '${e.points} ${tr('pts')}',
                style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
            const SizedBox(height: 6),
            TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: heights[p]!),
              duration: Duration(milliseconds: 700 + p * 150),
              curve: Curves.easeOutBack,
              builder: (context, h, _) => Container(
                height: h,
                margin: const EdgeInsets.symmetric(horizontal: 4),
                decoration: BoxDecoration(
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
                  gradient: LinearGradient(
                      begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: colors[p]!),
                  boxShadow: [BoxShadow(color: colors[p]![0].withValues(alpha: 0.3), blurRadius: 18)],
                ),
                alignment: Alignment.topCenter,
                padding: const EdgeInsets.only(top: 6),
                child: Text('$p', style: AppFonts.marquee(40, color: const Color(0xFF241705))),
              ),
            ),
          ],
        ),
      );
    }

    return SizedBox(
      height: 200,
      child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [column(2), column(1), column(3)]),
    );
  }
}
