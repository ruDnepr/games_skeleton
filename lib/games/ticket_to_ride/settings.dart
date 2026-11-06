import 'package:flutter/material.dart';

import '../definition.dart';

/// Переключатели «Билета на поезд». Каждый хранится под ключом
/// `game.ticket_to_ride.<key>` и не пересекается с другими играми.
///
/// `hints` — главная настройка из ТЗ: подсветка доступных маршрутов и
/// подсказка, какой маршрут занять. Этого хватает для детского варианта —
/// остальные правила партии остаются простыми.
const ticketToRideSettings = [
  GameSetting(
    key: 'hints',
    title: 'Подсказки',
    subtitle: 'Подсвечивать доступные маршруты на карте',
    icon: Icons.lightbulb_rounded,
    defaultValue: true,
  ),
];
