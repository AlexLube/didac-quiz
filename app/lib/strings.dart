/// Textos de la interfaz en español e inglés.
class Strings {
  static String lang = 'es';

  static const Map<String, Map<String, String>> _t = {
    'app_name': {'es': 'Didac-Quiz', 'en': 'Didac-Quiz'},
    'tagline': {'es': 'El reto diario de cine', 'en': 'The daily movie challenge'},
    'tab_today': {'es': 'Hoy', 'en': 'Today'},
    'tab_rankings': {'es': 'Rankings', 'en': 'Rankings'},
    'tab_profile': {'es': 'Perfil', 'en': 'Profile'},
    'loading': {'es': 'Cargando…', 'en': 'Loading…'},
    'retry': {'es': 'Reintentar', 'en': 'Retry'},
    'error_generic': {'es': 'Algo ha fallado. Revisa tu conexión.', 'en': 'Something went wrong. Check your connection.'},
    'not_configured': {
      'es': 'Esta compilación no tiene configurado el servidor (SUPABASE_URL y SUPABASE_ANON_KEY).',
      'en': 'This build has no server configured (SUPABASE_URL and SUPABASE_ANON_KEY).'
    },
    // Hoy
    'today_challenge': {'es': 'Reto de hoy', 'en': "Today's challenge"},
    'no_challenge': {'es': 'Hoy no hay reto disponible. ¡Vuelve mañana!', 'en': 'No challenge today. Come back tomorrow!'},
    'play': {'es': 'Jugar', 'en': 'Play'},
    'continue': {'es': 'Continuar', 'en': 'Continue'},
    'see_result': {'es': 'Ver mi resultado', 'en': 'See my result'},
    'questions_points': {'es': '10 preguntas · hasta {max} puntos', 'en': '10 questions · up to {max} points'},
    'rules_short': {
      'es': 'Fáciles 1 punto, medias 2, difíciles 3. 20 segundos por pregunta. Una partida al día.',
      'en': 'Easy 1 point, medium 2, hard 3. 20 seconds per question. One game a day.'
    },
    'streak': {'es': 'Racha', 'en': 'Streak'},
    'days': {'es': 'días', 'en': 'days'},
    'jokers_left': {'es': 'Comodines 50/50 esta semana', 'en': '50/50 jokers this week'},
    'yesterday_solutions': {'es': 'Soluciones de ayer', 'en': "Yesterday's answers"},
    'new_challenge_in': {'es': 'Nuevo reto en {t}', 'en': 'New challenge in {t}'},
    'guest_banner': {
      'es': 'Estás jugando como invitado. Crea una cuenta para entrar en los rankings.',
      'en': "You're playing as a guest. Create an account to join the rankings."
    },
    // Juego
    'question_n': {'es': 'Pregunta {n} de 10', 'en': 'Question {n} of 10'},
    'easy': {'es': 'Fácil', 'en': 'Easy'},
    'medium': {'es': 'Media', 'en': 'Medium'},
    'hard': {'es': 'Difícil', 'en': 'Hard'},
    'pts': {'es': 'pts', 'en': 'pts'},
    'pt': {'es': 'pt', 'en': 'pt'},
    'joker': {'es': '50/50', 'en': '50/50'},
    'confirm_order': {'es': 'Confirmar orden', 'en': 'Confirm order'},
    'drag_to_order': {'es': 'Arrastra para ordenar (arriba, la más antigua)', 'en': 'Drag to reorder (oldest on top)'},
    'correct': {'es': '¡Correcto!', 'en': 'Correct!'},
    'wrong': {'es': 'Fallo', 'en': 'Wrong'},
    'timeout': {'es': '¡Se acabó el tiempo!', 'en': "Time's up!"},
    'leave_game_title': {'es': '¿Salir del reto?', 'en': 'Leave the challenge?'},
    'leave_game_body': {
      'es': 'El tiempo sigue corriendo en el servidor. Si no vuelves a tiempo, la pregunta contará como fallo.',
      'en': 'The clock keeps running on the server. If you do not come back in time, the question counts as wrong.'
    },
    'leave': {'es': 'Salir', 'en': 'Leave'},
    'stay': {'es': 'Seguir jugando', 'en': 'Keep playing'},
    'report': {'es': 'Reportar pregunta', 'en': 'Report question'},
    'report_hint': {'es': '¿Qué le pasa a esta pregunta?', 'en': "What's wrong with this question?"},
    'report_sent': {'es': 'Gracias, lo revisaremos.', 'en': "Thanks, we'll review it."},
    'send': {'es': 'Enviar', 'en': 'Send'},
    'cancel': {'es': 'Cancelar', 'en': 'Cancel'},
    // Resultado
    'your_result': {'es': 'Tu resultado', 'en': 'Your result'},
    'points_of': {'es': '{p} de {max} puntos', 'en': '{p} of {max} points'},
    'total_time': {'es': 'Tiempo total', 'en': 'Total time'},
    'share': {'es': 'Compartir', 'en': 'Share'},
    'see_rankings': {'es': 'Ver rankings', 'en': 'See rankings'},
    'solutions_tomorrow': {
      'es': 'Las soluciones se publican mañana, cuando el reto se cierre para todo el mundo.',
      'en': 'Answers are published tomorrow, once the challenge closes worldwide.'
    },
    'streak_lost': {'es': 'Has perdido una racha de {n} días.', 'en': 'You lost a {n}-day streak.'},
    'restore_streak': {'es': 'Recuperarla viendo un anuncio', 'en': 'Restore it by watching an ad'},
    'streak_restored': {'es': '¡Racha recuperada!', 'en': 'Streak restored!'},
    'ad_not_available': {'es': 'No hay anuncio disponible ahora. Inténtalo más tarde.', 'en': 'No ad available right now. Try again later.'},
    'create_account_to_rank': {'es': 'Crea tu cuenta para guardar esta puntuación', 'en': 'Create your account to keep this score'},
    // Rankings
    'world': {'es': 'Mundial', 'en': 'World'},
    'country': {'es': 'País', 'en': 'Country'},
    'local': {'es': 'Local', 'en': 'Local'},
    'day': {'es': 'Hoy', 'en': 'Today'},
    'week': {'es': 'Semana', 'en': 'Week'},
    'month': {'es': 'Mes', 'en': 'Month'},
    'all_time': {'es': 'Histórico', 'en': 'All time'},
    'players': {'es': 'jugadores', 'en': 'players'},
    'you': {'es': 'Tú', 'en': 'You'},
    'area_of': {'es': 'Área de {name}', 'en': '{name} area'},
    'no_players_yet': {'es': 'Todavía no hay nadie aquí. ¡Sé el primero!', 'en': 'Nobody here yet. Be the first!'},
    'rankings_need_account': {'es': 'Crea una cuenta para ver tu país y tu ciudad.', 'en': 'Create an account to see your country and city.'},
    // Ligas privadas
    'leagues': {'es': 'Ligas', 'en': 'Leagues'},
    'my_leagues': {'es': 'Mis ligas', 'en': 'My leagues'},
    'leagues_intro': {
      'es': 'Crea una liga y compite con tus amigos con las mismas partidas del reto diario.',
      'en': 'Create a league and compete with your friends using the same daily games.'
    },
    'create_league': {'es': 'Crear liga', 'en': 'Create league'},
    'join_league': {'es': 'Unirme con código', 'en': 'Join with code'},
    'league_name': {'es': 'Nombre de la liga', 'en': 'League name'},
    'invite_code': {'es': 'Código de invitación', 'en': 'Invite code'},
    'invite_friends': {'es': 'Invitar amigos', 'en': 'Invite friends'},
    'invite_text': {
      'es': '¡Únete a mi liga «{name}» en Didac-Quiz! Código: {code}',
      'en': 'Join my league “{name}” on Didac-Quiz! Code: {code}'
    },
    'members_n': {'es': '{n} miembros', 'en': '{n} members'},
    'owner': {'es': 'Creador', 'en': 'Owner'},
    'leave_league': {'es': 'Salir de la liga', 'en': 'Leave league'},
    'delete_league': {'es': 'Borrar la liga', 'en': 'Delete league'},
    'delete_league_confirm': {'es': 'Se borrará la liga para todos sus miembros.', 'en': 'The league will be deleted for all members.'},
    'remove_member': {'es': 'Expulsar a {alias}', 'en': 'Remove {alias}'},
    'no_leagues': {'es': 'Todavía no estás en ninguna liga.', 'en': "You're not in any league yet."},
    'leagues_need_account': {'es': 'Crea una cuenta para jugar ligas con tus amigos.', 'en': 'Create an account to play leagues with your friends.'},
    'joined_league': {'es': 'Te has unido a «{name}»', 'en': 'You joined “{name}”'},
    'err_invalid_league_name': {'es': 'El nombre debe tener entre 3 y 40 caracteres y no puede ser ofensivo.', 'en': 'The name must be 3-40 characters and not offensive.'},
    'err_league_not_found': {'es': 'No existe ninguna liga con ese código.', 'en': 'No league with that code.'},
    'err_league_full': {'es': 'Esa liga está llena (máximo 100).', 'en': 'That league is full (max 100).'},
    'err_too_many_leagues': {'es': 'Puedes estar como máximo en 20 ligas.', 'en': 'You can be in at most 20 leagues.'},
    // Perfil y cuentas
    'create_account': {'es': 'Crear cuenta', 'en': 'Create account'},
    'login': {'es': 'Iniciar sesión', 'en': 'Log in'},
    'logout': {'es': 'Cerrar sesión', 'en': 'Log out'},
    'alias': {'es': 'Alias', 'en': 'Username'},
    'alias_help': {'es': '3-20 caracteres: letras, números, _ . -', 'en': '3-20 characters: letters, numbers, _ . -'},
    'password': {'es': 'Contraseña', 'en': 'Password'},
    'password_help': {'es': 'Mínimo 8 caracteres', 'en': 'At least 8 characters'},
    'birth_year': {'es': 'Año de nacimiento', 'en': 'Year of birth'},
    'city': {'es': 'Ciudad', 'en': 'City'},
    'search_city': {'es': 'Busca tu ciudad', 'en': 'Search your city'},
    'choose_country': {'es': 'Elige tu país', 'en': 'Choose your country'},
    'continue_google': {'es': 'Continuar con Google', 'en': 'Continue with Google'},
    'continue_apple': {'es': 'Continuar con Apple', 'en': 'Continue with Apple'},
    'or': {'es': 'o', 'en': 'or'},
    'no_email_note': {
      'es': 'Sin email ni teléfono. Solo un alias y una contraseña.',
      'en': 'No email or phone. Just a username and a password.'
    },
    'forgot_password': {'es': '¿Has olvidado la contraseña?', 'en': 'Forgot your password?'},
    'recover_account': {'es': 'Recuperar cuenta', 'en': 'Recover account'},
    'recovery_code': {'es': 'Código de recuperación', 'en': 'Recovery code'},
    'new_password': {'es': 'Nueva contraseña', 'en': 'New password'},
    'recovery_code_title': {'es': 'Guarda tu código de recuperación', 'en': 'Save your recovery code'},
    'recovery_code_body': {
      'es': 'Es la única forma de recuperar tu cuenta si olvidas la contraseña. Solo se muestra ahora: cópialo o haz una captura.',
      'en': 'It is the only way to recover your account if you forget your password. It is shown only now: copy it or take a screenshot.'
    },
    'copy': {'es': 'Copiar', 'en': 'Copy'},
    'copied': {'es': 'Copiado', 'en': 'Copied'},
    'saved_it': {'es': 'Ya lo he guardado', 'en': "I've saved it"},
    'new_recovery_code': {'es': 'Generar nuevo código de recuperación', 'en': 'Generate a new recovery code'},
    'complete_profile': {'es': 'Completa tu perfil', 'en': 'Complete your profile'},
    'best_streak': {'es': 'Mejor racha', 'en': 'Best streak'},
    'change_location': {'es': 'Cambiar país o ciudad', 'en': 'Change country or city'},
    'location_available_on': {'es': 'Podrás cambiarla a partir del {d}', 'en': 'You can change it from {d}'},
    'language': {'es': 'Idioma', 'en': 'Language'},
    'privacy': {'es': 'Política de privacidad', 'en': 'Privacy policy'},
    'legal_notice': {
      'es': 'Didac-Quiz no está afiliado ni patrocinado por ninguna academia, estudio o festival de cine. Datos de películas: Wikidata (CC0). Lugares: GeoNames (CC BY 4.0).',
      'en': 'Didac-Quiz is not affiliated with or sponsored by any film academy, studio or festival. Film data: Wikidata (CC0). Places: GeoNames (CC BY 4.0).'
    },
    'delete_account': {'es': 'Borrar mi cuenta', 'en': 'Delete my account'},
    'delete_account_confirm': {
      'es': 'Se borrarán tu perfil, tus partidas y tu posición en los rankings. No se puede deshacer.',
      'en': 'Your profile, games and ranking positions will be deleted. This cannot be undone.'
    },
    'delete': {'es': 'Borrar', 'en': 'Delete'},
    'save': {'es': 'Guardar', 'en': 'Save'},
    'guest': {'es': 'Invitado', 'en': 'Guest'},
    // Errores del servidor
    'err_alias_invalid': {'es': 'El alias no es válido.', 'en': 'Invalid username.'},
    'err_alias_taken': {'es': 'Ese alias ya existe.', 'en': 'That username is taken.'},
    'err_alias_banned': {'es': 'Ese alias no está permitido.', 'en': 'That username is not allowed.'},
    'err_invalid_location': {'es': 'Elige un país y una ciudad de la lista.', 'en': 'Pick a country and a city from the list.'},
    'err_invalid_birth_year': {'es': 'Año de nacimiento no válido.', 'en': 'Invalid year of birth.'},
    'err_weak_password': {'es': 'La contraseña debe tener al menos 8 caracteres.', 'en': 'The password must have at least 8 characters.'},
    'err_login': {'es': 'Alias o contraseña incorrectos.', 'en': 'Wrong username or password.'},
    'err_recovery': {'es': 'El alias o el código no son correctos.', 'en': 'Wrong username or code.'},
    'err_recovery_locked': {'es': 'Demasiados intentos. Espera 15 minutos.', 'en': 'Too many attempts. Wait 15 minutes.'},
    'err_no_jokers_left': {'es': 'No te quedan comodines esta semana.', 'en': 'No jokers left this week.'},
    'err_joker_not_allowed': {'es': 'Esta pregunta no admite comodín.', 'en': 'No joker for this question.'},
    'err_location_change_too_soon': {'es': 'Solo puedes cambiar de ciudad una vez cada 30 días.', 'en': 'You can only change city once every 30 days.'},
    'err_too_many_reports': {'es': 'Has enviado muchos reportes hoy.', 'en': 'You have sent many reports today.'},
  };

  static String t(String key, [Map<String, Object>? params]) {
    var s = _t[key]?[lang] ?? _t[key]?['es'] ?? key;
    params?.forEach((k, v) => s = s.replaceAll('{$k}', '$v'));
    return s;
  }

  /// Elige el idioma de un texto que viene del servidor como {"es": ..., "en": ...}.
  static String pick(dynamic value) {
    if (value == null) return '';
    if (value is String) return value;
    if (value is Map) {
      return (value[lang] ?? value['es'] ?? value.values.first ?? '').toString();
    }
    return value.toString();
  }
}

String tr(String key, [Map<String, Object>? params]) => Strings.t(key, params);
