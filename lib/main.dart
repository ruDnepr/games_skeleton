import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/settings.dart';
import 'app/sounds.dart';
import 'presentation/home.dart';
import 'presentation/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  final settings = SettingsController();
  // Preparing the audio players and reading the settings can share the same
  // start-up wait. The first sound is only needed after the splash screen, so
  // a slow audio device must never delay the first frame.
  final audio = PoolsSfxBackend.instance.load();
  await settings.load();
  runApp(ProviderScope(child: DianaApp(settings: settings)));
  unawaited(audio);
}

class DianaApp extends StatelessWidget {
  const DianaApp({super.key, required this.settings, this.showSplash = true});
  final SettingsController settings;
  final bool showSplash;
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Игры для Дианы',
    debugShowCheckedModeBanner: false,
    theme: dianaTheme(),
    home: showSplash
        ? SplashPage(settings: settings)
        : HomePage(settings: settings),
  );
}
