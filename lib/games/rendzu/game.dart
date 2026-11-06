import 'package:flutter/material.dart';

import '../../presentation/theme.dart';
import '../definition.dart';
import 'network.dart';
import 'rules.dart';
import 'session_page.dart';
import 'settings.dart';

/// Игра «Рэндзю» в каталоге. Карточка, правила, настройки и точка входа в
/// партию — всё здесь; главное окно, список игр, лобби и звук общие.
final rendzuGame = GameDefinition(
  id: rendzuGameId,
  title: 'Рэндзю',
  tagline: 'Пять камней в ряд — и победа',
  icon: Icons.bubble_chart_rounded,
  accent: purple,
  rules: rendzuRules,
  settings: rendzuSettings,
  // Кнопка «Играть» на карточке и сетевое лобби ведут сюда. Когда друг уже
  // подключился, [network] заполнен и партия сразу открывается по сети.
  start: (context, settings, {network}) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            RendzuEntryPage(settings: settings, network: network),
      ),
    );
  },
  options: rendzuOptions,
  parseOptions: rendzuParseOptions,
  validateMove: rendzuValidateMove,
  // Хост играет чёрными и ходит первым — так же, как белые в нардах. Просто и
  // предсказуемо для ребёнка.
  hostSide: (_) => 'black',
);
