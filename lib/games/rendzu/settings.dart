import 'package:flutter/material.dart';

import '../definition.dart';

/// Переключатели рэндзю. Каждый хранится под ключом `game.rendzu.<key>` и не
/// пересекается с другими играми.
///
/// `hints` — показывать кнопкой «Подсказка» хороший ход и предупреждать о
/// запрещённых ходах в рэндзю. `patternHighlight` — подсветка троек и четвёрок
/// на доске, чтобы видеть свои и чужие угрозы. Набор правил (гомоку/рэндзю),
/// размер доски (9/15) и уровень сложности — выбор перед партией, не настройки.
const rendzuSettings = [
  GameSetting(
    key: 'hints',
    title: 'Подсказки',
    subtitle: 'Кнопка «Подсказать ход» и предупреждения о запрещённых ходах',
    icon: Icons.lightbulb_rounded,
    defaultValue: true,
  ),
  GameSetting(
    key: 'patternHighlight',
    title: 'Подсветка троек и четвёрок',
    subtitle: 'Показывать свои и чужие угрозы прямо на доске',
    icon: Icons.grid_on_rounded,
    defaultValue: true,
  ),
];
