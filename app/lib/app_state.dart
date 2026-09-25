import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'config.dart';
import 'models.dart';
import 'services/ads.dart';
import 'services/api.dart';
import 'strings.dart';

/// Estado global sencillo: sesión, perfil e idioma.
class AppState extends ChangeNotifier {
  AppState._();
  static final AppState instance = AppState._();

  final api = Api();
  Profile? profile;
  bool ready = false;
  StreamSubscription<AuthState>? _authSub;

  User? get user => Supabase.instance.client.auth.currentUser;
  bool get isGuest => user == null || user!.isAnonymous || profile == null;
  bool get needsOnboarding => user != null && !user!.isAnonymous && profile == null;

  Future<void> init() async {
    _log('inicio');
    final prefs = await SharedPreferences.getInstance();
    final platformLang = PlatformDispatcher.instance.locale.languageCode;
    Strings.lang = prefs.getString('lang') ?? (platformLang == 'es' ? 'es' : 'en');

    await Supabase.initialize(url: Config.supabaseUrl, publishableKey: Config.supabaseAnonKey);
    _log('supabase listo');
    _authSub = Supabase.instance.client.auth.onAuthStateChange.listen((event) {
      if (event.event == AuthChangeEvent.signedIn) {
        refreshProfile();
      }
    });
    await ensureSession().timeout(const Duration(seconds: 20));
    _log('sesión lista (invitado: ${user?.isAnonymous})');
    await refreshProfile();
    _log('perfil: ${profile?.alias ?? '-'}');
    ready = true;
    notifyListeners();
    // Los anuncios se preparan en segundo plano: nunca bloquean el arranque.
    unawaited(Ads.init(minor: profile?.isMinor ?? false).then((_) => _log('anuncios listos')));
  }

  static void _log(String m) => debugPrint('[didacquiz] $m');

  /// Sin sesión, se entra como invitado (usuario anónimo de Supabase).
  Future<void> ensureSession() async {
    if (Supabase.instance.client.auth.currentSession == null) {
      await Supabase.instance.client.auth.signInAnonymously();
    }
  }

  Future<void> refreshProfile() async {
    try {
      profile = user == null
          ? null
          : await api.myProfile().timeout(const Duration(seconds: 15));
    } catch (e) {
      _log('perfil no disponible: $e');
      // sin conexión: se conserva el perfil anterior
    }
    notifyListeners();
  }

  void setProfile(Profile p) {
    profile = p;
    notifyListeners();
  }

  Future<void> setLanguage(String lang) async {
    Strings.lang = lang;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('lang', lang);
    notifyListeners();
  }

  // --- Cuentas -------------------------------------------------------------

  /// Crea una cuenta de usuario y contraseña. Si se estaba jugando como
  /// invitado, se convierte esa misma cuenta, así que la partida de hoy se conserva.
  Future<String?> registerWithPassword({
    required String alias,
    required String password,
    required String country,
    required int cityId,
    required int birthYear,
  }) async {
    final status = await api.aliasStatus(alias);
    if (status != 'ok') throw ApiError('alias_$status');
    final auth = Supabase.instance.client.auth;
    final email = api.emailFor(alias);
    if (auth.currentUser != null && auth.currentUser!.isAnonymous) {
      await auth.updateUser(UserAttributes(email: email));
      await auth.updateUser(UserAttributes(password: password));
      await auth.refreshSession();
    } else {
      await auth.signUp(email: email, password: password);
    }
    final code = await api.registerProfile(
      alias: alias,
      country: country,
      cityId: cityId,
      birthYear: birthYear,
      authMethod: 'password',
    );
    await refreshProfile();
    return code;
  }

  /// Para cuentas de Google o Apple que aún no tienen perfil.
  Future<void> completeOAuthProfile({
    required String alias,
    required String country,
    required int cityId,
    required int birthYear,
  }) async {
    final provider = user?.appMetadata['provider'] == 'apple' ? 'apple' : 'google';
    await api.registerProfile(
      alias: alias,
      country: country,
      cityId: cityId,
      birthYear: birthYear,
      authMethod: provider,
    );
    await refreshProfile();
  }

  Future<void> login(String alias, String password) async {
    try {
      await Supabase.instance.client.auth
          .signInWithPassword(email: api.emailFor(alias.trim()), password: password);
    } on AuthException {
      throw ApiError('login');
    }
    await refreshProfile();
  }

  Future<void> loginWithProvider(OAuthProvider provider) async {
    await Supabase.instance.client.auth.signInWithOAuth(
      provider,
      redirectTo: Config.oauthRedirect,
    );
  }

  Future<void> logout() async {
    await Supabase.instance.client.auth.signOut();
    profile = null;
    await ensureSession();
    notifyListeners();
  }

  Future<void> deleteAccount() async {
    await api.deleteMyAccount();
    await logout();
  }

  @override
  void dispose() {
    _authSub?.cancel();
    super.dispose();
  }
}
