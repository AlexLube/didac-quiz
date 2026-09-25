import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show OAuthProvider;

import '../app_state.dart';
import '../config.dart';
import '../models.dart';
import '../services/api.dart';
import '../strings.dart';
import '../theme.dart';
import '../widgets/common.dart';

/// Crear cuenta o iniciar sesión (usuario+contraseña, Google o Apple).
class AccountScreen extends StatefulWidget {
  final bool startWithLogin;
  const AccountScreen({super.key, this.startWithLogin = false});

  @override
  State<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends State<AccountScreen> {
  late bool _login = widget.startWithLogin;
  bool _busy = false;
  bool _manualFlow = false;

  final _alias = TextEditingController();
  final _password = TextEditingController();
  final _year = TextEditingController();
  String? _country;
  City? _city;

  @override
  void initState() {
    super.initState();
    AppState.instance.addListener(_onAuthChanged);
  }

  @override
  void dispose() {
    AppState.instance.removeListener(_onAuthChanged);
    _alias.dispose();
    _password.dispose();
    _year.dispose();
    super.dispose();
  }

  /// Tras volver de Google/Apple, se cierra esta pantalla; si falta el perfil,
  /// la app muestra el formulario para completarlo.
  void _onAuthChanged() {
    final s = AppState.instance;
    if (_manualFlow || !mounted) return;
    if (s.user != null && !s.user!.isAnonymous) {
      Navigator.of(context).popUntil((r) => r.isFirst);
    }
  }

  Future<void> _submit() async {
    final alias = _alias.text.trim();
    final password = _password.text;
    if (_login) {
      setState(() => _busy = true);
      _manualFlow = true;
      try {
        await AppState.instance.login(alias, password);
        if (mounted) Navigator.of(context).popUntil((r) => r.isFirst);
      } on ApiError catch (e) {
        if (mounted) showSnack(context, e.message);
      } finally {
        _manualFlow = false;
        if (mounted) setState(() => _busy = false);
      }
      return;
    }

    final year = int.tryParse(_year.text.trim());
    if (password.length < 8) {
      showSnack(context, tr('err_weak_password'));
      return;
    }
    if (_country == null || _city == null) {
      showSnack(context, tr('err_invalid_location'));
      return;
    }
    if (year == null) {
      showSnack(context, tr('err_invalid_birth_year'));
      return;
    }
    setState(() => _busy = true);
    _manualFlow = true;
    try {
      final code = await AppState.instance.registerWithPassword(
        alias: alias,
        password: password,
        country: _country!,
        cityId: _city!.id,
        birthYear: year,
      );
      if (!mounted) return;
      if (code != null) {
        await Navigator.of(context)
            .push(MaterialPageRoute(builder: (_) => RecoveryCodeScreen(code: code)));
      }
      if (mounted) Navigator.of(context).popUntil((r) => r.isFirst);
    } on ApiError catch (e) {
      if (mounted) showSnack(context, e.message);
    } catch (_) {
      if (mounted) showSnack(context, tr('error_generic'));
    } finally {
      _manualFlow = false;
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _oauth(OAuthProvider provider) async {
    try {
      await AppState.instance.loginWithProvider(provider);
    } catch (_) {
      if (mounted) showSnack(context, tr('error_generic'));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_login ? tr('login') : tr('create_account'))),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            SegmentedButton<bool>(
              segments: [
                ButtonSegment(value: false, label: Text(tr('create_account'))),
                ButtonSegment(value: true, label: Text(tr('login'))),
              ],
              selected: {_login},
              onSelectionChanged: (s) => setState(() => _login = s.first),
            ),
            const SizedBox(height: 16),
            if (Config.enableGoogleLogin)
              OutlinedButton.icon(
                onPressed: _busy ? null : () => _oauth(OAuthProvider.google),
                icon: const Icon(Icons.g_mobiledata_rounded, size: 32),
                label: Text(tr('continue_google')),
              ),
            if (Config.enableAppleLogin) ...[
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: _busy ? null : () => _oauth(OAuthProvider.apple),
                icon: const Icon(Icons.apple_rounded),
                label: Text(tr('continue_apple')),
              ),
            ],
            if (Config.enableGoogleLogin || Config.enableAppleLogin)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Row(children: [
                  const Expanded(child: Divider()),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Text(tr('or'), style: const TextStyle(color: AppColors.textMuted)),
                  ),
                  const Expanded(child: Divider()),
                ]),
              ),
            Text(tr('no_email_note'), style: const TextStyle(color: AppColors.textMuted)),
            const SizedBox(height: 12),
            TextField(
              controller: _alias,
              autocorrect: false,
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9_.\-]'))],
              maxLength: 20,
              decoration: InputDecoration(
                labelText: tr('alias'),
                helperText: _login ? null : tr('alias_help'),
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _password,
              obscureText: true,
              decoration: InputDecoration(
                labelText: tr('password'),
                helperText: _login ? null : tr('password_help'),
              ),
            ),
            if (!_login) ...[
              const SizedBox(height: 16),
              LocationPicker(onChanged: (c, city) {
                _country = c;
                _city = city;
              }),
              const SizedBox(height: 12),
              TextField(
                controller: _year,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                maxLength: 4,
                decoration: InputDecoration(labelText: tr('birth_year')),
              ),
            ],
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _busy ? null : _submit,
              child: _busy
                  ? const SizedBox(
                      width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5))
                  : Text(_login ? tr('login') : tr('create_account')),
            ),
            if (_login)
              TextButton(
                onPressed: () => Navigator.of(context)
                    .push(MaterialPageRoute(builder: (_) => const RecoverScreen())),
                child: Text(tr('forgot_password')),
              ),
          ],
        ),
      ),
    );
  }
}

/// Perfil para cuentas de Google o Apple (sin contraseña).
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _alias = TextEditingController();
  final _year = TextEditingController();
  String? _country;
  City? _city;
  bool _busy = false;

  @override
  void dispose() {
    _alias.dispose();
    _year.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final year = int.tryParse(_year.text.trim());
    if (_country == null || _city == null) {
      showSnack(context, tr('err_invalid_location'));
      return;
    }
    if (year == null) {
      showSnack(context, tr('err_invalid_birth_year'));
      return;
    }
    setState(() => _busy = true);
    try {
      final status = await AppState.instance.api.aliasStatus(_alias.text.trim());
      if (status != 'ok') throw ApiError('alias_$status');
      await AppState.instance.completeOAuthProfile(
        alias: _alias.text.trim(),
        country: _country!,
        cityId: _city!.id,
        birthYear: year,
      );
    } on ApiError catch (e) {
      if (mounted) showSnack(context, e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(tr('complete_profile')),
        actions: [
          TextButton(onPressed: () => AppState.instance.logout(), child: Text(tr('cancel'))),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            TextField(
              controller: _alias,
              autocorrect: false,
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9_.\-]'))],
              maxLength: 20,
              decoration: InputDecoration(labelText: tr('alias'), helperText: tr('alias_help')),
            ),
            const SizedBox(height: 12),
            LocationPicker(onChanged: (c, city) {
              _country = c;
              _city = city;
            }),
            const SizedBox(height: 12),
            TextField(
              controller: _year,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              maxLength: 4,
              decoration: InputDecoration(labelText: tr('birth_year')),
            ),
            const SizedBox(height: 16),
            FilledButton(onPressed: _busy ? null : _save, child: Text(tr('save'))),
          ],
        ),
      ),
    );
  }
}

/// Recuperar cuenta con alias + código de recuperación.
class RecoverScreen extends StatefulWidget {
  const RecoverScreen({super.key});

  @override
  State<RecoverScreen> createState() => _RecoverScreenState();
}

class _RecoverScreenState extends State<RecoverScreen> {
  final _alias = TextEditingController();
  final _code = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _alias.dispose();
    _code.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _recover() async {
    if (_password.text.length < 8) {
      showSnack(context, tr('err_weak_password'));
      return;
    }
    setState(() => _busy = true);
    try {
      final alias = _alias.text.trim();
      final newCode = await AppState.instance.api.recoverAccount(alias, _code.text, _password.text);
      if (!mounted) return;
      if (newCode == null) {
        showSnack(context, tr('err_recovery'));
        return;
      }
      await AppState.instance.login(alias, _password.text);
      if (!mounted) return;
      await Navigator.of(context)
          .push(MaterialPageRoute(builder: (_) => RecoveryCodeScreen(code: newCode)));
      if (mounted) Navigator.of(context).popUntil((r) => r.isFirst);
    } on ApiError catch (e) {
      if (mounted) showSnack(context, e.code == 'invalid_recovery' ? tr('err_recovery') : e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(tr('recover_account'))),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            TextField(controller: _alias, decoration: InputDecoration(labelText: tr('alias'))),
            const SizedBox(height: 12),
            TextField(
              controller: _code,
              textCapitalization: TextCapitalization.characters,
              decoration: InputDecoration(labelText: tr('recovery_code'), hintText: 'XXXX-XXXX-XXXX'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _password,
              obscureText: true,
              decoration: InputDecoration(labelText: tr('new_password'), helperText: tr('password_help')),
            ),
            const SizedBox(height: 16),
            FilledButton(onPressed: _busy ? null : _recover, child: Text(tr('recover_account'))),
          ],
        ),
      ),
    );
  }
}

/// Muestra el código de recuperación una sola vez.
class RecoveryCodeScreen extends StatelessWidget {
  final String code;
  const RecoveryCodeScreen({super.key, required this.code});

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Scaffold(
        appBar: AppBar(automaticallyImplyLeading: false, title: Text(tr('recovery_code'))),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Icon(Icons.key_rounded, size: 56, color: AppColors.amber),
                const SizedBox(height: 16),
                Text(tr('recovery_code_title'),
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
                const SizedBox(height: 12),
                Text(tr('recovery_code_body'), textAlign: TextAlign.center),
                const SizedBox(height: 24),
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 22),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: AppColors.amber, width: 2),
                  ),
                  child: SelectableText(
                    code,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        fontSize: 28, fontWeight: FontWeight.w900, letterSpacing: 3,
                        fontFamily: 'monospace'),
                  ),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: code));
                    showSnack(context, tr('copied'));
                  },
                  icon: const Icon(Icons.copy_rounded),
                  label: Text(tr('copy')),
                ),
                const Spacer(),
                FilledButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(tr('saved_it')),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
