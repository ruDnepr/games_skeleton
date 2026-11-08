import 'package:flutter/material.dart';

import '../../presentation/theme.dart';
import '../definition.dart';
import 'network.dart';
import 'rules.dart';
import 'settings.dart';
import 'session_page.dart';

/// Игра «Нарды» в каталоге. Короткие и длинные нарды — варианты одной игры:
/// карточка одна, вариант выбирается на отдельном экране перед партией (или
/// перед сетевым лобби, если друг уже на подходе). Правила, настройки и точка
/// входа в партию — всё здесь; главное окно, список игр, лобби и звук общие.
final backgammonGame = GameDefinition(
  id: backgammonGameId,
  title: 'Нарды',
  tagline: 'Бросай кости и спеши домой',
  icon: Icons.casino_rounded,
  accent: peach,
  rules: backgammonRules,
  settings: backgammonSettings,
  // Кнопка «Играть» на карточке ведёт сюда. Выбор варианта (короткие или
  // длинные) делает сама игра на своём экране; когда друг уже подключился,
  // [network] заполнен и партия сразу открывается по сети тем вариантом,
  // который выбрал хост.
  start: (context, settings, {network}) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            BackgammonEntryPage(settings: settings, network: network),
      ),
    );
  },
  options: backgammonOptions,
  parseOptions: backgammonParseOptions,
  validateMove: backgammonValidateMove,
  // Хост играет белыми и ходит первым. Просто и предсказуемо для ребёнка.
  hostSide: (_) => 'white',
  // Перед сетевым лобби хост выбирает вариант — короткие или длинные. Выбор
  // сохраняется в настройках и уезжает в рукопожатие через [backgammonOptions].
  preNetwork: (context, settings) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            BackgammonVariantPage(settings: settings, forNetwork: true),
      ),
    );
  },
);
