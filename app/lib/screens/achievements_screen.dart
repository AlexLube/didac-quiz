import 'package:flutter/material.dart';

import '../app_state.dart';
import '../models.dart';
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
      final supabase = AppState.instance.supabase;
      final profile = AppState.instance.profile;
      
      // 1. Cargar todos los logros del catálogo
      final allAch = await supabase.from('achievements').select().order('points', ascending: true);
      
      // 2. Cargar los logros desbloqueados por el usuario actual
      Set<String> unlocked = {};
      if (profile != null) {
        final userAch = await supabase
            .from('user_achievements')
            .select('achievement_id')
            .eq('profile_id', profile.id);
        unlocked = {for (final r in userAch) r['achievement_id'].toString()};
      }

      if (mounted) {
        setState(() {
          _achievements = List<Map<String, dynamic>>.from(allAch);
          _unlockedIds = unlocked;
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
        return Icons.emoji_events_rounded;
      case 'milestone':
        return Icons.workspace_premium_rounded;
      default:
        return Icons.stars_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    final unlockedCount = _unlockedIds.length;
    final totalCount = _achievements.length;

    return Scaffold(
      appBar: AppBar(
        title: Text(tr('achievements_title', {'count': '$unlockedCount/$totalCount'})),
      ),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? ErrorView(message: tr('error_generic'), onRetry: _load)
                : RefreshIndicator(
                    onRefresh: _load,
                    child: ListView(
                      padding: const EdgeInsets.all(20),
                      children: [
                        // Cabecera de progreso
                        Container(
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            gradient: AppColors.heroGradient,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: AppColors.accent.withValues(alpha: 0.3), width: 1.2),
                          ),
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: AppColors.accent.withValues(alpha: 0.15),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(Icons.military_tech_rounded, color: AppColors.accent, size: 32),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Column(
                               crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      'Trofeos de Cine',
                                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: AppColors.text),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      'Has conseguido $unlockedCount de $totalCount logros disponibles.',
                                      style: const TextStyle(fontSize: 13, color: AppColors.textMuted),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 20),
                        // Lista de logros
                        ..._achievements.map((ach) {
                          final id = ach['id'].toString();
                          final unlocked = _unlockedIds.contains(id);
                          final title = ach['title_es'] ?? id;
                          final desc = ach['description_es'] ?? '';
                          final points = ach['points'] ?? 5;
                          final category = ach['category'] ?? 'general';
                          final icon = _iconForCategory(category);

                          return Container(
                            margin: const EdgeInsets.only(bottom: 12),
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: unlocked ? AppColors.surface : AppColors.backgroundTop,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: unlocked ? AppColors.accent.withValues(alpha: 0.4) : AppColors.border,
                                width: unlocked ? 1.5 : 1,
                              ),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  width: 50,
                                  height: 50,
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
                                    size: 24,
                                    color: unlocked ? AppColors.accent : AppColors.textMuted,
                                  ),
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Expanded(
                                            child: Text(
                                              title,
                                              style: TextStyle(
                                                fontSize: 16,
                                                fontWeight: FontWeight.w800,
                                                color: unlocked ? AppColors.text : AppColors.textMuted,
                                              ),
                                            ),
                                          ),
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                            decoration: BoxDecoration(
                                              color: unlocked ? AppColors.gold.withValues(alpha: 0.15) : AppColors.surfaceHigh,
                                              borderRadius: BorderRadius.circular(8),
                                            ),
                                            child: Text(
                                              '+$points pts',
                                              style: TextStyle(
                                                fontSize: 12,
                                                fontWeight: FontWeight.w800,
                                                color: unlocked ? AppColors.gold : AppColors.textMuted,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        desc,
                                        style: const TextStyle(fontSize: 13, color: AppColors.textMuted, height: 1.3),
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
                  ),
      ),
    );
  }
}
