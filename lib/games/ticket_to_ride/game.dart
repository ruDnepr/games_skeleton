import 'package:flutter/material.dart';

import '../../presentation/theme.dart';
import '../definition.dart';
import 'network.dart';
import 'rules.dart';
import 'settings.dart';
import 'session_page.dart';

/// Игра «Билет на поезд» в каталоге. Карточка, правила, настройки и точка входа
/// в партию — всё здесь; главное окно, список игр, лобби и звук общие.
final ticketToRideGame = GameDefinition(
  id: ticketToRideGameId,
  title: 'Билет на поезд',
  tagline: 'Прокладывай маршруты и соединяй города',
  icon: Icons.train_rounded,
  accent: peach,
  rules: ticketToRideRules,
  settings: ticketToRideSettings,
  // Кнопка «Играть» на карточке и сетевое лобби ведут сюда. Когда друг уже
  // подключился, [network] заполнен и партия сразу открывается по сети.
  start: (context, settings, {network}) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => TicketToRideEntryPage(
          settings: settings,
          network: network,
        ),
      ),
    );
  },
  options: ticketToRideOptions,
  parseOptions: ticketToRideParseOptions,
  validateMove: ticketToRideValidateMove,
  // Хост ходит первым — так же, как белые в нардах. Просто и предсказуемо.
  hostSide: (_) => 'me',
);
