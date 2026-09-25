import 'package:flutter/material.dart';

import 'app_state.dart';
import 'config.dart';
import 'screens/auth_screens.dart';
import 'screens/home_screen.dart';
import 'strings.dart';
import 'theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const DidacQuizApp());
}

class DidacQuizApp extends StatelessWidget {
  const DidacQuizApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AppState.instance,
      builder: (context, _) => MaterialApp(
        title: 'Didac-Quiz',
        debugShowCheckedModeBanner: false,
        theme: buildTheme(),
        home: const StartGate(),
      ),
    );
  }
}

/// Arranque: configuración, sesión (invitado si hace falta) y perfil.
class StartGate extends StatefulWidget {
  const StartGate({super.key});

  @override
  State<StartGate> createState() => _StartGateState();
}

class _StartGateState extends State<StartGate> {
  Object? _error;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    if (!Config.isConfigured) return;
    setState(() => _error = null);
    try {
      if (!AppState.instance.ready) await AppState.instance.init();
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = AppState.instance;
    if (!Config.isConfigured) {
      return _Splash(child: Text(tr('not_configured'), textAlign: TextAlign.center));
    }
    if (_error != null) {
      return _Splash(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(tr('error_generic'), textAlign: TextAlign.center),
            const SizedBox(height: 16),
            OutlinedButton(onPressed: _start, child: Text(tr('retry'))),
          ],
        ),
      );
    }
    if (!state.ready) {
      return const _Splash(child: CircularProgressIndicator());
    }
    if (state.needsOnboarding) {
      return const OnboardingScreen();
    }
    return const HomeShell();
  }
}

class _Splash extends StatelessWidget {
  final Widget child;
  const _Splash({required this.child});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.movie_filter_rounded, size: 72, color: Color(0xFFFFB300)),
                const SizedBox(height: 12),
                Text(tr('app_name'),
                    style: const TextStyle(fontSize: 34, fontWeight: FontWeight.w900)),
                Text(tr('tagline'), style: const TextStyle(color: Color(0xFFA0A0AE))),
                const SizedBox(height: 32),
                child,
              ],
            ),
          ),
        ),
      ),
    );
  }
}
