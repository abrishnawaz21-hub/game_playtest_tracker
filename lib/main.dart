import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'data.dart';
import 'features/auth/auth_screens.dart';
import 'game.dart';
import 'screens.dart';
import 'theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (isConfigured) {
    await Supabase.initialize(url: supabaseUrl, publishableKey: supabaseAnonKey);
  }
  runApp(const ProviderScope(child: App()));
}

class _AuthRefresh extends ChangeNotifier {
  late final StreamSubscription _sub;
  /// True after the user opened a password-reset email link: they must choose a new password.
  bool recovering = false;
  _AuthRefresh() {
    _sub = sb.auth.onAuthStateChange.listen((s) {
      if (s.event == AuthChangeEvent.passwordRecovery) recovering = true;
      if (s.event == AuthChangeEvent.signedOut) recovering = false;
      notifyListeners();
    });
  }
  @override
  void dispose() {
    _sub.cancel();
    super.dispose();
  }
}

class App extends StatefulWidget {
  const App({super.key});
  @override
  State<App> createState() => _AppState();
}

class _AppState extends State<App> {
  final _auth = isConfigured ? _AuthRefresh() : null;
  late final GoRouter? _router = isConfigured ? _buildRouter() : null;
  // Reduced motion: no splash at all. Otherwise a short one that any tap skips.
  bool _splash = !WidgetsBinding.instance.platformDispatcher.accessibilityFeatures.disableAnimations;

  @override
  void initState() {
    super.initState();
    Future.delayed(const Duration(milliseconds: 700), _endSplash);
  }

  void _endSplash() {
    if (mounted && _splash) setState(() => _splash = false);
  }

  static const _public = {'/login', '/forgot-password'};

  GoRouter _buildRouter() => GoRouter(
        refreshListenable: _auth,
        redirect: (context, state) {
          final signedIn = sb.auth.currentSession != null;
          final at = state.matchedLocation;
          if (_auth!.recovering && signedIn) return at == '/reset-password' ? null : '/reset-password';
          if (!signedIn && !_public.contains(at)) return '/login';
          if (signedIn && _public.contains(at)) return '/';
          return null;
        },
        routes: [
          GoRoute(path: '/login', builder: (_, _) => const LoginScreen()),
          GoRoute(path: '/forgot-password', builder: (_, _) => const ForgotPasswordScreen()),
          GoRoute(path: '/reset-password', builder: (_, _) => const ResetPasswordScreen()),
          GoRoute(path: '/delete-account', builder: (_, _) => const DeleteAccountScreen()),
          GoRoute(path: '/', builder: (_, _) => const RootShell()),
          GoRoute(
              path: '/game/:id',
              builder: (_, s) => GameShell(id: s.pathParameters['id']!)),
          GoRoute(
              path: '/report/:id',
              builder: (_, s) => ReportScreen(id: s.pathParameters['id']!)),
          GoRoute(
              path: '/session/:id',
              builder: (_, s) => SessionScreen(id: s.pathParameters['id']!)),
        ],
      );

  @override
  Widget build(BuildContext context) {
    final theme = appTheme();
    if (_splash) {
      return MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: theme,
          home: Scaffold(
            backgroundColor: darkPanel,
            body: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _endSplash, // tap anywhere to skip
              child: const Center(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                LogoMark(size: 96),
                SizedBox(height: 20),
                Text.rich(TextSpan(children: [
                  TextSpan(text: 'Playtest ', style: TextStyle(fontWeight: FontWeight.w700)),
                  TextSpan(text: 'Tracker'),
                ]), style: TextStyle(color: Colors.white, fontSize: 26)),
              ])),
            ),
          ));
    }
    if (_router == null) {
      return MaterialApp(
          theme: theme, home: const Scaffold(body: SetupNeeded()));
    }
    return MaterialApp.router(
      title: 'Game Playtest Tracker',
      theme: theme,
      routerConfig: _router,
      // The prototype is drawn for a ~390dp phone; DejaVu runs wide, so scale type down.
      // Smallest text is 13.1 x 0.92 = 12 px. The user's own text-size setting is kept: it is multiplied, not replaced.
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(0.92 * MediaQuery.textScalerOf(context).scale(1))),
        child: child!,
      ),
    );
  }
}
