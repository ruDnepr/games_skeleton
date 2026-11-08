import 'package:flutter/material.dart';

import '../../presentation/theme.dart';
import '../definition.dart';
import 'network.dart';
import 'rules.dart';
import 'session_page.dart';
import 'settings.dart';

/// Игра «Шашки» в каталоге. Карточка, правила, настройки и точка входа в партию
/// — всё здесь; главное окно, список игр, лобби и звук общие.
final checkersGame = GameDefinition(
  id: checkersGameId,
  title: 'Шашки',
  tagline: 'Бей по диагонали и доходи до дамки',
  icon: Icons.grid_view_rounded,
  accent: purple,
  rules: checkersRules,
  settings: checkersSettings,
  // Кнопка «Играть» на карточке и сетевое лобби ведут сюда. Когда друг уже
  // подключился, [network] заполнен и партия сразу открывается по сети.
  start: (context, settings, {network}) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            CheckersEntryPage(settings: settings, network: network),
      ),
    );
  },
  options: checkersOptions,
  parseOptions: checkersParseOptions,
  validateMove: checkersValidateMove,
  // Хост играет белыми и ходит первым. Просто и предсказуемо для ребёнка.
  hostSide: (_) => 'white',
  // Перед сетевым лобби хост выбирает вариант шашек — русские, классические,
  // международные или поддавки. Выбор сохраняется в настройках и уезжает в
  // рукопожатие через [checkersOptions].
  preNetwork: (context, settings) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            CheckersVariantPage(settings: settings, forNetwork: true),
      ),
    );
  },
);
