import 'package:flutter/material.dart';

import '../../presentation/theme.dart';
import 'engine/model.dart';

/// Костяшка домино: объёмная, с точками и тенью.
///
/// [width] — короткая сторона. В руке и в базаре кость стоит вертикально
/// (`width × 2·width`), а в цепочке лежит вдоль неё ([horizontal]): тогда она
/// занимает `2·width × width`, и её половинки смотрят влево и вправо. Дубли в
/// цепочке остаются вертикальными — они лежат поперёк.
class DominoTileView extends StatelessWidget {
  const DominoTileView({
    super.key,
    required this.tile,
    required this.width,
    this.selected = false,
    this.highlighted = false,
    this.dimmed = false,
    this.horizontal = false,
    this.onTap,
    this.semanticLabel,
  });

  final DominoTile tile;
  final double width;

  /// Кость выбрана: она приподнимается над рукой.
  final bool selected;

  /// Кость подходит к столу — её подсвечивает подсказка.
  final bool highlighted;

  /// Кость не подходит: она тише остальных, но остаётся читаемой.
  final bool dimmed;

  /// Кость лежит вдоль цепочки: половинки смотрят влево и вправо.
  final bool horizontal;

  final VoidCallback? onTap;
  final String? semanticLabel;

  /// Костяшка всегда в пропорции 2:1 — две ширины на одну длину.
  static const heightRatio = 2.0;

  double get _height => width * heightRatio;

  /// Размер на экране с учётом поворота.
  Size get size => horizontal ? Size(_height, width) : Size(width, _height);

  @override
  Widget build(BuildContext context) {
    final face = AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      width: width,
      height: _height,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(width * .17),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFFFFDF8), Color(0xFFF6EAD2), Color(0xFFEADBBE)],
          stops: [0, .55, 1],
        ),
        border: Border.all(
          color: selected
              ? deepPurple
              : (highlighted ? purple : const Color(0xFFD3BF98)),
          width: selected || highlighted ? 2.4 : 1.4,
        ),
        boxShadow: [
          BoxShadow(
            color: (highlighted ? purple : ink).withValues(alpha: .22),
            offset: Offset(0, selected ? 2 : 4),
            blurRadius: selected ? 4 : 0,
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: selected ? .30 : .20),
            offset: Offset(0, selected ? 7 : 6),
            blurRadius: selected ? 12 : 6,
          ),
          if (highlighted)
            BoxShadow(
              color: purple.withValues(alpha: .45),
              blurRadius: 14,
              spreadRadius: 1,
            ),
        ],
      ),
      padding: EdgeInsets.symmetric(
        horizontal: width * .13,
        vertical: width * .12,
      ),
      child: Column(
        children: [
          Expanded(child: _PipHalf(value: tile.a, side: width)),
          Container(
            height: 1.6,
            margin: EdgeInsets.symmetric(vertical: width * .05),
            decoration: BoxDecoration(
              color: const Color(0xFFC4AE86),
              borderRadius: BorderRadius.circular(1),
            ),
          ),
          Expanded(child: _PipHalf(value: tile.b, side: width)),
        ],
      ),
    );

    // Поворот против часовой стрелки: верхняя половинка смотрит влево.
    final rotated = horizontal
        ? RotatedBox(quarterTurns: 3, child: face)
        : face;

    return Semantics(
      label: semanticLabel ?? 'Кость ${tile.label}',
      button: onTap != null,
      child: Opacity(
        opacity: dimmed ? .45 : 1,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: rotated,
        ),
      ),
    );
  }
}

/// Половинка кости с точками от 0 до 6.
class _PipHalf extends StatelessWidget {
  const _PipHalf({required this.value, required this.side});

  final int value;
  final double side;

  /// Где стоят точки: клетки 3×3, начиная с левого верхнего угла.
  static const _patterns = <int, List<int>>{
    0: [],
    1: [4],
    2: [0, 8],
    3: [0, 4, 8],
    4: [0, 2, 6, 8],
    5: [0, 2, 4, 6, 8],
    6: [0, 2, 3, 5, 6, 8],
  };

  @override
  Widget build(BuildContext context) {
    final cells = _patterns[value] ?? const <int>[];
    final dot = side * .19;
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final height = constraints.maxHeight;
        return Stack(
          children: [
            for (final cell in cells)
              Positioned(
                left: (cell % 3) * (width / 3) + (width / 3 - dot) / 2,
                top: (cell ~/ 3) * (height / 3) + (height / 3 - dot) / 2,
                child: Container(
                  width: dot,
                  height: dot,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: const RadialGradient(
                      center: Alignment(-.3, -.4),
                      colors: [Color(0xFF6B5540), Color(0xFF3B2C1F)],
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.white.withValues(alpha: .5),
                        offset: const Offset(0, 1),
                        blurRadius: 1,
                      ),
                    ],
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

/// Обратная сторона кости — так лежит базар.
class DominoTileBack extends StatelessWidget {
  const DominoTileBack({super.key, required this.width});

  final double width;

  @override
  Widget build(BuildContext context) => Container(
    width: width,
    height: width * 2,
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(width * .17),
      gradient: const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFF9C6B41), Color(0xFF7A4E2C)],
      ),
      border: Border.all(color: const Color(0xFF5E3A1F), width: 1.4),
      boxShadow: [
        BoxShadow(
          color: ink.withValues(alpha: .25),
          offset: const Offset(0, 4),
          blurRadius: 4,
        ),
      ],
    ),
    child: Center(
      child: Container(
        width: width * .46,
        height: width * .46,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(width * .1),
          border: Border.all(color: const Color(0xFFFFE8B8).withValues(alpha: .55)),
        ),
        child: Icon(
          Icons.auto_awesome_rounded,
          size: width * .3,
          color: const Color(0xFFFFE8B8).withValues(alpha: .85),
        ),
      ),
    ),
  );
}

/// Маленькая иконка-кость: квадрат с двумя половинками. Используется в панели
/// игрока и в истории ходов.
class TileMark extends StatelessWidget {
  const TileMark({super.key, this.size = 28});

  final double size;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      color: const Color(0xFFFFF8E6),
      borderRadius: BorderRadius.circular(size * .22),
      border: Border.all(color: const Color(0xFFD3BF98), width: 1.2),
    ),
    child: Column(
      children: [
        Expanded(
          child: Container(
            margin: EdgeInsets.all(size * .14),
            decoration: const BoxDecoration(
              color: Color(0xFF3B2C1F),
              shape: BoxShape.circle,
            ),
          ),
        ),
        Container(
          height: 1,
          color: const Color(0xFFD3BF98),
        ),
        Expanded(
          child: Container(
            margin: EdgeInsets.all(size * .14),
            decoration: const BoxDecoration(
              color: Color(0xFF3B2C1F),
              shape: BoxShape.circle,
            ),
          ),
        ),
      ],
    ),
  );
}
