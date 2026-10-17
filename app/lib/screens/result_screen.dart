import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:share_plus/share_plus.dart';

import '../app_state.dart';
import '../models.dart';
import '../services/ads.dart';
import '../services/achievements.dart';
import '../services/api.dart';
import '../share_text.dart';
import '../strings.dart';
import '../theme.dart';
import '../widgets/cinema.dart';
import '../widgets/common.dart';
import '../widgets/unlock_dialog.dart';
import 'auth_screens.dart';

class ResultScreen extends StatefulWidget {
  final bool justFinished;
  final VoidCallback onOpenRankings;
  const ResultScreen({super.key, this.justFinished = false, required this.onOpenRankings});

  @override
  State<ResultScreen> createState() => _ResultScreenState();
}

class _ResultScreenState extends State<ResultScreen> {
  GameSummary? _game;
  final _ticketKey = GlobalKey();
  Object? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      // Intersticial al terminar el reto, antes de ver el resultado.
      if (widget.justFinished) await Ads.showInterstitial();
      final g = await AppState.instance.api.gameSummary();
      await AppState.instance.refreshProfile();
      if (mounted) setState(() => _game = g);
      if (widget.justFinished && !AppState.instance.isGuest) {
        final fresh = await Achievements.instance.takeNew();
        if (mounted && fresh.isNotEmpty) {
          await Future<void>.delayed(const Duration(milliseconds: 700));
          if (mounted) await showAchievementsUnlocked(context, fresh);
        }
      }
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  Future<void> _share() async {
    final g = _game;
    if (g == null) return;
    final text = buildShareText(g, streak: AppState.instance.profile?.streakCurrent ?? 0);
    if (kIsWeb) {
      await SharePlus.instance.share(ShareParams(text: text));
      return;
    }
    try {
      final boundary = _ticketKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary != null) {
        final image = await boundary.toImage(pixelRatio: 3);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        if (bytes != null) {
          final file = File('${Directory.systemTemp.path}/didaccine-quiz-${g.date.toIso8601String().substring(0, 10)}.png');
          await file.writeAsBytes(bytes.buffer.asUint8List(), flush: true);
          await SharePlus.instance.share(ShareParams(text: text, files: [XFile(file.path, mimeType: 'image/png')]));
          return;
        }
      }
    } catch (_) {
      if (mounted) showSnack(context, tr('share_image_failed'));
    }
    await SharePlus.instance.share(ShareParams(text: text));
  }

  Future<void> _restoreStreak() async {
    final earned = await Ads.showRewarded();
    if (!mounted) return;
    if (!earned) {
      showSnack(context, tr('ad_not_available'));
      return;
    }
    try {
      final p = await AppState.instance.api.restoreStreak();
      AppState.instance.setProfile(p);
      if (mounted) {
        setState(() {});
        showSnack(context, tr('streak_restored'));
      }
    } on ApiError catch (e) {
      if (mounted) showSnack(context, e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(tr('your_result').toUpperCase())),
      body: SafeArea(child: _body()),
    );
  }

  Widget _body() {
    if (_error != null) return ErrorView(message: tr('error_generic'), onRetry: _load);
    final g = _game;
    if (g == null) return const Center(child: CircularProgressIndicator());
    final state = AppState.instance;
    final profile = state.profile;
    final celebrate = g.maxPoints > 0 && g.totalPoints / g.maxPoints >= 0.7;
    return Stack(children: [
      ListView(
      padding: const EdgeInsets.all(20),
      children: [
        RepaintBoundary(
          key: _ticketKey,
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: const BoxDecoration(gradient: AppColors.backgroundGradient),
            child: TicketCard(game: g, streak: profile?.streakCurrent ?? 0),
          ),
        ),
        const SizedBox(height: 20),
        FilledButton.icon(
          onPressed: _share,
          icon: const Icon(Icons.ios_share_rounded),
          label: Text(tr('share')),
        ),
        const SizedBox(height: 12),
        if (state.isGuest)
          OutlinedButton.icon(
            onPressed: () async {
              await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const AccountScreen()));
              if (mounted) setState(() {});
            },
            icon: const Icon(Icons.person_add_alt_1_rounded),
            label: Text(tr('create_account_to_rank')),
          )
        else
          OutlinedButton.icon(
            onPressed: () {
              Navigator.of(context).popUntil((r) => r.isFirst);
              widget.onOpenRankings();
            },
            icon: const Icon(Icons.emoji_events_rounded),
            label: Text(tr('see_rankings')),
          ),
        if (profile != null && profile.canRestoreStreak && profile.streakLost != null) ...[
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Text(tr('streak_lost', {'n': profile.streakLost!})),
                  const SizedBox(height: 8),
                  TextButton.icon(
                    onPressed: _restoreStreak,
                    icon: const Icon(Icons.play_circle_rounded),
                    label: Text(tr('restore_streak')),
                  ),
                ],
              ),
            ),
          ),
        ],
        const SizedBox(height: 20),
        Text(tr('solutions_tomorrow'),
            textAlign: TextAlign.center, style: const TextStyle(color: AppColors.textMuted)),
      ],
    ),
      if (celebrate) const Positioned.fill(child: ConfettiBurst()),
    ]);
  }
}
