import 'package:flutter/material.dart';

import '../../presentation/theme.dart';
import '../definition.dart';
import 'network.dart';
import 'rules.dart';
import 'settings.dart';
import 'session_page.dart';

/// The only game in the catalogue so far.
///
/// It is a template, not a game: its rules explain the frame, its switches are
/// examples, and its session screen says that the game itself is still to come.
/// Adding a real game means copying this folder and replacing the four files —
/// the menu, the game list, the rules screen, the settings screen and the
/// network lobby need no changes at all.
final exampleGame = GameDefinition(
  id: exampleGameId,
  title: 'Игра-пример',
  tagline: 'Заготовка: сюда встанет твоя игра',
  icon: Icons.extension_rounded,
  accent: yellow,
  rules: exampleRules,
  settings: exampleSettings,
  // The card's «Играть» leads here; the network lobby leads here too, with
  // `network` filled after a friend connects.
  start: (context, settings, {network}) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ExampleSessionPage(network: network),
      ),
    );
  },
  options: exampleOptions,
  parseOptions: exampleParseOptions,
  validateMove: exampleValidateMove,
  // The example has no sides, only places: the host keeps the one called
  // «host». A game with colours or turns returns its own label here.
  hostSide: (_) => 'host',
);
