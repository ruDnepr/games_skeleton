import 'package:flutter/material.dart';

import '../definition.dart';
import 'engine/levels.dart';
import 'network.dart';
import 'progress.dart';
import 'rules.dart';
import 'session_page.dart';
import 'settings.dart';

/// Игра «Push Hour» в каталоге. Карточка, правила, настройки и точка входа в
/// партию — всё здесь; главное окно, список игр, лобби и звук общие.
final pushHourGame = GameDefinition(
  id: pushHourGameId,
  title: 'Push Hour',
  tagline: 'Выведи красную машину с парковки',
  icon: Icons.directions_car_rounded,
  accent: const Color(0xFFFF4B4B),
  rules: pushHourRules,
  settings: pushHourSettings,
  // Кнопка «Играть» на карточке и сетевое лобби ведут сюда. Когда друг уже
  // подключился, [network] заполнен и партия сразу открывается по сети тем
  // уровнем, который выбрал хост.
  start: (context, settings, {network}) async {
    final progress = PushHourProgress();
    await progress.load();
    final level = network == null
        ? levelByNumber(progress.unlockedLevel)
        : levelByNumber(pushHourParseOptions(network.lobby.options));
    if (!context.mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PushHourEntryPage(
          settings: settings,
          progress: progress,
          level: level,
          network: network,
        ),
      ),
    );
  },
  options: pushHourOptions,
  parseOptions: pushHourParseOptions,
  validateMove: pushHourValidateMove,
  // У Push Hour нет «сторон»: каждый решает свою головоломку. Хост — это просто
  // хост.
  hostSide: (_) => 'host',
);
