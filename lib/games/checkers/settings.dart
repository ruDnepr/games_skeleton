import 'package:flutter/material.dart';

import '../definition.dart';

/// Переключатели шашек. Каждый хранится под ключом `game.<id>.<key>` и не
/// пересекается с другими играми.
///
/// * `hints` — подсветка возможных ходов и ходов шашками, которыми вообще
///   можно пойти;
/// * `hintButton` — отдельная кнопка «Подсказать ход», вызывающая ИИ.
const checkersSettings = [
  GameSetting(
    key: 'hints',
    title: 'Подсказки',
    subtitle: 'Подсвечивать возможные ходы и шашки, которыми можно ходить',
    icon: Icons.lightbulb_rounded,
    defaultValue: true,
  ),
  GameSetting(
    key: 'hintButton',
    title: 'Кнопка «Подсказка»',
    subtitle: 'Показывать кнопку, которая подскажет хороший ход',
    icon: Icons.tips_and_updates_rounded,
    defaultValue: true,
  ),
];
