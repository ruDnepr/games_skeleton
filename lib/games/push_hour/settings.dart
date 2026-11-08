import 'package:flutter/material.dart';

import '../definition.dart';

/// Переключатели «Push Hour». Каждый хранится под ключом
/// `game.push_hour.<key>` и не пересекается с другими играми.
///
/// `hints` — главная настройка: показывать подсказку по кнопке-лампочке.
/// `numbers` — подписывать номера уровней на сетке выбора.
const pushHourSettings = [
  GameSetting(
    key: 'hints',
    title: 'Подсказки',
    subtitle: 'Показывать следующий ход по кнопке-лампочке',
    icon: Icons.lightbulb_rounded,
    defaultValue: true,
  ),
  GameSetting(
    key: 'numbers',
    title: 'Номера уровней',
    subtitle: 'Подписывать уровни числами на сетке',
    icon: Icons.format_list_numbered_rounded,
    defaultValue: true,
  ),
];
