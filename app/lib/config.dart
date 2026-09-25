import 'package:flutter/foundation.dart';

/// Configuración que se inyecta al compilar con --dart-define
/// (ver README y el workflow de GitHub Actions).
class Config {
  static const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

  /// Dominio ficticio para convertir el alias en el "email" interno de
  /// Supabase Auth. Nunca se envía ningún correo.
  static const playerEmailDomain =
      String.fromEnvironment('PLAYER_EMAIL_DOMAIN', defaultValue: 'players.didaccine.com');

  static const enableGoogleLogin =
      bool.fromEnvironment('ENABLE_GOOGLE_LOGIN', defaultValue: false);
  static const enableAppleLogin =
      bool.fromEnvironment('ENABLE_APPLE_LOGIN', defaultValue: false);
  static const oauthRedirect = 'com.didacquiz.app://login-callback/';

  static const privacyUrl = String.fromEnvironment('PRIVACY_URL',
      defaultValue: 'https://www.didaccine.com/didac-quiz-privacidad');

  // Anuncios: por defecto, los identificadores de PRUEBA de Google.
  static const _testBanner = 'ca-app-pub-3940256099942544/6300978111';
  static const _testInterstitial = 'ca-app-pub-3940256099942544/1033173712';
  static const _testRewarded = 'ca-app-pub-3940256099942544/5224354917';
  static const bannerId =
      String.fromEnvironment('ADMOB_BANNER_ID', defaultValue: _testBanner);
  static const interstitialId =
      String.fromEnvironment('ADMOB_INTERSTITIAL_ID', defaultValue: _testInterstitial);
  static const rewardedId =
      String.fromEnvironment('ADMOB_REWARDED_ID', defaultValue: _testRewarded);

  static bool get isConfigured => supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty;

  static bool get adsSupported =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);
}
