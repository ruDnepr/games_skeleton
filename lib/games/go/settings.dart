import 'package:flutter/material.dart';

import '../definition.dart';

/// Переключатели го. Каждый хранится под ключом `game.<id>.<key>` и не
/// пересекается с другими играми.
///
/// * `hints` — подсветка возможных ходов, групп в атари и запрещённой точки ко;
/// * `hintButton` — отдельная кнопка «Подсказать ход», вызывающая ИИ.
///
/// Размер доски и режим партии — выбор на экране перед началом, а не
/// переключатели: их неудобно «включать-выключать».
const goSettings = [
  GameSetting(
    key: 'hints',
    title: 'Подсказки',
    subtitle: 'Подсвечивать ходы, группы в атари и запрещённую точку ко',
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
