import 'package:flutter/material.dart';

import '../definition.dart';

/// Переключатели лото. Каждый хранится под ключом `game.<id>.<key>` и не
/// пересекается с другими играми.
///
/// `hints` — подсвечивать клетку, на которую пришёл бочонок: ребёнок видит,
/// где искать вытянутое число. `hintButton` — большая кнопка «Подсказка»,
/// показывает все числа, которые уже можно закрыть. `voice` — голос ведущего
/// через TTS: полезно, когда ребёнок не смотрит на экран.
const lotoSettings = [
  GameSetting(
    key: 'hints',
    title: 'Подсказывать числа',
    subtitle: 'Подсвечивать клетку, на которую пришёл бочонок',
    icon: Icons.lightbulb_rounded,
    defaultValue: true,
  ),
  GameSetting(
    key: 'hintButton',
    title: 'Кнопка «Подсказка»',
    subtitle: 'Показывать все числа, которые можно закрыть',
    icon: Icons.tips_and_updates_rounded,
    defaultValue: true,
  ),
  GameSetting(
    key: 'voice',
    title: 'Проговаривать числа',
    subtitle: 'Ведущий называет вытянутое число голосом',
    icon: Icons.record_voice_over_rounded,
    defaultValue: true,
  ),
];
