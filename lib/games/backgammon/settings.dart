import 'package:flutter/material.dart';

import '../definition.dart';

/// Переключатели нард. Каждый хранится под ключом `game.<id>.<key>` и не
/// пересекается с другими играми. Список общий для коротких и длинных нард —
/// настройки те же.
///
/// `hints` — главная настройка из ТЗ: подсветка возможных ходов и кнопка
/// «Подсказать ход». `numbers` — номера пунктов на доске. `autoRoll` — кости
/// бросаются сами в начале хода, ребёнку на одну кнопку меньше.
const backgammonSettings = [
  GameSetting(
    key: 'hints',
    title: 'Подсказки',
    subtitle: 'Подсвечивать возможные ходы и показывать кнопку-подсказку',
    icon: Icons.lightbulb_rounded,
    defaultValue: true,
  ),
  GameSetting(
    key: 'numbers',
    title: 'Номера пунктов',
    subtitle: 'Подписать пункты числами — легче считать шаги',
    icon: Icons.format_list_numbered_rounded,
    defaultValue: false,
  ),
  GameSetting(
    key: 'autoRoll',
    title: 'Авто-бросок костей',
    subtitle: 'Кости бросаются сами в начале хода',
    icon: Icons.auto_mode_rounded,
    defaultValue: false,
  ),
];
