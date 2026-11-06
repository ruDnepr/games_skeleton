import 'package:flutter/material.dart';

import '../backgammon/engine/model.dart';
import '../backgammon/session_page.dart';
import '../backgammon/settings.dart' show backgammonSettings;
import '../definition.dart';
import 'network.dart';
import 'rules.dart';

/// Игра «Длинные нарды» в каталоге. Делит с короткими нардами движок, экран
/// партии, настройки и звук — отличается стартовой расстановкой (все шашки на
/// «голове»), правилом «без выбивания» и набором карточек правил.
final longBackgammonGame = GameDefinition(
  id: longBackgammonGameId,
  title: 'Длинные нарды',
  tagline: 'Гонка без выбивания: строй блоки и спеши домой',
  icon: Icons.donut_large_rounded,
  accent: const Color(0xFFC9B6E8),
  rules: longBackgammonRules,
  settings: backgammonSettings,
  start: (context, settings, {network}) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => BackgammonEntryPage(
          settings: settings,
          network: network,
          variant: BackgammonVariant.long,
        ),
      ),
    );
  },
  options: longBackgammonOptions,
  parseOptions: longBackgammonParseOptions,
  validateMove: longBackgammonValidateMove,
  hostSide: (_) => 'white',
);
