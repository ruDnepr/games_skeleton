import 'package:flutter/material.dart';

import '../../presentation/theme.dart';
import '../definition.dart';
import 'network.dart';
import 'rules.dart';
import 'session_page.dart';
import 'settings.dart';

/// Игра «Домино» в каталоге. Карточка, правила, настройки и точка входа в
/// партию — всё здесь; главное окно, список игр, лобби и звук общие.
final dominoGame = GameDefinition(
  id: dominoGameId,
  title: 'Домино',
  tagline: 'Выкладывай кости и опустошай руку',
  icon: Icons.dock_rounded,
  accent: peach,
  rules: dominoRules,
  settings: dominoSettings,
  // Кнопка «Играть» на карточке и сетевое лобби ведут сюда. Когда друг уже
  // подключился, [network] заполнен и партия сразу открывается по сети.
  start: (context, settings, {network}) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            DominoEntryPage(settings: settings, network: network),
      ),
    );
  },
  options: dominoOptions,
  parseOptions: dominoParseOptions,
  validateMove: dominoValidateMove,
  // Хост играет за место 0 и ходит первым (выкладывает стартовую кость).
  hostSide: (_) => 'me',
);
