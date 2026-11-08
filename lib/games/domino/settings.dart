import 'package:flutter/material.dart';

import '../definition.dart';

/// Переключатели домино. Каждый хранится под ключом `game.<id>.<key>` и не
/// пересекается с другими играми.
///
/// `hints` — главная настройка: подсветка костей, которые подходят к столу.
/// `hintButton` — волшебная кнопка с советом, какую кость лучше поставить.
const dominoSettings = [
  GameSetting(
    key: 'hints',
    title: 'Подсказки',
    subtitle: 'Подсвечивать кости, которые подходят к столу',
    icon: Icons.lightbulb_rounded,
    defaultValue: true,
  ),
  GameSetting(
    key: 'hintButton',
    title: 'Кнопка «Подсказка»',
    subtitle: 'Показывать волшебную кнопку с советом',
    icon: Icons.touch_app_rounded,
    defaultValue: true,
  ),
];
