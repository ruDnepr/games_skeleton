import 'package:flutter/material.dart';

/// Названия цветов машин в винительном падеже: «сдвинь жёлтую машину».
///
/// В кампании у каждой машины свой цвет, поэтому подсказка называет машину
/// цветом, а не номером. Значения цветов совпадают с COLORS в
/// `tool/generate_levels.py`.
///
/// Карта не `const`: ключ `Color` переопределяет `==`, а const-карта такого
/// не разрешает.
final Map<Color, String> _carColorNames = <Color, String>{
  const Color(0xFFFF4B4B): 'красную',
  const Color(0xFF8266D5): 'фиолетовую',
  const Color(0xFFFFD66D): 'жёлтую',
  const Color(0xFF8ED1B0): 'зелёную',
  const Color(0xFF7FC8E8): 'голубую',
  const Color(0xFFFFB27F): 'оранжевую',
  const Color(0xFFC7B8F0): 'сиреневую',
  const Color(0xFFF3A6C8): 'розовую',
  const Color(0xFF9FB8F0): 'васильковую',
  const Color(0xFFFFE0A3): 'песочную',
  const Color(0xFFB7E4C7): 'мятную',
  const Color(0xFF7FD1C1): 'бирюзовую',
  const Color(0xFFCFCFDA): 'серебристую',
};

/// «жёлтую машину», «красную машину»; для незнакомого цвета — «машину».
String carColorAccusative(Color color) {
  final name = _carColorNames[color];
  return name == null ? 'машину' : '$name машину';
}

/// Сложность уровня по минимальному числу ходов.
String levelDifficulty(int minMoves) {
  if (minMoves <= 7) return 'Легко';
  if (minMoves <= 12) return 'Средне';
  if (minMoves <= 19) return 'Сложно';
  return 'Хардкор';
}
