/// История партии для отмены хода.
///
/// В офлайн-режимах (против компьютера и вдвоём на одном устройстве) отмена
/// всегда доступна и возвращается на начало прошлого хода. В сетевой игре
/// отмена идёт по согласию: одна сторона спрашивает, вторая подтверждает — и
/// тогда оба откатываются к снимку. Поэтому снимок — это полное состояние, а
/// не патч.
library;

import 'model.dart';

/// Запись одного выстрела в истории партии.
///
/// Хранит кто стрелял, куда и что вышло. Нужна для отмены хода: контроллер
/// восстанавливает состояние, выталкивая записи из стека.
class ShotRecord {
  const ShotRecord({
    required this.shooter,
    required this.shot,
    required this.sunkBefore,
    required this.allSunkBefore,
  });

  /// Кто стрелял.
  final Side shooter;

  /// Сам выстрел с результатом.
  final Shot shot;

  /// Был ли потоплен корабль этим выстрелом.
  bool get didSink => shot.result == ShotResult.sunk;

  /// Сколько кораблей противника было потоплено ДО этого выстрела.
  final int sunkBefore;

  /// Был ли весь флот потоплен ДО этого выстрела.
  final bool allSunkBefore;

  @override
  String toString() =>
      '${shooter.russianLabel} → ${shot.square}: ${shot.result.russianLabel}';
}

/// Стек выстрелов партии с возможностью отмены.
class ShotHistory {
  final List<ShotRecord> _records = [];

  List<ShotRecord> get records => List.unmodifiable(_records);

  bool get isEmpty => _records.isEmpty;
  int get length => _records.length;

  void push(ShotRecord record) => _records.add(record);

  ShotRecord pop() => _records.removeLast();

  ShotRecord? get last => _records.isEmpty ? null : _records.last;

  /// Очистка перед новой партией.
  void clear() => _records.clear();

  /// Все выстрелы одного игрока в порядке выполнения.
  List<ShotRecord> byShooter(Side side) =>
      _records.where((r) => r.shooter == side).toList();
}

/// Снимок состояния поля, необходимый для отмены одного выстрела.
///
/// Отмена восстанавливает и выстрелы по моему полю, и мои выстрелы по полю
/// соперника, и чей был ход — иначе партия «поедет».
class BoardSnapshot {
  const BoardSnapshot({
    required this.turn,
    required this.myIncoming,
    required this.myShots,
  });

  final Side turn;

  /// Выстрелы соперника по моему полю: клетка → результат.
  final Map<Square, ShotResult> myIncoming;

  /// Мои выстрелы по полю соперника: клетка → выстрел с результатом.
  final Map<Square, Shot> myShots;
}
