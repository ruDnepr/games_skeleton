import 'package:flutter/material.dart';

import '../../presentation/theme.dart';
import '../definition.dart';
import 'network.dart';
import 'rules.dart';
import 'session_page.dart';
import 'settings.dart';

/// Игра «Лото» в каталоге. Карточка, правила, настройки и точка входа в
/// партию — всё здесь; главное окно, список игр, лобби и звук общие.
final lotoGame = GameDefinition(
  id: lotoGameId,
  title: 'Лото',
  tagline: 'Закрывай числа и собирай строку',
  icon: Icons.bubble_chart_rounded,
  accent: yellow,
  rules: lotoRules,
  settings: lotoSettings,
  // Кнопка «Играть» на карточке и сетевое лобби ведут сюда. Когда друг уже
  // подключился, [network] заполнен и партия сразу открывается по сети.
  start: (context, settings, {network}) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            LotoEntryPage(settings: settings, network: network),
      ),
    );
  },
  options: lotoOptions,
  parseOptions: lotoParseOptions,
  validateMove: lotoValidateMove,
  // Хост — ведущий: он тянет бочонки и объявляет их. Просто и предсказуемо.
  hostSide: (_) => 'host',
);
