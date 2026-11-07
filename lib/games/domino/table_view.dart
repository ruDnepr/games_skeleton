import 'dart:math';

import 'package:flutter/material.dart';

import '../../presentation/theme.dart';
import 'engine/model.dart';
import 'tile_view.dart';

/// Дерево стола.
const wood = Color(0xFF8B552E);
const woodLight = Color(0xFFB77A3D);
const woodDark = Color(0xFF613D23);

/// Сукно, на котором лежат кости.
const felt = Color(0xFF2F6B4F);
const feltLight = Color(0xFF3F8462);

/// Сукно стола в деревянной рамке.
class TableSurface extends StatelessWidget {
  const TableSurface({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.fromLTRB(8, 8, 8, 8),
  });

  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      color: wood,
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: woodLight, width: 2),
      boxShadow: const [
        BoxShadow(color: woodDark, offset: Offset(0, 5)),
        BoxShadow(
          color: Color(0x446B492D),
          blurRadius: 16,
          offset: Offset(0, 10),
        ),
      ],
    ),
    padding: const EdgeInsets.all(4),
    child: ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [feltLight, felt, Color(0xFF255741)],
          ),
        ),
        child: CustomPaint(
          painter: _FeltPainter(),
          child: Padding(padding: padding, child: child),
        ),
      ),
    ),
  );
}

/// Лёгкая текстура сукна: диагональные штрихи и мелкие крапинки.
class _FeltPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final lines = Paint()
      ..color = Colors.white.withValues(alpha: .035)
      ..strokeWidth = 1;
    for (double x = -size.height; x < size.width; x += 7) {
      canvas.drawLine(Offset(x, 0), Offset(x + size.height, size.height), lines);
    }
    final random = Random(7);
    final dots = Paint()..color = Colors.black.withValues(alpha: .05);
    for (var index = 0; index < 110; index++) {
      canvas.drawCircle(
        Offset(random.nextDouble() * size.width, random.nextDouble() * size.height),
        random.nextDouble() * 1.3 + .4,
        dots,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _FeltPainter oldDelegate) => false;
}

/// Цепочка костей на столе.
///
/// Кости лежат вдоль цепочки, дубли — поперёк. Если цепочка длиннее экрана,
/// она прокручивается сама к тому концу, куда только что поставили кость.
class ChainView extends StatefulWidget {
  const ChainView({
    super.key,
    required this.placed,
    this.scrollToken = 0,
    this.scrollTo,
  });

  final List<PlacedTile> placed;

  /// Меняется после каждого хода: по нему цепочка понимает, что пора
  /// прокрутиться к нужному концу.
  final int scrollToken;
  final ChainSide? scrollTo;

  @override
  State<ChainView> createState() => _ChainViewState();
}

class _ChainViewState extends State<ChainView> {
  final ScrollController _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToSide(widget.scrollTo));
  }

  @override
  void didUpdateWidget(ChainView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.scrollToken != widget.scrollToken) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _scrollToSide(widget.scrollTo),
      );
    }
  }

  void _scrollToSide(ChainSide? side) {
    if (!mounted || !_scroll.hasClients) return;
    final target = side == ChainSide.left ? 0.0 : _scroll.position.maxScrollExtent;
    if ((_scroll.offset - target).abs() < 2) return;
    _scroll.animateTo(
      target,
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOut,
    );
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      // Дубль в цепочке стоит поперёк, поэтому по высоте кость занимает
      // половину полосы. Верхняя граница держит кости мелкими: так в
      // цепочку помещается больше костей, а не одна-две.
      final byHeight = constraints.hasBoundedHeight
          ? (constraints.maxHeight - 12) / 2
          : 30.0;
      final width = byHeight.clamp(10.0, 28.0).toDouble();
      if (widget.placed.isEmpty) {
        return const Center(
          child: Text(
            'Цепочка пока пустая',
            style: TextStyle(
              color: Colors.white70,
              fontWeight: FontWeight.w800,
              fontSize: 13,
            ),
          ),
        );
      }
      return SingleChildScrollView(
        key: const Key('chain'),
        controller: _scroll,
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            for (final (index, placed) in widget.placed.indexed)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 1.5),
                child: DominoTileView(
                  key: Key('chain-tile-$index'),
                  tile: DominoTile(placed.left, placed.right),
                  width: width,
                  horizontal: !placed.isAcross,
                  semanticLabel: placed.isAcross
                      ? 'Дубль ${placed.left}:${placed.right} поперёк цепочки'
                      : 'Кость ${placed.left}:${placed.right} в цепочке',
                ),
              ),
          ],
        ),
      );
    },
  );
}

/// Открытый конец цепочки: крупное число и стрелка.
class EndChip extends StatelessWidget {
  const EndChip({
    super.key,
    required this.value,
    required this.side,
    required this.onTap,
    this.highlighted = false,
    this.enabled = true,
  });

  final int? value;
  final ChainSide side;
  final VoidCallback onTap;
  final bool highlighted;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final arrow = side == ChainSide.left
        ? Icons.arrow_back_rounded
        : Icons.arrow_forward_rounded;
    final background = highlighted
        ? purple
        : Colors.white.withValues(alpha: .16);
    const foreground = Colors.white;
    return Semantics(
      button: true,
      label: value == null
          ? 'Конец цепочки'
          : 'Поставить к концу $value ${side.label}',
      child: Opacity(
        opacity: enabled ? 1 : .5,
        child: Material(
          color: background,
          borderRadius: BorderRadius.circular(14),
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: enabled ? onTap : null,
            child: Container(
              constraints: const BoxConstraints(minWidth: 54, minHeight: 40),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: highlighted
                      ? Colors.white.withValues(alpha: .8)
                      : Colors.white.withValues(alpha: .22),
                  width: 1.5,
                ),
                boxShadow: highlighted
                    ? [
                        BoxShadow(
                          color: purple.withValues(alpha: .6),
                          blurRadius: 12,
                          spreadRadius: 1,
                        ),
                      ]
                    : null,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (side == ChainSide.left) Icon(arrow, size: 16, color: foreground),
                  const SizedBox(width: 2),
                  Text(
                    value?.toString() ?? '–',
                    style: TextStyle(
                      color: foreground,
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(width: 2),
                  if (side == ChainSide.right) Icon(arrow, size: 16, color: foreground),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Стопка закрытых костей в базаре.
class BazaarStack extends StatelessWidget {
  const BazaarStack({
    super.key,
    required this.count,
    required this.enabled,
    required this.onTap,
  });

  final int count;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final backWidth = 15.0;
    return Semantics(
      button: enabled,
      label: 'Базар: $count костей',
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: enabled ? onTap : null,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
            decoration: BoxDecoration(
              color: enabled
                  ? yellow.withValues(alpha: .95)
                  : Colors.white.withValues(alpha: .16),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: Colors.white.withValues(alpha: .25),
                width: 1.5,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: backWidth * 2.2,
                  height: backWidth * 2,
                  child: Stack(
                    children: [
                      for (final (index, shift) in const [0.0, 4.0, 8.0].indexed)
                        Positioned(
                          left: shift,
                          top: index.isEven ? 0 : 2,
                          child: DominoTileBack(width: backWidth),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 7),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Базар',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w900,
                        color: enabled ? ink : Colors.white,
                      ),
                    ),
                    Text(
                      '$count',
                      style: TextStyle(
                        fontSize: 17,
                        height: 1,
                        fontWeight: FontWeight.w900,
                        color: enabled ? ink : Colors.white,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Панель игрока: имя, сколько у него костей и чей сейчас ход.
class PlayerPanel extends StatelessWidget {
  const PlayerPanel({
    super.key,
    required this.seat,
    required this.name,
    required this.tiles,
    required this.active,
    this.compact = false,
    this.isMe = false,
    this.note,
  });

  final int seat;
  final String name;
  final int tiles;
  final bool active;
  final bool compact;
  final bool isMe;
  final String? note;

  @override
  Widget build(BuildContext context) {
    final subtitle = note ?? (tiles == 0 ? 'все кости выложены' : '$tiles ${_tilesWord(tiles)}');
    return Container(
      key: Key('player-panel-$seat'),
      height: compact ? 44 : 54,
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 9 : 12,
        vertical: compact ? 4 : 6,
      ),
      decoration: BoxDecoration(
        color: active
            ? const Color(0xFFEDE5FD)
            : Colors.white.withValues(alpha: .82),
        borderRadius: BorderRadius.circular(compact ? 15 : 18),
        border: Border.all(
          color: active ? const Color(0xFFB9A3EF) : const Color(0xFFF1EAE5),
          width: 2,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          TileMark(size: compact ? 26 : 32),
          SizedBox(width: compact ? 7 : 9),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    isMe ? '$name · ты' : name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: compact ? 12 : 13,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 10,
                      color: muted,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (active) ...[
            const SizedBox(width: 6),
            Eyebrow(
              'ХОД',
              color: deepPurple,
              background: const Color(0xFFDCCDF8),
              fontSize: compact ? 8 : 9,
            ),
          ],
        ],
      ),
    );
  }

  static String _tilesWord(int count) {
    final mod10 = count % 10;
    final mod100 = count % 100;
    if (mod10 == 1 && mod100 != 11) return 'кость';
    if (mod10 >= 2 && mod10 <= 4 && (mod100 < 12 || mod100 > 14)) {
      return 'кости';
    }
    return 'костей';
  }
}

/// Панели всех игроков, кроме того, чья рука показана внизу.
class PlayersStrip extends StatelessWidget {
  const PlayersStrip({
    super.key,
    required this.names,
    required this.handSizes,
    required this.activeSeat,
    required this.handSeat,
    required this.notes,
    this.compact = false,
  });

  final List<String> names;
  final List<int> handSizes;
  final int activeSeat;
  final int handSeat;
  final Map<int, String> notes;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final others = [
      for (var seat = 0; seat < names.length; seat++)
        if (seat != handSeat) seat,
    ];
    if (others.isEmpty) return const SizedBox.shrink();
    return SizedBox(
      height: compact ? 44 : 54,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 2),
        child: Row(
          children: [
            for (final seat in others) ...[
              PlayerPanel(
                seat: seat,
                name: names[seat],
                tiles: seat < handSizes.length ? handSizes[seat] : 0,
                active: seat == activeSeat,
                compact: compact,
                isMe: false,
                note: notes[seat],
              ),
              if (seat != others.last) const SizedBox(width: 8),
            ],
          ],
        ),
      ),
    );
  }
}

/// Кости в руке. Крупные, с подсветкой тех, что подходят к столу.
class HandView extends StatelessWidget {
  const HandView({
    super.key,
    required this.tiles,
    required this.playable,
    required this.selected,
    required this.hintsEnabled,
    required this.onTap,
    this.suggested,
    this.reserved = false,
  });

  final List<DominoTile> tiles;
  final Set<DominoTile> playable;
  final DominoTile? selected;
  final DominoTile? suggested;
  final bool hintsEnabled;
  final ValueChanged<DominoTile> onTap;

  /// Ход другого игрока: чужие кости не нажимаются.
  final bool reserved;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      if (tiles.isEmpty) {
        return const Center(
          child: Text(
            'Костей нет — ты всё выложил!',
            style: TextStyle(
              color: muted,
              fontWeight: FontWeight.w900,
              fontSize: 13,
            ),
          ),
        );
      }
      final gap = 6.0;
      final byWidth =
          (constraints.maxWidth - gap * (tiles.length - 1)) / tiles.length;
      // Пропорция кости — 2:1, поэтому ширина ограничена половиной высоты
      // полосы: иначе высокие кости обрезались снизу.
      final byHeight = constraints.hasBoundedHeight
          ? (constraints.maxHeight - 8) / 2
          : 60.0;
      final limit = byHeight.clamp(18.0, 58.0).toDouble();
      final width = byWidth.clamp(16.0, limit).toDouble();
      return SingleChildScrollView(
        key: const Key('hand'),
        scrollDirection: Axis.horizontal,
        child: ConstrainedBox(
          constraints: BoxConstraints(minWidth: constraints.maxWidth),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (final (index, tile) in tiles.indexed) ...[
                if (index > 0) SizedBox(width: gap),
                _HandTile(
                  tile: tile,
                  width: width,
                  highlighted: hintsEnabled && playable.contains(tile),
                  selected: selected == tile,
                  suggested: suggested == tile,
                  onTap: reserved ? null : () => onTap(tile),
                ),
              ],
            ],
          ),
        ),
      );
    },
  );
}

class _HandTile extends StatelessWidget {
  const _HandTile({
    required this.tile,
    required this.width,
    required this.highlighted,
    required this.selected,
    required this.suggested,
    required this.onTap,
  });

  final DominoTile tile;
  final double width;
  final bool highlighted;
  final bool selected;
  final bool suggested;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => AnimatedSlide(
    offset: Offset(0, selected ? -.05 : 0),
    duration: const Duration(milliseconds: 160),
    curve: Curves.easeOut,
    child: DominoTileView(
      key: Key('hand-tile-${tile.label}'),
      tile: tile,
      width: width,
      selected: selected || suggested,
      highlighted: highlighted && !selected,
      onTap: onTap,
    ),
  );
}
