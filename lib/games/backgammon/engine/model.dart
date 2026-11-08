/// Модели коротких нард: доска, шашки, кости, ход, партия.
///
/// Представление доски — классическое: 24 пункта, каждый — знаковое число.
/// Положительное число — белые шашки, отрицательное — чёрные, ноль — пусто.
/// Белые идут от 23 к 0 (убывание) и выносят из дома 0..5; чёрные — от 0 к 23
/// (возрастание) и выносят из дома 18..23. Так направления и дома симметричны,
/// а правила записываются коротко и одинаково для обоих цветов.
library;

/// Вариант нард. У коротких и длинных нард одна и та же доска и ход шашек,
/// но разная стартовая расстановка и правило постановки на чужой пункт:
/// короткие — можно выбивать одиночную чужую шашку, длинные — чужой пункт
/// (даже с одной шашкой) блокирует ход, выбивания нет.
enum BackgammonVariant { short, long }

/// Сторона игрока. Белые начинают с дальней стороны и идут к пункту 0,
/// чёрные — к пункту 23.
enum Player { white, black }

extension PlayerX on Player {
  /// Соперник.
  Player get other => this == Player.white ? Player.black : Player.white;

  /// Направление движения по индексам пунктов: белые −1, чёрные +1.
  int get direction => this == Player.white ? -1 : 1;

  /// Дом, из которого выносятся шашки: белые 0..5, чёрные 18..23.
  List<int> get homePoints =>
      this == Player.white
          ? const [0, 1, 2, 3, 4, 5]
          : const [18, 19, 20, 21, 22, 23];
}

/// Доска: 24 пункта, бары и «вынесенные» обоих игроков.
///
/// Класс иммутабельный — каждое правило возвращает новую доску. Так историю
/// для отмены хода можно хранить просто как список прошлых состояний, а сеть
/// проверяет ход повторным применением правил к своему состоянию.
class Board {
  const Board({
    required this.points,
    this.whiteBar = 0,
    this.blackBar = 0,
    this.whiteOff = 0,
    this.blackOff = 0,
  }) : assert(points.length == 24);

  /// 24 пункта. `points[i] > 0` — белые, `< 0` — чёрные.
  final List<int> points;

  final int whiteBar;
  final int blackBar;
  final int whiteOff;
  final int blackOff;

  /// Сколько шашек цвета [player] на пункте [point]. 0 для пустого или чужого.
  int at(int point, Player player) {
    final value = points[point];
    if (player == Player.white) return value > 0 ? value : 0;
    return value < 0 ? -value : 0;
  }

  /// Чужие шашки на пункте (для проверки блока и выбивания).
  int opponentAt(int point, Player player) => at(point, player.other);

  /// Сколько шашек цвета на баре.
  int bar(Player player) =>
      player == Player.white ? whiteBar : blackBar;

  /// Сколько шашек цвета уже вынесено.
  int off(Player player) =>
      player == Player.white ? whiteOff : blackOff;

  /// Всего шашек цвета на доске (пункты + бар). Должно быть 15 минус вынесенные.
  int onBoard(Player player) {
    var sum = bar(player);
    for (var i = 0; i < 24; i++) {
      sum += at(i, player);
    }
    return sum;
  }

  /// Есть ли шашка на баре — её надо вводить первой.
  bool hasBar(Player player) => bar(player) > 0;

  /// Копия доски.
  Board copy() => Board(
    points: List<int>.of(points),
    whiteBar: whiteBar,
    blackBar: blackBar,
    whiteOff: whiteOff,
    blackOff: blackOff,
  );

  /// Стартовая расстановка. У коротких нард — классическая расстановка по
  /// пунктам 24/13/8/6. У длинных — все 15 шашек цвета на «голове»: белые на
  /// 24-м пункте (23), чёрные на 1-м (0). Оба цвета идут навстречу друг другу
  /// к своим домам, как в коротких.
  factory Board.initial({
    BackgammonVariant variant = BackgammonVariant.short,
  }) {
    final points = List<int>.filled(24, 0);
    if (variant == BackgammonVariant.long) {
      // Все 15 шашек на голове.
      points[23] = 15; // белые на 24-м
      points[0] = -15; // чёрные на 1-м
      return Board(points: points);
    }
    // Короткие: 24-й пункт (23), 13-й (12), 8-й (7), 6-й (5).
    points[23] = 2;
    points[12] = 5;
    points[7] = 3;
    points[5] = 5;
    // Чёрные зеркально: 24-й пункт (0), 13-й (11), 8-й (16), 6-й (18).
    points[0] = -2;
    points[11] = -5;
    points[16] = -3;
    points[18] = -5;
    return Board(points: points);
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Board &&
          _listEquals(points, other.points) &&
          whiteBar == other.whiteBar &&
          blackBar == other.blackBar &&
          whiteOff == other.whiteOff &&
          blackOff == other.blackOff;

  @override
  int get hashCode => Object.hash(
    Object.hashAll(points),
    whiteBar,
    blackBar,
    whiteOff,
    blackOff,
  );

  static bool _listEquals(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

/// Один шаг шашки одной костью. Ход за партию — это последовательность таких
/// шагов (1–4), потому что дубль даёт четыре движения, а две разные кости — два.
///
/// [from] равен `null`, когда шашка вводится с бара. [to] равен `null`, когда
/// шашка выносится с доски. Так код правил читается без магических чисел.
class Move {
  const Move({
    required this.player,
    required this.die,
    required this.from,
    required this.to,
  });

  final Player player;

  /// Значение кости (1..6), которой сделан этот шаг.
  final int die;

  /// Пункт отправления (0..23) или `null` для хода с бара.
  final int? from;

  /// Пункт назначения (0..23) или `null` для выноса с доски.
  final int? to;

  /// Ввод с бара.
  bool get fromBar => from == null;

  /// Вынос шашки.
  bool get bearOff => to == null;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Move &&
          player == other.player &&
          die == other.die &&
          from == other.from &&
          to == other.to;

  @override
  int get hashCode => Object.hash(player, die, from, to);

  @override
  String toString() {
    final f = fromBar ? 'бар' : 'п.${from! + 1}';
    final t = bearOff ? 'вынос' : 'п.${to! + 1}';
    return '$f→$t (${player.name}, кость $die)';
  }

  Map<String, Object?> toJson() => {
    'player': player.name,
    'die': die,
    'from': from,
    'to': to,
  };

  static Move fromJson(Map<String, Object?> json) {
    final player = _parsePlayer(json['player']);
    final die = json['die'];
    final from = json['from'];
    final to = json['to'];
    if (die is! int || die < 1 || die > 6) {
      throw const FormatException('Ход не распознан: кость');
    }
    if (from != null && (from is! int || from < 0 || from > 23)) {
      throw const FormatException('Ход не распознан: откуда');
    }
    if (to != null && (to is! int || to < 0 || to > 23)) {
      throw const FormatException('Ход не распознан: куда');
    }
    return Move(player: player, die: die, from: from as int?, to: to as int?);
  }
}

/// Сыгранный ход одной стороной: кости и сделанные шаги.
class Turn {
  const Turn({required this.player, required this.dice, required this.moves});

  final Player player;

  /// Брошенные кости: две разные [a, b] или четыре одинаковые [a, a, a, a].
  final List<int> dice;

  /// Шаги, реально сделанные за этот ход (0..dice.length).
  final List<Move> moves;

  Map<String, Object?> toJson() => {
    'player': player.name,
    'dice': List<int>.of(dice),
    'moves': moves.map((m) => m.toJson()).toList(),
  };
}

/// Состояние партии в один момент: доска, чей ход, оставшиеся кости и победитель.
class GameState {
  const GameState({
    required this.board,
    required this.turn,
    this.rolled = const [],
    this.available = const [],
    this.winner,
    this.variant = BackgammonVariant.short,
  });

  final Board board;

  /// Чей сейчас ход.
  final Player turn;

  /// Брошенные кости текущего хода — для показа. Не меняются по мере ходов.
  final List<int> rolled;

  /// Кости, которыми ещё можно ходить в этот ход. Убывает по мере шагов.
  final List<int> available;

  /// Победитель, если партия закончилась.
  final Player? winner;

  /// Вариант нард — определяет правило постановки на чужой пункт.
  final BackgammonVariant variant;

  bool get isOver => winner != null;

  GameState copyWith({
    Board? board,
    Player? turn,
    List<int>? rolled,
    List<int>? available,
    Player? winner,
  }) => GameState(
    board: board ?? this.board,
    turn: turn ?? this.turn,
    rolled: rolled ?? this.rolled,
    available: available ?? this.available,
    winner: winner ?? this.winner,
    variant: variant,
  );

  GameState withTurn(Player next) =>
      copyWith(turn: next, rolled: const [], available: const []);

  /// Применяет бросок: `rolled` — две кости [a, b] (для показа и сети),
  /// `available` — развёрнутый список: 4 для дубля, 2 иначе. Без расширения
  /// дубль давал бы только 2 хода вместо 4 — это источник истины для
  /// `isLegal`/`applyMove`, поэтому расширение происходит здесь, в одном месте.
  GameState withRoll(List<int> dice) => copyWith(
    rolled: List<int>.of(dice),
    available: List<int>.of(expandDice(dice)),
  );
}

/// Сколько ходов даёт бросок. Дубль — четыре движения одной костью, две
/// разные кости — два. Чистая функция в модели, чтобы `withRoll` расширял
/// сам, не завися от правил.
List<int> expandDice(List<int> rolled) {
  if (rolled.length != 2) {
    return List<int>.of(rolled);
  }
  final a = rolled[0];
  final b = rolled[1];
  if (a == b) return [a, a, a, a];
  return [a, b];
}

Player _parsePlayer(Object? value) {
  if (value == 'white') return Player.white;
  if (value == 'black') return Player.black;
  throw const FormatException('Ход не распознан: цвет');
}
