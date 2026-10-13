import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../config.dart';
import '../models.dart';
import '../strings.dart';

/// Error del servidor traducido a un mensaje para el jugador.
class ApiError implements Exception {
  final String code;
  ApiError(this.code);

  String get message {
    final known = tr('err_$code');
    return known == 'err_$code' ? tr('error_generic') : known;
  }

  @override
  String toString() => 'ApiError($code)';
}

/// Envoltorio de las funciones del servidor (RPC de Supabase).
class Api {
  SupabaseClient get _c => Supabase.instance.client;
  GoTrueClient get auth => _c.auth;

  static const _knownCodes = [
    'alias_invalid', 'alias_taken', 'alias_banned', 'invalid_location', 'invalid_birth_year',
    'weak_password', 'recovery_locked', 'invalid_recovery', 'no_jokers_left', 'joker_not_allowed',
    'joker_already_used', 'location_change_too_soon', 'too_many_reports', 'profile_exists',
    'account_not_permanent', 'no_challenge_today', 'wrong_position', 'not_served',
    'streak_restore_unavailable', 'profile_required', 'challenge_still_open', 'question_not_seen',
    'invalid_league_name', 'league_not_found', 'league_full', 'too_many_leagues', 'not_a_member',
    'not_league_owner', 'not_admin', 'question_not_found', 'challenge_already_open',
  ];

  Future<dynamic> _rpc(String fn, [Map<String, dynamic>? params]) async {
    try {
      return await _c.rpc(fn, params: params);
    } on PostgrestException catch (e) {
      final code = _knownCodes.firstWhere((c) => e.message.contains(c), orElse: () => 'generic');
      throw ApiError(code);
    }
  }

  String emailFor(String alias) => '${alias.toLowerCase()}@${Config.playerEmailDomain}';

  // --- Juego ---------------------------------------------------------------
  Future<TodayInfo> today() async => TodayInfo.fromJson(asMap(await _rpc('get_today')));

  Future<Map<String, dynamic>> nextQuestion() async => asMap(await _rpc('next_question'));

  Future<Map<String, dynamic>> submitAnswer(int position, Object? answer) async =>
      asMap(await _rpc('submit_answer', {'p_position': position, 'p_answer': answer}));

  Future<Map<String, dynamic>> useJoker(int position) async =>
      asMap(await _rpc('use_joker', {'p_position': position}));

  Future<GameSummary?> gameSummary([DateTime? date]) async {
    final r = await _rpc('get_game_summary', {'p_date': date == null ? null : _d(date)});
    return r == null ? null : GameSummary.fromJson(asMap(r));
  }

  Future<Map<String, dynamic>?> solutions([DateTime? date]) async {
    final r = await _rpc('get_solutions', {'p_date': date == null ? null : _d(date)});
    return r == null ? null : asMap(r);
  }

  Future<List<Map<String, dynamic>>> searchTitles(String query) async =>
      asMapList(await _rpc('search_titles', {'p_query': query}));

  Future<void> reportQuestion(int questionId, String reason) =>
      _rpc('report_question', {'p_question_id': questionId, 'p_reason': reason});

  Future<Leaderboard> leaderboard(String scope, String period) async => Leaderboard.fromJson(
      asMap(await _rpc('get_leaderboard', {'p_scope': scope, 'p_period': period})));

  // --- Ligas privadas -----------------------------------------------------
  Future<List<League>> myLeagues() async =>
      asMapList(await _rpc('my_leagues')).map(League.fromJson).toList();

  Future<League> createLeague(String name) async =>
      League.fromJson(asMap(await _rpc('create_league', {'p_name': name})));

  Future<League> joinLeague(String code) async =>
      League.fromJson(asMap(await _rpc('join_league', {'p_code': code})));

  Future<void> leaveLeague(int id) => _rpc('leave_league', {'p_league': id});

  Future<void> deleteLeague(int id) => _rpc('delete_league', {'p_league': id});

  Future<void> removeLeagueMember(int id, String alias) =>
      _rpc('remove_league_member', {'p_league': id, 'p_alias': alias});

  Future<Leaderboard> leagueLeaderboard(int id, String period) async => Leaderboard.fromJson(
      asMap(await _rpc('league_leaderboard', {'p_league': id, 'p_period': period})));

  // --- Perfil ------------------------------------------------------------
  Future<Profile?> myProfile() async {
    final r = await _rpc('get_my_profile');
    return r == null ? null : Profile.fromJson(asMap(r));
  }

  Future<String> aliasStatus(String alias) async =>
      (await _rpc('is_alias_available', {'p_alias': alias})) as String;

  /// Devuelve el código de recuperación (solo cuentas con contraseña).
  Future<String?> registerProfile({
    required String alias,
    required String country,
    required int cityId,
    required int birthYear,
    required String authMethod,
  }) async {
    final r = asMap(await _rpc('register_profile', {
      'p_alias': alias,
      'p_country': country,
      'p_city': cityId,
      'p_birth_year': birthYear,
      'p_auth_method': authMethod,
    }));
    return r['recovery_code'] as String?;
  }

  Future<String> regenerateRecoveryCode() async =>
      (await _rpc('regenerate_recovery_code')) as String;

  /// Devuelve el nuevo código de recuperación, o null si alias/código no son válidos.
  Future<String?> recoverAccount(String alias, String code, String newPassword) async {
    final r = asMap(await _rpc('recover_account',
        {'p_alias': alias, 'p_code': code, 'p_new_password': newPassword}));
    return r['ok'] == true ? r['recovery_code'] as String? : null;
  }

  Future<Profile> updateLocation(String country, int cityId) async =>
      Profile.fromJson(asMap(await _rpc('update_location', {'p_country': country, 'p_city': cityId})));

  Future<Profile> restoreStreak() async => Profile.fromJson(asMap(await _rpc('restore_streak')));

  Future<void> deleteMyAccount() => _rpc('delete_my_account');

  // --- Lugares -------------------------------------------------------------
  Future<List<Country>> countries() async {
    final rows = await _c.from('countries').select('code, name_es, name_en');
    return (rows as List)
        .map((r) => Country(r['code'] as String, r['name_es'] as String, r['name_en'] as String))
        .toList();
  }

  Future<List<City>> searchCities(String country, String query) async {
    final rows = await _rpc('search_cities', {'p_country': country, 'p_query': query, 'p_limit': 20});
    return (rows as List).map((r) => City(asInt(r['id']), r['name'] as String)).toList();
  }

  // --- Administración (solo cuentas de administrador) ------------------------
  Future<bool> isAdmin() async => (await _rpc('is_admin')) == true;
  Future<Map<String, dynamic>> adminDashboard() async => asMap(await _rpc('admin_dashboard'));
  Future<List<Map<String, dynamic>>> adminQuestions(
          {String? search, String? format, bool onlyManual = false, int offset = 0}) async =>
      asMapList(await _rpc('admin_list_questions', {
        'p_search': search, 'p_format': format, 'p_only_manual': onlyManual,
        'p_limit': 30, 'p_offset': offset,
      }));
  Future<int> adminSaveQuestion(int? id, Map<String, dynamic> data) async =>
      asInt(asMap(await _rpc('admin_save_question', {'p_id': id, 'p_data': data}))['id']);
  Future<void> adminSetActive(int id, bool active) =>
      _rpc('admin_set_question_active', {'p_id': id, 'p_active': active});
  Future<void> adminResolveReport(int id, String status) =>
      _rpc('admin_resolve_report', {'p_id': id, 'p_status': status});
  Future<Map<String, dynamic>?> adminChallenge(DateTime d) async {
    final r = await _rpc('admin_get_challenge', {'p_date': _d(d)});
    return r == null ? null : asMap(r);
  }
  Future<void> adminReplace(DateTime d, int position, int questionId) => _rpc(
      'admin_replace_challenge_question', {'p_date': _d(d), 'p_position': position, 'p_question_id': questionId});

  /// Sube una imagen propia al almacenamiento público y devuelve su dirección.
  Future<String> adminUploadImage(List<int> bytes, String ext) async {
    final path = 'manual/${DateTime.now().millisecondsSinceEpoch}.$ext';
    await _c.storage.from('media').uploadBinary(path, Uint8List.fromList(bytes),
        fileOptions: FileOptions(contentType: ext == 'png' ? 'image/png' : 'image/jpeg', upsert: true));
    return _c.storage.from('media').getPublicUrl(path);
  }

  String _d(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}
