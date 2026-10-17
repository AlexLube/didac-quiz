import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../strings.dart';
import '../theme.dart';
import '../widgets/common.dart';

class AchievementsScreen extends StatefulWidget {
  const AchievementsScreen({super.key});

  @override
  State<AchievementsScreen> createState() => _AchievementsScreenState();
}

class _AchievementsScreenState extends State<AchievementsScreen> {
  bool _loading = true;
  List<Map<String, dynamic>> _achievements = [];
  List<Map<String, dynamic>> _hallOfFame = [];
  Set<String> _unlockedIds = {};
  Object? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final client = Supabase.instance.client;
      final uid = client.auth.currentUser?.id;

      final allAch = await client
          .from('achievements')
          .select()
          .order('points', ascending: true);

      Set<String> unlocked = {};
      if (uid != null) {
        final userAch = await client
            .from('user_achievements')
            .select('achievement_id')
            .eq('user_id', uid);
        unlocked = {for (final r in userAch as List) r['achievement_id'].toString()};
      }

      List<Map<String, dynamic>> hall = [];
      try {
        final hof = await client
            .from('hall_of_fame')
            .select()
            .order('year_month', ascending: false)
            .order('position', ascending: true)
            .limit(30);
        hall = List<Map<String, dynamic>>.from(hof as List);
      } catch (_) {}

      if (mounted) {
        setState(() {
          _achievements = List<Map<String, dynamic>>.from(allAch as List);
          _unlockedIds = unlocked;
          _hallOfFame = hall;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e;
          _loading = false;
        });
      }
    }
  }

  IconData _iconForCategory(String category) {
    switch (category) {
      case 'streak':
        return Icons.local_fire_department_rounded;
      case 'score':
        return Icons.bolt_rounded;
      case 'media':
        return Icons.theaters_rounded;
      case 'social':
        return Icons.groups_rounded;
      case 'special':
        return Icons.cake_rounded;
      case 'milestone':
        return Icons.workspace_premium_rounded;
      default:
        return Icons.military_tech_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEs = Strings.lang == 'es';
    final unlockedCount = _unlockedIds.length;
    final totalCount = _achievements.length;
    final earnedPoints = _achievements
        .where((a) => _unlockedIds.contains(a['id'].toString()))
        .fold<int>(0, (sum, a) => sum + ((a['points'] as num?)?.toInt() ?? 0));

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: Text(isEs ? 'Logros y Salón de la Fama' : 'Achievements & Hall of Fame'),
          bottom: TabBar(
            indicatorColor: AppColors.accent,
            labelColor: AppColors.accent,
            unselectedLabelColor: AppColors.textMuted,
            tabs: [
              Tab(
                icon: const Icon(Icons.military_tech_rounded, size: 20),
                text: isEs
                    ? 'Logros ($unlockedCount/$totalCount)'
                    : 'Trophies ($unlockedCount/$totalCount)',
              ),
              Tab(
                icon: const Icon(Icons.emoji_events_rounded, size: 20),
                text: 'Hall of Fame',
              ),
            ],
          ),
        ),
        body: SafeArea(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _error != null
                  ? ErrorView(message: tr('error_generic'), onRetry: _load)
                  : TabBarView(
                      children: [
                        _buildAchievementsList(isEs, unlockedCount, totalCount, earnedPoints),
                        _buildHallOfFameList(isEs),
                      ],
                    ),
        ),
      ),
    );
  }

  Widget _buildAchievementsList(
      bool isEs, int unlockedCount, int totalCount, int earnedPoints) {
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: AppColors.heroGradient,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                  color: AppColors.accent.withValues(alpha: 0.35), width: 1.2),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.accent.withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.military_tech_rounded,
                      color: AppColors.accent, size: 32),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        isEs ? '+$earnedPoints pts en Trofeos' : '+$earnedPoints Trophy pts',
                        style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                            color: AppColors.text),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        isEs
                            ? 'Has desbloqueado $unlockedCount de $totalCount logros.'
                            : 'You unlocked $unlockedCount of $totalCount achievements.',
                        style: const TextStyle(fontSize: 13, color: AppColors.textMuted),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          ..._achievements.map((ach) {
            final id = ach['id'].toString();
            final unlocked = _unlockedIds.contains(id);
            final title = (isEs ? ach['title_es'] : ach['title_en']) ?? id;
            final desc = (isEs ? ach['description_es'] : ach['description_en']) ?? '';
            final points = ach['points'] ?? 5;
            final category = (ach['category'] ?? 'general').toString();
            final icon = _iconForCategory(category);

            return Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: unlocked ? AppColors.surface : AppColors.backgroundTop,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: unlocked
                      ? AppColors.accent.withValues(alpha: 0.45)
                      : AppColors.border,
                  width: unlocked ? 1.5 : 1,
                ),
              ),
              child: Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: unlocked
                          ? AppColors.accent.withValues(alpha: 0.18)
                          : AppColors.surfaceHigh,
                      border: Border.all(
                        color: unlocked ? AppColors.gold : AppColors.border,
                        width: 1.5,
                      ),
                    ),
                    child: Icon(
                      unlocked ? icon : Icons.lock_outline_rounded,
                      size: 22,
                      color: unlocked ? AppColors.accent : AppColors.textMuted,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                title.toString(),
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w800,
                                  color: unlocked ? AppColors.text : AppColors.textMuted,
                                ),
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: unlocked
                                    ? AppColors.gold.withValues(alpha: 0.16)
                                    : AppColors.surfaceHigh,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                '+$points pts',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w800,
                                  color:
                                      unlocked ? AppColors.gold : AppColors.textMuted,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 3),
                        Text(
                          desc.toString(),
                          style: const TextStyle(
                              fontSize: 12, color: AppColors.textMuted, height: 1.3),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildHallOfFameList(bool isEs) {
    if (_hallOfFame.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.emoji_events_outlined,
                  size: 56, color: AppColors.accent),
              const SizedBox(height: 14),
              Text(
                isEs ? 'Salón de la Fama Mensual' : 'Monthly Hall of Fame',
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              Text(
                isEs
                    ? 'El día 1 de cada mes se corona aquí al Top 3 del mes anterior y comienza una nueva temporada.'
                    : 'On the 1st of every month, the previous month Top 3 are crowned here and a new season begins.',
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.textMuted, height: 1.4),
              ),
            ],
          ),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(20),
      itemCount: _hallOfFame.length,
      itemBuilder: (context, i) {
        final row = _hallOfFame[i];
        final pos = (row['position'] as num?)?.toInt() ?? 1;
        final medalColor = pos == 1
            ? AppColors.gold
            : (pos == 2 ? const Color(0xFFCBD5E1) : const Color(0xFFD97706));
        return Card(
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: medalColor.withValues(alpha: 0.2),
              child: Text('$posº',
                  style: TextStyle(color: medalColor, fontWeight: FontWeight.w900)),
            ),
            title: Text(
              (row['alias'] ?? 'Jugador').toString(),
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
            subtitle: Text('${row['year_month']}'),
            trailing: Text(
              '${row['total_points']} pts',
              style: const TextStyle(
                  color: AppColors.accent, fontWeight: FontWeight.w800),
            ),
          ),
        );
      },
    );
  }
}
