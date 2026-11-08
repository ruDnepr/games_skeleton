/// Модели шашек: доска, шашки, ход, партия.
///
/// Файл чистый Dart — без Flutter, — поэтому движок можно тестировать без
/// платформы и переиспользовать в любом интерфейсе. Структура повторяет
/// `domain/models.dart` оригинальной игры «Шашки для Дианы»: доска — 8×8 или
/// 10×10, шашки стоят на тёмных клетках, где `(row + col)` нечётно. Строка 0 —
/// верхний край, куда идут белые; чёрные начинают сверху, белые — снизу.
library;

import 'dart:collection';

/// Вариант шашек. Отличается размером доски, числом рядов, поведением дамки и
/// целью: например, в поддавках выигрывает тот, кто отдал все шашки.
enum GameVariant { russian, american, international, giveaway }

/// Сторона игрока. Белые идут вверх (к ряду 0), чёрные — вниз (к последнему
/// ряду). Так направления симметричны, а правила пишутся коротко для обоих
/// цветов.
enum Side { white, black }

extension SideDetails on Side {
  /// Соперник.
  Side get opponent => this == Side.white ? Side.black : Side.white;

  /// Направление хода простой шашки: белые вверх (−1), чёрные вниз (+1).
  int get forward => this == Side.white ? -1 : 1;

  /// Подпись для интерфейса.
  String get label => this == Side.white ? 'Белые' : 'Чёрные';
}

extension VariantDetails on GameVariant {
  /// Название для экрана выбора режима.
  String get label => switch (this) {
    GameVariant.russian => 'Русские шашки',
    GameVariant.american => 'Классические шашки',
    GameVariant.international => 'Международные шашки',
    GameVariant.giveaway => 'Поддавки',
  };

  /// Размер доски: 8 для большинства вариантов, 10 для международных.
  int get boardSize => this == GameVariant.international ? 10 : 8;

  /// Число рядов шашек каждого цвета на старте.
  int get initialRows => this == GameVariant.international ? 4 : 3;

  /// Дамка «летает» через всю диагональ — русские, международные, поддавки.
  /// В классических (американских) шашках дамка ходит на одну клетку.
  bool get flyingKings => this != GameVariant.american;

  /// Простая шашка может бить назад — все варианты, кроме классических.
  bool get backwardsCapture => this != GameVariant.american;

  /// Обязательный захват максимального числа шашек — только международные.
  bool get maximumCapture => this == GameVariant.international;

  /// Цель — отдать свои шашки (реверсивная) — только поддавки.
  bool get reverseGoal => this == GameVariant.giveaway;

  /// Кто ходит первым. В классических шашках — чёрные, в остальных — белые.
  Side get firstSide =>
      this == GameVariant.american ? Side.black : Side.white;
}

/// Клетка на доске. Равенство по координатам, поэтому годится как ключ мапы.
class Square {
  const Square(this.row, this.col);

  final int row;
  final int col;

  /// Лежит ли клетка на доске размера [size].
  bool inside(int size) => row >= 0 && col >= 0 && row < size && col < size;

  /// Сетевой формат: пара чисел `[row, col]`.
  List<int> toJson() => [row, col];

  /// Обратный разбор — с проверкой, что пара лежит на доске до 10×10.
  factory Square.fromJson(Object? value) {
    if (value is! List ||
        value.length != 2 ||
        value[0] is! int ||
        value[1] is! int) {
      throw const FormatException('Некорректная клетка');
    }
    final square = Square(value[0] as int, value[1] as int);
    if (!square.inside(10)) throw const FormatException('Клетка вне доски');
    return square;
  }

  @override
  bool operator ==(Object other) =>
      other is Square && row == other.row && col == other.col;
  @override
  int get hashCode => Object.hash(row, col);
  @override
  String toString() => '${String.fromCharCode(97 + col)}${row + 1}';
}

/// Шашка: цвет и флаг дамки. Незменяемая — превращение в дамку возвращает новую.
class Piece {
  const Piece(this.side, {this.king = false});

  final Side side;
  final bool king;

  /// Превращение в дамку. Если уже дамка — возвращает себя.
  Piece crown() => king ? this : Piece(side, king: true);

  @override
  bool operator ==(Object other) =>
      other is Piece && side == other.side && king == other.king;
  @override
  int get hashCode => Object.hash(side, king);
}

/// Один *полный* ход: стартовая клетка, серия приземлений и серия взятых шашек.
///
/// Каждый приземляющий ход соответствует одной взятой шашке в серии взятий;
/// для тихого хода `landings` — ровно одна клетка, `captures` — пусто.
class Move {
  Move({
    required this.from,
    required List<Square> landings,
    List<Square> captures = const [],
  }) : landings = List.unmodifiable(landings),
       captures = List.unmodifiable(captures) {
    if (landings.isEmpty ||
        landings.length > 20 ||
        (captures.isNotEmpty && captures.length != landings.length)) {
      throw ArgumentError('Некорректная последовательность хода');
    }
  }

  final Square from;
  final List<Square> landings;
  final List<Square> captures;

  /// Финальная клетка хода.
  Square get to => landings.last;

  /// Является ли ход взятием.
  bool get isCapture => captures.isNotEmpty;

  /// Сетевой формат: `{from, path, captures}`. `path` — серия приземлений,
  /// `captures` — пустой список для тихого хода и той же длины, что и `path`,
  /// для взятия.
  Map<String, Object> toJson() => {
    'from': from.toJson(),
    'path': landings.map((p) => p.toJson()).toList(),
    'captures': captures.map((p) => p.toJson()).toList(),
  };

  /// Обратный разбор — с проверкой формы.
  factory Move.fromJson(Object? value) {
    if (value is! Map || value['path'] is! List || value['captures'] is! List) {
      throw const FormatException('Некорректный ход');
    }
    final path = (value['path'] as List).map(Square.fromJson).toList();
    final captures =
        (value['captures'] as List).map(Square.fromJson).toList();
    if (path.isEmpty ||
        path.length > 20 ||
        (captures.isNotEmpty && captures.length != path.length)) {
      throw const FormatException('Некорректная последовательность хода');
    }
    return Move(
      from: Square.fromJson(value['from']),
      landings: path,
      captures: captures,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is Move &&
      from == other.from &&
      _sameList(landings, other.landings) &&
      _sameList(captures, other.captures);
  @override
  int get hashCode =>
      Object.hash(from, Object.hashAll(landings), Object.hashAll(captures));
  @override
  String toString() =>
      '$from${isCapture ? ' × ' : ' – '}${landings.join(' – ')}';
}

bool _sameList<T>(List<T> a, List<T> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// Доска: размер и набор шашек на тёмных клетках. Незменяемая.
class Board {
  Board(this.size, Map<Square, Piece> pieces)
    : pieces = UnmodifiableMapView(Map.of(pieces)) {
    if (size != 8 && size != 10) throw ArgumentError.value(size, 'size');
    if (pieces.keys.any((p) => !p.inside(size) || (p.row + p.col).isEven)) {
      throw ArgumentError('Шашки должны стоять на тёмных клетках доски');
    }
  }

  /// Стартовая расстановка для варианта: чёрные сверху, белые снизу.
  factory Board.initial(GameVariant variant) {
    final size = variant.boardSize;
    final result = <Square, Piece>{};
    for (var row = 0; row < size; row++) {
      for (var col = 0; col < size; col++) {
        if ((row + col).isEven) continue;
        if (row < variant.initialRows) {
          result[Square(row, col)] = const Piece(Side.black);
        }
        if (row >= size - variant.initialRows) {
          result[Square(row, col)] = const Piece(Side.white);
        }
      }
    }
    return Board(size, result);
  }

  final int size;
  final Map<Square, Piece> pieces;

  /// Шашка на клетке или `null`, если клетка пустая.
  Piece? at(Square square) => pieces[square];

  /// Сколько шашек цвета на доске.
  int count(Side side) =>
      pieces.values.where((piece) => piece.side == side).length;
}

/// Правила ничьей, общие для всех вариантов: одна и та же позиция с правом хода
/// видимая [drawRepetitions] раз, либо [drawQuietPlies] тихих ходов подряд — 15
/// на каждого без взятия и без хода простой шашки. Если на доске остались
/// только дамки, порог растёт до [drawQuietPliesKings] (30 на каждого): дамочные
/// окончания могут тянуться долго.
const drawRepetitions = 3;
const drawQuietPlies = 30;
const drawQuietPliesKings = 60;

/// Состояние партии: вариант, доска, чей ход, номер полухода и счётчик тихих
/// полуходов для правила ничьей. Незменяемое.
class GameState {
  const GameState({
    required this.variant,
    required this.board,
    required this.turn,
    this.ply = 0,
    this.quietPlies = 0,
  });

  /// Стартовое состояние для варианта.
  factory GameState.initial(GameVariant variant) =>
      GameState(variant: variant, board: Board.initial(variant), turn: variant.firstSide);

  final GameVariant variant;
  final Board board;
  final Side turn;
  final int ply;

  /// Полуходов подряд без взятия и без хода простой шашки. Для правила ничьей.
  final int quietPlies;

  /// Доска и сторона хода, без счётчика: две позиции, различающиеся только
  /// `ply`, для правила повторения одинаковые.
  String get positionKey => _positionHash(includePly: false);

  /// Стабильный отпечаток для протокола, не зависящий от порядка обхода мапы.
  String get fingerprint => _positionHash(includePly: true);

  String _positionHash({required bool includePly}) {
    var hash = 0x811c9dc5;
    void mix(int n) {
      hash = ((hash ^ n) * 0x01000193) & 0xffffffff;
    }

    mix(variant.index);
    mix(turn.index);
    if (includePly) mix(ply);
    for (var row = 0; row < board.size; row++) {
      for (var col = 0; col < board.size; col++) {
        final piece = board.at(Square(row, col));
        mix(
          piece == null
              ? 0
              : 1 + piece.side.index * 2 + (piece.king ? 1 : 0),
        );
      }
    }
    return hash.toRadixString(16).padLeft(8, '0');
  }
}
