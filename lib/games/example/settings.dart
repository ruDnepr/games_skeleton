import 'package:flutter/material.dart';

import '../definition.dart';

/// Switches that belong to the example game.
///
/// They do nothing yet: the point is to show how a game declares its own
/// settings. The shared settings screen renders them with the same row as the
/// sound switch, and each value is stored under `game.example.<key>`.
const exampleSettings = [
  GameSetting(
    key: 'reminder',
    title: 'Напоминание',
    subtitle: 'Пример переключателя этой игры',
    icon: Icons.notifications_rounded,
    defaultValue: true,
  ),
  GameSetting(
    key: 'markers',
    title: 'Метки на поле',
    subtitle: 'Ещё один переключатель игры',
    icon: Icons.flag_rounded,
    defaultValue: false,
  ),
];
