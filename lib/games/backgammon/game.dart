import 'package:flutter/material.dart';

import '../../presentation/theme.dart';
import '../definition.dart';
import 'engine/model.dart';
import 'network.dart';
import 'rules.dart';
import 'settings.dart';
import 'session_page.dart';

/// Игра «Короткие нарды» в каталоге. Карточка, правила, настройки и точка входа
/// в партию — всё здесь; главное окно, список игр, лобби и звук общие.
final backgammonGame = GameDefinition(
  id: backgammonGameId,
  title: 'Короткие нарды',
  tagline: 'Выбиваешь шашки соперника и спешишь домой',
  icon: Icons.casino_rounded,
  accent: peach,
  rules: backgammonRules,
  settings: backgammonSettings,
  // Кнопка «Играть» на карточке и сетевое лобби ведут сюда. Когда друг уже
  // подключился, [network] заполнен и партия сразу открывается по сети.
  start: (context, settings, {network}) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => BackgammonEntryPage(
          settings: settings,
          network: network,
          variant: BackgammonVariant.short,
        ),
      ),
    );
  },
  options: backgammonOptions,
  parseOptions: backgammonParseOptions,
  validateMove: backgammonValidateMove,
  // Хост играет белыми и ходит первым. Просто и предсказуемо для ребёнка.
  hostSide: (_) => 'white',
);
