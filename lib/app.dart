import 'package:flutter/material.dart';

import 'features/onboarding/onboarding_screen.dart';
import 'features/shell/home_shell.dart';
import 'features/splash/splash_screen.dart';

class App extends StatelessWidget {
  const App({super.key});

  static const String routeSplash = '/';
  static const String routeOnboarding = '/onboarding';
  static const String routeHome = '/home';

  @override
  Widget build(BuildContext context) {
    final scheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFF1D9E75), // vert-sarcelle : résilience / mesh
    );
    return MaterialApp(
      title: 'TraNaSi',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorScheme: scheme, useMaterial3: true),
      initialRoute: routeSplash,
      routes: {
        routeSplash: (_) => const SplashScreen(),
        routeOnboarding: (_) => const OnboardingScreen(),
        routeHome: (_) => const HomeShell(),
      },
    );
  }
}
