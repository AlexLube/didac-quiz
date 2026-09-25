import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app_state.dart';
import '../config.dart';
import '../models.dart';
import '../services/ads.dart';
import '../services/api.dart';
import '../strings.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'auth_screens.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AppState.instance,
      builder: (context, _) {
        final state = AppState.instance;
        final p = state.profile;
        return Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  _Header(p),
                  const SizedBox(height: 20),
                  if (p == null) ...[
                    FilledButton(
                      onPressed: () => Navigator.of(context)
                          .push(MaterialPageRoute(builder: (_) => const AccountScreen())),
                      child: Text(tr('create_account')),
                    ),
                  ] else ...[
                    Row(
                      children: [
                        Expanded(child: _Stat(tr('streak'), '${p.streakCurrent}')),
                        const SizedBox(width: 12),
                        Expanded(child: _Stat(tr('best_streak'), '${p.streakBest}')),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Card(
                      child: ListTile(
                        leading: const Icon(Icons.place_rounded, color: AppColors.amber),
                        title: Text('${p.cityName}, ${Strings.pick(p.countryName)}'),
                        subtitle: Text(p.canChangeLocation
                            ? tr('change_location')
                            : tr('location_available_on', {
                                'd': '${p.locationChangeAvailableOn.day}/${p.locationChangeAvailableOn.month}/${p.locationChangeAvailableOn.year}'
                              })),
                        onTap: p.canChangeLocation ? () => _changeLocation(context) : null,
                      ),
                    ),
                    if (p.authMethod == 'password')
                      Card(
                        child: ListTile(
                          leading: const Icon(Icons.key_rounded, color: AppColors.amber),
                          title: Text(tr('new_recovery_code')),
                          onTap: () => _newRecoveryCode(context),
                        ),
                      ),
                  ],
                  Card(
                    child: ListTile(
                      leading: const Icon(Icons.translate_rounded, color: AppColors.amber),
                      title: Text(tr('language')),
                      trailing: SegmentedButton<String>(
                        showSelectedIcon: false,
                        segments: const [
                          ButtonSegment(value: 'es', label: Text('ES')),
                          ButtonSegment(value: 'en', label: Text('EN')),
                        ],
                        selected: {Strings.lang},
                        onSelectionChanged: (s) => state.setLanguage(s.first),
                      ),
                    ),
                  ),
                  Card(
                    child: ListTile(
                      leading: const Icon(Icons.privacy_tip_rounded, color: AppColors.amber),
                      title: Text(tr('privacy')),
                      onTap: () => launchUrl(Uri.parse(Config.privacyUrl),
                          mode: LaunchMode.externalApplication),
                    ),
                  ),
                  if (p != null) ...[
                    Card(
                      child: ListTile(
                        leading: const Icon(Icons.logout_rounded),
                        title: Text(tr('logout')),
                        onTap: () => state.logout(),
                      ),
                    ),
                    Card(
                      child: ListTile(
                        leading: const Icon(Icons.delete_forever_rounded, color: AppColors.error),
                        title: Text(tr('delete_account'),
                            style: const TextStyle(color: AppColors.error)),
                        onTap: () => _deleteAccount(context),
                      ),
                    ),
                  ] else
                    Card(
                      child: ListTile(
                        leading: const Icon(Icons.login_rounded),
                        title: Text(tr('login')),
                        onTap: () => Navigator.of(context).push(
                            MaterialPageRoute(builder: (_) => const AccountScreen(startWithLogin: true))),
                      ),
                    ),
                  const SizedBox(height: 16),
                  Text(tr('legal_notice'),
                      style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
                ],
              ),
            ),
            const BannerSlot(),
          ],
        );
      },
    );
  }

  Future<void> _changeLocation(BuildContext context) async {
    String? country;
    City? city;
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(20, 20, 20, MediaQuery.of(ctx).viewInsets.bottom + 20),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(tr('change_location'),
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
              const SizedBox(height: 16),
              LocationPicker(onChanged: (c, ci) {
                country = c;
                city = ci;
              }),
              const SizedBox(height: 16),
              FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr('save'))),
            ],
          ),
        ),
      ),
    );
    if (ok != true || country == null || city == null) return;
    try {
      final p = await AppState.instance.api.updateLocation(country!, city!.id);
      AppState.instance.setProfile(p);
    } on ApiError catch (e) {
      if (context.mounted) showSnack(context, e.message);
    }
  }

  Future<void> _newRecoveryCode(BuildContext context) async {
    try {
      final code = await AppState.instance.api.regenerateRecoveryCode();
      if (!context.mounted) return;
      await Navigator.of(context)
          .push(MaterialPageRoute(builder: (_) => RecoveryCodeScreen(code: code)));
    } on ApiError catch (e) {
      if (context.mounted) showSnack(context, e.message);
    }
  }

  Future<void> _deleteAccount(BuildContext context) async {
    final sure = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('delete_account')),
        content: Text(tr('delete_account_confirm')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('cancel'))),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(tr('delete'), style: const TextStyle(color: AppColors.error)),
          ),
        ],
      ),
    );
    if (sure != true) return;
    try {
      await AppState.instance.deleteAccount();
    } catch (_) {
      if (context.mounted) showSnack(context, tr('error_generic'));
    }
  }
}

class _Header extends StatelessWidget {
  final Profile? p;
  const _Header(this.p);

  @override
  Widget build(BuildContext context) {
    final name = p?.alias ?? tr('guest');
    return Row(
      children: [
        CircleAvatar(
          radius: 34,
          backgroundColor: AppColors.amber,
          foregroundColor: Colors.black,
          child: Text(name.characters.first.toUpperCase(),
              style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w900)),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Text(name, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w900)),
        ),
      ],
    );
  }
}

class _Stat extends StatelessWidget {
  final String label;
  final String value;
  const _Stat(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(18)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(value, style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w900)),
          Text(label, style: const TextStyle(color: AppColors.textMuted)),
        ],
      ),
    );
  }
}
