import 'dart:async';

import 'package:flutter/material.dart';

import '../../app.dart';
import '../../core/app/app_scope.dart';

/// Première page : logo puis routage selon l'identité locale.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_started) {
      _started = true;
      unawaited(_bootstrap());
    }
  }

  Future<void> _bootstrap() async {
    final services = AppScope.of(context);
    await Future<void>.delayed(const Duration(milliseconds: 1200));

    // Une identité complète = profil + clé privée présente dans le KeyStore.
    final ready = await services.identity.isInitialised();
    if (!mounted) return;

    if (ready) {
      Navigator.pushReplacementNamed(context, App.routeHome);
    } else {
      Navigator.pushReplacementNamed(context, App.routeOnboarding);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: Image.asset('assets/images/icon_mesh_1024.png', width: 180),
      ),
    );
  }
}
