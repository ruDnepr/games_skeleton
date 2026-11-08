import 'package:flutter/material.dart';

import '../../presentation/theme.dart';
import '../definition.dart';
import 'network.dart';
import 'rules.dart';
import 'session_page.dart';
import 'settings.dart';

/// Игра «Морской бой» в каталоге. Карточка, правила, настройки и точка входа в
/// партию — всё здесь; главное окно, список игр, лобби и звук общие.
final battleshipGame = GameDefinition(
  id: battleshipGameId,
  title: 'Морской бой',
  tagline: 'Расставь корабли и потопи флот соперника',
  icon: Icons.directions_boat_rounded,
  // Морская волна — но из палитры каркаса берём глубокий фиолетовый, чтобы
  // карточка гармонировала с остальными играми.
  accent: deepPurple,
  rules: battleshipRules,
  settings: battleshipSettings,
  // Кнопка «Играть» на карточке и сетевое лобби ведут сюда. Когда друг уже
  // подключился, [network] заполнен и партия сразу открывается по сети.
  start: (context, settings, {network}) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => BattleshipEntryPage(
          settings: settings,
          network: network,
        ),
      ),
    );
  },
  options: battleshipOptions,
  parseOptions: battleshipParseOptions,
  validateMove: battleshipValidateMove,
  // Хост стреляет первым — как белые в шашках. Просто и предсказуемо для
  // ребёнка: тот, кто создал комнату, начинает бой.
  hostSide: (_) => 'me',
);
