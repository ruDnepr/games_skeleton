import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Пара кубиков с заметной анимацией броска: при смене значений кубики
/// подпрыгивают, крутятся и быстро меняют лица ~600 мс, потом с лёгким
/// отскоком оседают на выпавших. Использованные кости затемнены.
class DiceWidget extends StatefulWidget {
  const DiceWidget({
    super.key,
    required this.rolled,
    required this.available,
    this.onRoll,
    this.canRoll = false,
  });

  final List<int> rolled;
  final List<int> available;
  final VoidCallback? onRoll;
  final bool canRoll;

  @override
  State<DiceWidget> createState() => _DiceWidgetState();
}

class _DiceWidgetState extends State<DiceWidget>
    with SingleTickerProviderStateMixin {
  late final AnimationController _anim = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 620),
  );

  @override
  void initState() {
    super.initState();
    // При создании виджета с уже брошенными костями (новый ход) — сразу
    // запускаем анимацию броска. Иначе она проиграется только при следующем
    // обновлении, и первый бросок после смены хода будет без анимации.
    if (widget.rolled.isNotEmpty) {
      _anim.forward(from: 0);
    }
  }

  @override
  void didUpdateWidget(covariant DiceWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_listEquals(widget.rolled, oldWidget.rolled)) {
      _anim.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final rolled = widget.rolled;
    final isDouble = rolled.length == 2 && rolled[0] == rolled[1];
    final dice = isDouble ? List.filled(4, rolled[0]) : rolled;
    // Сколько костей разыграно — от числа показанных костей (4 для дубля),
    // не от длины rolled (2): иначе при дубле получалось отрицательное число.
    final usedCount = dice.length - widget.available.length;

    return GestureDetector(
      onTap: widget.canRoll ? widget.onRoll : null,
      child: AnimatedBuilder(
        animation: _anim,
        builder: (context, _) {
          final t = _anim.value;
          final tumbling = t > 0 && t < 1;
          return Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < dice.length; i++)
                Padding(
                  padding:
                      EdgeInsets.only(right: i == dice.length - 1 ? 0 : 8),
                  child: _Die(
                    value: tumbling
                        ? ((DateTime.now().millisecondsSinceEpoch ~/
                                    70 +
                                i * 3) %
                            6) +
                            1
                        : dice[i],
                    used: !tumbling && i < usedCount,
                    // Подскок: вверх-вниз синусоидой, затухающей к концу.
                    bounce: tumbling
                        ? math.sin(t * math.pi * 3) * (1 - t) * 8
                        : 0,
                    // Вращение: пара оборотов с замедлением.
                    rotation: tumbling ? t * 2.2 * math.pi * (1 - t * 0.6) : 0,
                    // Лёгкое увеличение в полёте.
                    scale: tumbling ? 1 + 0.12 * (1 - t) : 1,
                  ),
                ),
              if (isDouble && rolled.isNotEmpty) ...[
                const SizedBox(width: 8),
                const Text(
                  'дубль!',
                  style: TextStyle(
                    color: Color(0xFF6047AF),
                    fontWeight: FontWeight.w900,
                    fontSize: 13,
                  ),
                ),
              ],
            ],
          );
        },
      ),
    );
  }

  bool _listEquals(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

class _Die extends StatelessWidget {
  const _Die({
    required this.value,
    required this.used,
    required this.bounce,
    required this.rotation,
    required this.scale,
  });
  final int value;
  final bool used;
  final double bounce;
  final double rotation;
  final double scale;

  @override
  Widget build(BuildContext context) => Transform.translate(
    offset: Offset(0, -bounce),
    child: Transform.rotate(
      angle: rotation,
      child: Transform.scale(
        scale: scale,
        child: Opacity(
          opacity: used ? 0.35 : 1,
          child: Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: used ? const Color(0xFFE4E0EE) : Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFD7CCEC), width: 1.5),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x221E1633),
                  blurRadius: 6,
                  offset: Offset(0, 3),
                ),
              ],
            ),
            child: CustomPaint(painter: _PipsPainter(value)),
          ),
        ),
      ),
    ),
  );
}

class _PipsPainter extends CustomPainter {
  _PipsPainter(this.value);
  final int value;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = const Color(0xFF3D3154);
    final s = size.width;
    final r = s * 0.11;
    final c = Offset(s / 2, s / 2);
    final off = s * 0.26;
    final positions = _pipPositions(value, c, off);
    for (final p in positions) {
      canvas.drawCircle(p, r, paint);
    }
  }

  List<Offset> _pipPositions(int v, Offset c, double off) {
    final tl = c + Offset(-off, -off);
    final tr = c + Offset(off, -off);
    final ml = c + Offset(-off, 0);
    final mr = c + Offset(off, 0);
    final bl = c + Offset(-off, off);
    final br = c + Offset(off, off);
    switch (v) {
      case 1:
        return [c];
      case 2:
        return [tl, br];
      case 3:
        return [tl, c, br];
      case 4:
        return [tl, tr, bl, br];
      case 5:
        return [tl, tr, c, bl, br];
      case 6:
        return [tl, tr, ml, mr, bl, br];
      default:
        return [c];
    }
  }

  @override
  bool shouldRepaint(covariant _PipsPainter old) => old.value != value;
}
