import 'dart:ui'
    show
        Canvas,
        Color,
        FontWeight,
        Offset,
        Paint,
        PaintingStyle,
        Path,
        Rect,
        Size,
        TextDirection;

import 'package:flame/components.dart';
import 'package:flame/events.dart';
import 'package:flame/game.dart';
import 'package:flutter/painting.dart'
    show Alignment, LinearGradient, RadialGradient, TextPainter, TextSpan, TextStyle;

import '../backgammon_controller.dart';
import '../engine/model.dart';
import 'board_geometry.dart';

// Палитра доски — тёплое дерево в духе общей темы приложения.
const _woodDark = Color(0xFF8C5831);
const _woodLight = Color(0xFFC28E54);
const _feltA = Color(0xFFE7B98C);
const _feltB = Color(0xFFD9A06B);
const _pointDark = Color(0xFF6E4A2C);
const _pointLight = Color(0xFFF2D9B0);
const _whiteChecker = Color(0xFFFBF1DD);
const _blackChecker = Color(0xFF3D3154);
const _highlight = Color(0xFF6047AF);
const _hint = Color(0xFFFFD66D);

/// Flame-игра: рисует доску, шашки и подсветку и ловит тапы по пунктам/бару/
/// выносу. Вся логика — в [BackgammonController], игра только отображает
/// состояние и сообщает контроллеру о тапах.
class BackgammonGame extends FlameGame {
  BackgammonGame(this.controller);

  final BackgammonController controller;

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    add(BoardComponent(controller: controller));
  }
}

class BoardComponent extends PositionComponent with TapCallbacks {
  BoardComponent({required this.controller});

  final BackgammonController controller;

  BoardGeometry? _geo;
  Board? _rendered;
  // Летающая шашка для анимации одиночного хода.
  _Flyer? _flyer;

  @override
  void onGameResize(Vector2 size) {
    super.onGameResize(size);
    this.size = size;
    position = Vector2.zero();
    _geo = BoardGeometry(Size(size.x, size.y));
  }

  @override
  bool containsLocalPoint(Vector2 point) => true;

  @override
  void onTapUp(TapUpEvent event) {
    final geo = _geo;
    if (geo == null) return;
    final pos = Offset(event.localPosition.x, event.localPosition.y);
    final target = geo.hitTest(pos);
    if (target.isPoint) {
      controller.selectPoint(target.point!);
    } else if (target.isBar) {
      controller.selectBar();
    } else if (target.isOff) {
      controller.selectOff();
    }
  }

  @override
  void update(double dt) {
    super.update(dt);
    final board = controller.state.board;
    if (_rendered != board) {
      _maybeStartFlight(_rendered, board);
      _rendered = board;
    }
    if (_flyer != null) {
      _flyer!.t += dt / 0.28; // ~280 мс на перелёт
      if (_flyer!.t >= 1) _flyer = null;
    }
  }

  void _maybeStartFlight(Board? old, Board now) {
    if (old == null || _geo == null) return;
    try {
      final diff = _singleMoveDiff(old, now);
      if (diff == null) return; // несколько изменений — без анимации
      final from = _slotCenter(now, diff.player, diff.from, isSource: true);
      final to = _slotCenter(now, diff.player, diff.to, isSource: false);
      _flyer = _Flyer(
        player: diff.player,
        from: from,
        to: to,
        t: 0,
        hideDestTop: diff.hideDestTop,
        dest: diff.to,
      );
    } catch (_) {
      // Любая неоднозначность — просто показываем новую позицию.
    }
  }

  /// Центр верхней шашки в слоте на доске [board]. Для источника — это верхушка
  /// старого стека (до ухода шашки), для адресата — верхушка нового (после
  /// прихода). Разница в один индекс: источник читает count, адресат count−1.
  Offset _slotCenter(Board board, Player player, _Slot slot,
      {required bool isSource}) {
    final geo = _geo!;
    switch (slot.kind) {
      case 'point':
        final count = board.at(slot.point!, player);
        final idx = isSource ? count : count - 1;
        return geo.checkerAt(slot.point!, idx < 0 ? 0 : idx);
      case 'bar':
        final count = board.bar(player);
        final idx = isSource ? count : count - 1;
        return geo.barCheckerAt(player == Player.white, idx < 0 ? 0 : idx);
      case 'off':
        return geo.offRect(player == Player.white).center;
      default:
        throw StateError('неизвестный слот: ${slot.kind}');
    }
  }

  /// Находит ровно одно перемещение шашки между [old] и [now]. Если изменений
  /// несколько (ход по сети применяется целиком) — возвращает null.
  _MoveDiff? _singleMoveDiff(Board old, Board now) {
    _Slot? src;
    _Slot? dst;
    Player? mover;
    for (var i = 0; i < 24; i++) {
      final ow = old.at(i, Player.white);
      final nw = now.at(i, Player.white);
      if (nw == ow - 1) {
        if (src != null) return null;
        src = _Slot.point(i);
        mover = Player.white;
      } else if (nw == ow + 1) {
        if (dst != null) return null;
        dst = _Slot.point(i);
        mover ??= Player.white;
      }
      final ob = old.at(i, Player.black);
      final nb = now.at(i, Player.black);
      if (nb == ob - 1) {
        if (src != null) return null;
        src = _Slot.point(i);
        mover = Player.black;
      } else if (nb == ob + 1) {
        if (dst != null) return null;
        dst = _Slot.point(i);
        mover ??= Player.black;
      }
    }
    // Бар и вынос.
    if (old.bar(Player.white) != now.bar(Player.white)) {
      if (old.bar(Player.white) == now.bar(Player.white) + 1) {
        if (src != null) return null;
        src = const _Slot.bar();
        mover = Player.white;
      } else if (old.bar(Player.white) + 1 == now.bar(Player.white)) {
        if (dst != null) return null;
        dst = const _Slot.bar();
        mover ??= Player.black; // выбитие — чёрная шашка на бар
      } else {
        return null;
      }
    }
    if (old.bar(Player.black) != now.bar(Player.black)) {
      if (old.bar(Player.black) == now.bar(Player.black) + 1) {
        if (src != null) return null;
        src = const _Slot.bar();
        mover = Player.black;
      } else if (old.bar(Player.black) + 1 == now.bar(Player.black)) {
        if (dst != null) return null;
        dst = const _Slot.bar();
        mover ??= Player.white;
      } else {
        return null;
      }
    }
    if (old.off(Player.white) != now.off(Player.white)) {
      if (old.off(Player.white) + 1 == now.off(Player.white)) {
        if (dst != null) return null;
        dst = const _Slot.off();
        mover ??= Player.white;
      } else {
        return null;
      }
    }
    if (old.off(Player.black) != now.off(Player.black)) {
      if (old.off(Player.black) + 1 == now.off(Player.black)) {
        if (dst != null) return null;
        dst = const _Slot.off();
        mover ??= Player.black;
      } else {
        return null;
      }
    }
    if (src == null || dst == null || mover == null) return null;
    return _MoveDiff(
      player: mover,
      from: src,
      to: dst,
      hideDestTop: dst.kind != 'off',
    );
  }

  @override
  void render(Canvas canvas) {
    final geo = _geo;
    if (geo == null) return;
    _drawFrame(canvas, geo);
    _drawPoints(canvas, geo);
    _drawBar(canvas, geo);
    _drawOffTrays(canvas, geo);
    _drawCheckers(canvas, geo);
    _drawHighlights(canvas, geo);
    _drawFlyer(canvas, geo);
  }

  void _drawFrame(Canvas canvas, BoardGeometry geo) {
    final frame = Paint()..color = _woodDark;
    canvas.drawRect(Offset.zero & geo.size, frame);
    final inner = Rect.fromLTRB(
      geo.frame,
      geo.frame,
      geo.size.width - geo.trayWidth,
      geo.size.height - geo.frame,
    );
    canvas.drawRect(inner, Paint()..color = _feltA);
    // Лёгкий градиент фетра.
    canvas.drawRect(
      inner,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [_feltA, _feltB],
        ).createShader(inner),
    );
  }

  void _drawPoints(Canvas canvas, BoardGeometry geo) {
    for (var i = 0; i < 24; i++) {
      final base = Offset(geo.pointCenterX(i), geo.baseY(i));
      final apex = Offset(geo.pointCenterX(i), geo.apexY(i));
      final path = Path()
        ..moveTo(base.dx - geo.pointWidth / 2, base.dy)
        ..lineTo(base.dx + geo.pointWidth / 2, base.dy)
        ..lineTo(apex.dx, apex.dy)
        ..close();
      canvas.drawPath(
        path,
        Paint()..color = i.isEven ? _pointLight : _pointDark,
      );
      if (controller.numbersEnabled) {
        final tp = TextPainter(
          text: TextSpan(
            text: '${i + 1}',
            style: const TextStyle(
              color: _woodDark,
              fontSize: 9,
              fontWeight: FontWeight.w800,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(
          canvas,
          Offset(base.dx - tp.width / 2, geo.isTop(i) ? base.dy + 2 : base.dy - tp.height - 2),
        );
      }
    }
  }

  void _drawBar(Canvas canvas, BoardGeometry geo) {
    final rect = Rect.fromLTWH(
      geo.barCenterX - geo.barWidth / 2,
      geo.frame,
      geo.barWidth,
      geo.size.height - 2 * geo.frame,
    );
    canvas.drawRect(rect, Paint()..color = _woodDark);
  }

  void _drawOffTrays(Canvas canvas, BoardGeometry geo) {
    for (final isWhite in [true, false]) {
      final rect = geo.offRect(isWhite);
      canvas.drawRect(rect, Paint()..color = _woodLight);
      final count = isWhite
          ? controller.state.board.whiteOff
          : controller.state.board.blackOff;
      if (count == 0) continue;
      final tp = TextPainter(
        text: TextSpan(
          text: '$count',
          style: const TextStyle(
            color: _woodDark,
            fontSize: 18,
            fontWeight: FontWeight.w900,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, rect.center - Offset(tp.width / 2, tp.height / 2));
    }
  }

  void _drawCheckers(Canvas canvas, BoardGeometry geo) {
    for (var i = 0; i < 24; i++) {
      for (final player in Player.values) {
        final count = controller.state.board.at(i, player);
        if (count == 0) continue;
        // Прячем верхнюю шашку адресата во время полёта.
        var visible = count;
        final f = _flyer;
        if (f != null &&
            f.player == player &&
            f.hideDestTop &&
            f.dest.kind == 'point' &&
            f.dest.point == i) {
          visible = count - 1;
        }
        for (var k = 0; k < visible && k < 5; k++) {
          _drawChecker(canvas, geo.checkerAt(i, k), player);
        }
        if (visible > 5) {
          _drawCount(canvas, geo.checkerAt(i, 4), visible);
        }
      }
    }
    // Шашки на баре.
    for (final player in Player.values) {
      final count = controller.state.board.bar(player);
      for (var k = 0; k < count && k < 5; k++) {
        _drawChecker(canvas, geo.barCheckerAt(player == Player.white, k), player);
      }
      if (count > 5) {
        _drawCount(canvas, geo.barCheckerAt(player == Player.white, 4), count);
      }
    }
  }

  void _drawChecker(Canvas canvas, Offset c, Player player) {
    final r = _geo!.checkerRadius;
    final isWhite = player == Player.white;
    // Тень.
    canvas.drawCircle(
      c + Offset(0, r * 0.18),
      r,
      Paint()..color = const Color(0x33000000),
    );
    final base = isWhite ? _whiteChecker : _blackChecker;
    final light = isWhite ? const Color(0xFFFFFFFF) : const Color(0xFF5A4E78);
    canvas.drawCircle(c, r, Paint()..shader = RadialGradient(
      center: Alignment(-0.4, -0.4),
      colors: [light, base],
    ).createShader(Rect.fromCircle(center: c, radius: r)));
    // Ободок.
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4
        ..color = isWhite ? const Color(0xFFC9B68C) : const Color(0xFF221B33),
    );
    // Внутреннее колечко.
    canvas.drawCircle(
      c,
      r * 0.46,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..color = isWhite ? const Color(0xFFE2CFA6) : const Color(0xFF6A5C8C),
    );
  }

  void _drawCount(Canvas canvas, Offset c, int count) {
    final tp = TextPainter(
      text: TextSpan(
        text: '$count',
        style: const TextStyle(
          color: Color(0xFFFFFFFF),
          fontSize: 13,
          fontWeight: FontWeight.w900,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final bg = Rect.fromCircle(center: c, radius: _geo!.checkerRadius * 0.7);
    canvas.drawCircle(
      bg.center,
      bg.width / 2,
      Paint()..color = const Color(0xCC6047AF),
    );
    tp.paint(canvas, bg.center - Offset(tp.width / 2, tp.height / 2));
  }

  void _drawHighlights(Canvas canvas, BoardGeometry geo) {
    if (!controller.hintsEnabled) return;
    // Подсветка шашек, которыми можно ходить.
    for (final point in controller.movablePoints) {
      _strokePoint(canvas, geo, point, _hint);
    }
    // Выбранный пункт.
    final sel = controller.selectedPoint;
    if (sel != null) _strokePoint(canvas, geo, sel, _highlight);
    if (controller.selectedBar) {
      final rect = geo.barRect(controller.state.turn == Player.white);
      canvas.drawRect(
        rect,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3
          ..color = _highlight,
      );
    }
    // Адресаты.
    for (final dest in controller.highlightedDestinations) {
      _strokePoint(canvas, geo, dest, _hint);
      _fillPointDots(canvas, geo, dest, _hint);
    }
    // Вынос как адресат.
    if (controller.highlightedDestinations.isNotEmpty &&
        controller.legalForSelected.any((m) => m.bearOff)) {
      final rect = geo.offRect(controller.state.turn == Player.white);
      canvas.drawRect(
        rect,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3
          ..color = _hint,
      );
    }
  }

  void _strokePoint(Canvas canvas, BoardGeometry geo, int i, Color color) {
    final rect = geo.pointRect(i);
    canvas.drawRect(
      rect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..color = color,
    );
  }

  void _fillPointDots(Canvas canvas, BoardGeometry geo, int i, Color color) {
    final apex = Offset(geo.pointCenterX(i), geo.apexY(i));
    canvas.drawCircle(apex, 6, Paint()..color = color.withValues(alpha: 0.7));
  }

  void _drawFlyer(Canvas canvas, BoardGeometry geo) {
    final f = _flyer;
    if (f == null) return;
    final t = f.t.clamp(0.0, 1.0);
    final eased = (t).toDouble();
    final pos = Offset.lerp(f.from, f.to, eased)!;
    _drawChecker(canvas, pos, f.player);
  }
}

class _Flyer {
  _Flyer({
    required this.player,
    required this.from,
    required this.to,
    required this.t,
    required this.hideDestTop,
    required this.dest,
  });
  final Player player;
  final Offset from;
  final Offset to;
  double t;
  final bool hideDestTop;
  final _Slot dest;
}

class _Slot {
  const _Slot.point(this.point)
      : kind = 'point',
        isWhiteBar = false;
  const _Slot.bar()
      : kind = 'bar',
        point = null,
        isWhiteBar = false;
  const _Slot.off()
      : kind = 'off',
        point = null,
        isWhiteBar = false;
  final String kind;
  final int? point;
  final bool isWhiteBar;
}

class _MoveDiff {
  _MoveDiff({
    required this.player,
    required this.from,
    required this.to,
    required this.hideDestTop,
  });
  final Player player;
  final _Slot from;
  final _Slot to;
  final bool hideDestTop;
}
