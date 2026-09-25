import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import '../config.dart';

/// Publicidad con Google AdMob. Nunca se muestra un anuncio en mitad del reto.
class Ads {
  static bool _ready = false;
  static bool _minor = false;

  static Future<void> init({required bool minor}) async {
    if (!Config.adsSupported) return;
    _minor = minor;
    try {
      await _requestConsent(minor);
      if (minor) {
        await MobileAds.instance.updateRequestConfiguration(RequestConfiguration(
          tagForUnderAgeOfConsent: TagForUnderAgeOfConsent.yes,
          maxAdContentRating: MaxAdContentRating.t,
        ));
      }
      await MobileAds.instance.initialize().timeout(const Duration(seconds: 20));
      _ready = true;
    } catch (_) {
      _ready = false;
    }
  }

  /// Formulario de consentimiento de Google (obligatorio en la UE).
  static Future<void> _requestConsent(bool minor) {
    final done = Completer<void>();
    ConsentInformation.instance.requestConsentInfoUpdate(
      ConsentRequestParameters(tagForUnderAgeOfConsent: minor),
      () {
        ConsentForm.loadAndShowConsentFormIfRequired((FormError? error) {
          if (!done.isCompleted) done.complete();
        });
      },
      (FormError error) {
        if (!done.isCompleted) done.complete();
      },
    );
    return done.future.timeout(const Duration(seconds: 15), onTimeout: () {});
  }

  static AdRequest _request() => AdRequest(nonPersonalizedAds: _minor);

  /// Intersticial al terminar el reto. Si no carga en unos segundos, se sigue sin anuncio.
  static Future<void> showInterstitial() async {
    if (!_ready) return;
    final done = Completer<void>();
    var timedOut = false;
    var shown = false;
    InterstitialAd.load(
      adUnitId: Config.interstitialId,
      request: _request(),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (ad) {
          if (timedOut) {
            ad.dispose();
            return;
          }
          shown = true;
          ad.fullScreenContentCallback = FullScreenContentCallback(
            onAdDismissedFullScreenContent: (ad) {
              ad.dispose();
              if (!done.isCompleted) done.complete();
            },
            onAdFailedToShowFullScreenContent: (ad, error) {
              ad.dispose();
              if (!done.isCompleted) done.complete();
            },
          );
          ad.show();
        },
        onAdFailedToLoad: (error) {
          if (!done.isCompleted) done.complete();
        },
      ),
    );
    await done.future.timeout(const Duration(seconds: 6), onTimeout: () {
      if (!shown) timedOut = true;
    });
    // Si el anuncio llegó a mostrarse, esperamos a que el jugador lo cierre.
    if (shown) await done.future;
  }

  /// Anuncio con recompensa. Devuelve true si el jugador lo vio entero.
  static Future<bool> showRewarded() async {
    if (!_ready) return false;
    final done = Completer<bool>();
    var earned = false;
    RewardedAd.load(
      adUnitId: Config.rewardedId,
      request: _request(),
      rewardedAdLoadCallback: RewardedAdLoadCallback(
        onAdLoaded: (ad) {
          ad.fullScreenContentCallback = FullScreenContentCallback(
            onAdDismissedFullScreenContent: (ad) {
              ad.dispose();
              if (!done.isCompleted) done.complete(earned);
            },
            onAdFailedToShowFullScreenContent: (ad, error) {
              ad.dispose();
              if (!done.isCompleted) done.complete(false);
            },
          );
          ad.show(onUserEarnedReward: (ad, reward) => earned = true);
        },
        onAdFailedToLoad: (error) {
          if (!done.isCompleted) done.complete(false);
        },
      ),
    );
    return done.future;
  }
}

/// Banner para las pantallas de ranking y perfil.
class BannerSlot extends StatefulWidget {
  const BannerSlot({super.key});

  @override
  State<BannerSlot> createState() => _BannerSlotState();
}

class _BannerSlotState extends State<BannerSlot> {
  BannerAd? _ad;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    if (!Ads._ready) return;
    _ad = BannerAd(
      adUnitId: Config.bannerId,
      size: AdSize.banner,
      request: Ads._request(),
      listener: BannerAdListener(
        onAdLoaded: (_) {
          if (mounted) setState(() => _loaded = true);
        },
        onAdFailedToLoad: (ad, error) => ad.dispose(),
      ),
    )..load();
  }

  @override
  void dispose() {
    _ad?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_ad == null || !_loaded) return const SizedBox.shrink();
    return SafeArea(
      top: false,
      child: SizedBox(
        height: _ad!.size.height.toDouble(),
        width: _ad!.size.width.toDouble(),
        child: AdWidget(ad: _ad!),
      ),
    );
  }
}
