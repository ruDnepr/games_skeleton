import 'package:flutter/material.dart';

import '../../presentation/theme.dart';
import '../definition.dart';
import 'network.dart';
import 'rules.dart';
import 'session_page.dart';
import 'settings.dart';

/// Игра «Го» в каталоге. Карточка, правила, настройки и точка входа в
/// партию — всё здесь; главное окно, список игр, лобби и звук общие.
final goGame = GameDefinition(
  id: goGameId,
  title: 'Го',
  tagline: 'Окружай камни и забирай территорию',
  icon: Icons.circle_rounded,
  accent: deepPurple,
  rules: goRules,
  settings: goSettings,
  // Кнопка «Играть» на карточке и сетевое лобби ведут сюда. Когда друг уже
  // подключился, [network] заполнен и партия сразу открывается по сети.
  start: (context, settings, {network}) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            GoEntryPage(settings: settings, network: network),
      ),
    );
  },
  options: goOptions,
  parseOptions: goParseOptions,
  validateMove: goValidateMove,
  // Хост играет чёрными и ходит первым — как в настоящем го.
  hostSide: (_) => 'black',
);
