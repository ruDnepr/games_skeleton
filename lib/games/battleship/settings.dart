import 'package:flutter/material.dart';

import '../definition.dart';

/// Переключатели морского боя. Каждый хранится под ключом
/// `game.<id>.<key>` и не пересекается с другими играми.
///
/// `hints` — главная настройка из ТЗ: подсветка необстрелянных клеток и
/// кнопка-подсказка «куда стрелять».
const battleshipSettings = [
  GameSetting(
    key: 'hints',
    title: 'Подсказки',
    subtitle: 'Подсветка ещё не обстрелянных клеток',
    icon: Icons.lightbulb_rounded,
    defaultValue: true,
  ),
];
