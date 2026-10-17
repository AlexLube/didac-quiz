import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models.dart';
import '../strings.dart';

/// Un logro del catálogo (100 en total, en 5 familias).
class Achievement {
  final String id;
  final dynamic title;
  final dynamic description;
  final int points;
  final String category;
  final int target;

  Achievement.fromJson(Map<String, dynamic> j)
      : id = '${j['id']}',
        title = {'es': j['title_es'], 'en': j['title_en']},
        description = {'es': j['description_es'], 'en': j['description_en']},
        points = asInt(j['points'], 5),
        category = (j['category'] ?? 'general') as String,
        target = asInt(j['target_value'], 1);

  /// Familia del logro (rachas, partidas, críticas, taquilla, velocidad).
  String get family => id.split('_').first;

  IconData get icon => switch (family) {
        'streak' => Icons.local_fire_department_rounded,
        'games' => Icons.event_seat_rounded,
        'master' => Icons.star_rounded,
        'points' => Icons.confirmation_number_rounded,
        'clean' => Icons.bolt_rounded,
        _ => Icons.emoji_events_rounded,
      };
}

class HallEntry {
  final String yearMonth;
  final int position;
  final String alias;
  final int points;
  HallEntry.fromJson(Map<String, dynamic> j)
      : yearMonth = '${j['year_month']}',
        position = asInt(j['position']),
        alias = '${j['alias']}',
        points = asInt(j['total_points']);
}

/// Progreso del jugador: valores de cada familia y logros conseguidos.
class AchievementProgress {
  final Map<String, int> values;
  final List<String> unlocked;
  final int bonusPoints;
  const AchievementProgress(this.values, this.unlocked, this.bonusPoints);

  static const empty = AchievementProgress({}, [], 0);

  AchievementProgress.fromJson(Map<String, dynamic> j)
      : values = {
          'streak': asInt(j['streak_best']),
          'games': asInt(j['games']),
          'master': asInt(j['master']),
          'points': asInt(j['points']),
          'clean': asInt(j['fast']),
        },
        unlocked = ((j['unlocked'] ?? []) as List).map((e) => '$e').toList(),
        bonusPoints = asInt(j['bonus_points']);

  double ratio(Achievement a) => a.target == 0 ? 0 : (values[a.family] ?? 0) / a.target;
  int current(Achievement a) => values[a.family] ?? 0;
}

const achievementFamilies = ['streak', 'games', 'master', 'points', 'clean'];

String familyLabel(String f) => tr('ach_family_$f');

/// Catálogo de logros, progreso del jugador y avisos de logros nuevos.
class Achievements extends ChangeNotifier {
  Achievements._();
  static final Achievements instance = Achievements._();

  SupabaseClient get _c => Supabase.instance.client;
  List<Achievement> catalog = [];
  AchievementProgress progress = AchievementProgress.empty;
  List<HallEntry> hall = [];
  bool loaded = false;

  Set<String> get unlocked => progress.unlocked.toSet();

  Future<void> load() async {
    try {
      if (catalog.isEmpty) {
        final rows = await _c.from('achievements').select().order('category').order('target_value');
        catalog = asMapList(rows).map(Achievement.fromJson).toList()
          ..sort((a, b) {
            final f = achievementFamilies.indexOf(a.family).compareTo(achievementFamilies.indexOf(b.family));
            return f != 0 ? f : a.target.compareTo(b.target);
          });
      }
      final p = await _c.rpc('my_achievement_progress');
      progress = p == null ? AchievementProgress.empty : AchievementProgress.fromJson(asMap(p));
      final h = await _c.from('hall_of_fame').select().order('year_month', ascending: false).order('position');
      hall = asMapList(h).map(HallEntry.fromJson).toList();
      loaded = true;
    } catch (e) {
      debugPrint('[didacquiz] logros no disponibles: $e');
    }
    notifyListeners();
  }

  /// Logros que el jugador ha conseguido desde la última vez que se le avisó.
  Future<List<Achievement>> takeNew() async {
    await load();
    final uid = _c.auth.currentUser?.id;
    if (uid == null || !loaded) return [];
    final prefs = await SharedPreferences.getInstance();
    final key = 'ach_seen_$uid';
    final seen = prefs.getStringList(key);
    final now = progress.unlocked;
    await prefs.setStringList(key, now);
    if (seen == null) return []; // primera vez en este dispositivo: no se avisa de lo antiguo
    final fresh = now.where((a) => !seen.contains(a)).toSet();
    return catalog.where((a) => fresh.contains(a.id)).toList();
  }
}
