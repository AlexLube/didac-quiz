/// Modelos simples a partir del JSON que devuelven las funciones del servidor.
library;

Map<String, dynamic> asMap(dynamic v) =>
    v == null ? <String, dynamic>{} : Map<String, dynamic>.from(v as Map);

List<Map<String, dynamic>> asMapList(dynamic v) =>
    v == null ? [] : (v as List).map((e) => asMap(e)).toList();

int asInt(dynamic v, [int fallback = 0]) =>
    v is int ? v : (v is num ? v.toInt() : int.tryParse('$v') ?? fallback);

class Profile {
  final String alias;
  final String countryCode;
  final dynamic countryName;
  final int cityId;
  final String cityName;
  final int birthYear;
  final bool isMinor;
  final String authMethod;
  final int streakCurrent;
  final int streakBest;
  final bool canRestoreStreak;
  final int? streakLost;
  final DateTime locationChangeAvailableOn;

  Profile.fromJson(Map<String, dynamic> j)
      : alias = j['alias'] as String,
        countryCode = j['country_code'] as String,
        countryName = j['country_name'],
        cityId = asInt(j['city_id']),
        cityName = (j['city_name'] ?? '') as String,
        birthYear = asInt(j['birth_year']),
        isMinor = j['is_minor'] == true,
        authMethod = (j['auth_method'] ?? 'password') as String,
        streakCurrent = asInt(j['streak_current']),
        streakBest = asInt(j['streak_best']),
        canRestoreStreak = j['can_restore_streak'] == true,
        streakLost = j['streak_lost'] == null ? null : asInt(j['streak_lost']),
        locationChangeAvailableOn =
            DateTime.tryParse('${j['location_change_available_on']}') ?? DateTime.now();

  bool get canChangeLocation => !DateTime.now().isBefore(locationChangeAvailableOn);
}

class AnswerSummary {
  final int position;
  final int difficulty;
  final bool? correct;
  final int points;
  final int elapsedMs;
  final bool jokerUsed;

  AnswerSummary.fromJson(Map<String, dynamic> j)
      : position = asInt(j['position']),
        difficulty = asInt(j['difficulty'], 1),
        correct = j['correct'] as bool?,
        points = asInt(j['points']),
        elapsedMs = asInt(j['elapsed_ms']),
        jokerUsed = j['joker_used'] == true;
}

class GameSummary {
  final DateTime date;
  final bool finished;
  final int position;
  final int totalPoints;
  final int maxPoints;
  final int totalMs;
  final List<AnswerSummary> answers;

  GameSummary.fromJson(Map<String, dynamic> j)
      : date = DateTime.parse('${j['date']}'),
        finished = j['finished'] == true,
        position = asInt(j['position']),
        totalPoints = asInt(j['total_points']),
        maxPoints = asInt(j['max_points'], 18),
        totalMs = asInt(j['total_ms']),
        answers = asMapList(j['answers']).map(AnswerSummary.fromJson).toList();
}

class TodayInfo {
  final DateTime date;
  final bool available;
  final String kind;
  final dynamic title;
  final String status; // not_started | in_progress | finished
  final GameSummary? game;
  final int jokersLeft;
  final Profile? profile;

  TodayInfo.fromJson(Map<String, dynamic> j)
      : date = DateTime.parse('${j['date']}'),
        available = j['available'] == true,
        kind = (j['kind'] ?? 'general') as String,
        title = j['title'],
        status = (j['status'] ?? 'not_started') as String,
        game = j['game'] == null ? null : GameSummary.fromJson(asMap(j['game'])),
        jokersLeft = asInt(j['jokers_left']),
        profile = j['profile'] == null ? null : Profile.fromJson(asMap(j['profile']));
}

class Question {
  final int position;
  final int id;
  final String format;
  final int difficulty;
  final dynamic prompt;
  final List<dynamic> options;
  final String? imageUrl;
  final String? imageAttribution;
  final int timeLimitMs;
  final int remainingMs;
  final List<int> removedOptions;

  Question.fromJson(Map<String, dynamic> j)
      : position = asInt(j['position']),
        id = asInt(j['id']),
        format = j['format'] as String,
        difficulty = asInt(j['difficulty'], 1),
        prompt = j['prompt'],
        options = List<dynamic>.from(j['options'] as List),
        imageUrl = j['image_url'] as String?,
        imageAttribution = j['image_attribution'] as String?,
        timeLimitMs = asInt(j['time_limit_ms'], 20000),
        remainingMs = asInt(j['remaining_ms'], 20000),
        removedOptions = ((j['removed_options'] ?? []) as List).map((e) => asInt(e)).toList();

  bool get isOrder => format == 'order';
  bool get jokerAllowed =>
      options.length == 4 &&
      const ['choice', 'intruder', 'decade', 'clues', 'image_choice', 'image_reveal']
          .contains(format);
}

class LeaderboardRow {
  final int rank;
  final String alias;
  final String countryCode;
  final String? city;
  final int points;
  final int ms;
  final int games;
  final bool isMe;

  LeaderboardRow.fromJson(Map<String, dynamic> j)
      : rank = asInt(j['rank']),
        alias = j['alias'] as String,
        countryCode = (j['country_code'] ?? '') as String,
        city = j['city'] as String?,
        points = asInt(j['points']),
        ms = asInt(j['ms']),
        games = asInt(j['games']),
        isMe = j['is_me'] == true;
}

class Leaderboard {
  final Map<String, dynamic> label;
  final int totalPlayers;
  final List<LeaderboardRow> top;
  final LeaderboardRow? me;
  final List<LeaderboardRow> around;

  Leaderboard.fromJson(Map<String, dynamic> j)
      : label = asMap(j['label']),
        totalPlayers = asInt(j['total_players']),
        top = asMapList(j['top']).map(LeaderboardRow.fromJson).toList(),
        me = j['me'] == null ? null : LeaderboardRow.fromJson(asMap(j['me'])),
        around = asMapList(j['around']).map(LeaderboardRow.fromJson).toList();
}

class Country {
  final String code;
  final String nameEs;
  final String nameEn;
  Country(this.code, this.nameEs, this.nameEn);
}

class City {
  final int id;
  final String name;
  City(this.id, this.name);
}
