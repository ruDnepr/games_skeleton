import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'engine/model.dart';

/// Парковка: асфальт, контрастная разметка мест и зелёный выезд в ряду 2.
///
/// Клетки чередуются по светлоте и разделены заметными швами, чтобы границы
/// клеток читались и под машинами, и на пустом поле.
class LotPainter extends CustomPainter {
  const LotPainter({required this.cell});

  /// Размер клетки поля в пикселях.
  final double cell;

  static const Color _asphaltLight = Color(0xFF5A5273);
  static const Color _asphaltDark = Color(0xFF443D59);
  static const Color _asphaltDeep = Color(0xFF2E2941);
  static const Color _exitGreen = Color(0xFF3ED47F);

  @override
  void paint(Canvas canvas, Size size) {
    final board = Offset.zero & size;
    final shape = RRect.fromRectAndRadius(
      board,
      Radius.circular(cell * 0.32),
    );

    canvas.drawRRect(
      shape,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[_asphaltDeep, _asphaltDark],
        ).createShader(board),
    );

    canvas.save();
    canvas.clipRRect(shape);
    _cells(canvas, size);
    _grid(canvas, size);
    _exit(canvas, size);
    canvas.drawRect(
      board,
      Paint()
        ..shader = RadialGradient(
          radius: .9,
          colors: <Color>[
            Colors.white.withValues(alpha: .05),
            Colors.black.withValues(alpha: .22),
          ],
        ).createShader(board),
    );
    canvas.restore();

    canvas.drawRRect(
      shape,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(1.5, cell * 0.03)
        ..color = Colors.white.withValues(alpha: .26),
    );
  }

  /// Шахматные клетки: светлее и темнее через одну.
  void _cells(Canvas canvas, Size size) {
    final light = Paint()..color = _asphaltLight.withValues(alpha: .55);
    final dark = Paint()..color = Colors.black.withValues(alpha: .16);
    for (var row = 0; row < boardSize; row++) {
      for (var col = 0; col < boardSize; col++) {
        final rect = Rect.fromLTWH(col * cell, row * cell, cell, cell);
        canvas.drawRect(rect, (row + col).isEven ? light : dark);
      }
    }
  }

  /// Швы между клетками: тёмная канавка и светлая линия по ней.
  void _grid(Canvas canvas, Size size) {
    final groove = Paint()
      ..color = Colors.black.withValues(alpha: .38)
      ..strokeWidth = math.max(2, cell * 0.045);
    final edge = Paint()
      ..color = Colors.white.withValues(alpha: .14)
      ..strokeWidth = math.max(1, cell * 0.016);
    for (var index = 1; index < boardSize; index++) {
      final offset = index * cell;
      canvas.drawLine(Offset(offset, 0), Offset(offset, size.height), groove);
      canvas.drawLine(Offset(0, offset), Offset(size.width, offset), groove);
      canvas.drawLine(
        Offset(offset - cell * 0.022, 0),
        Offset(offset - cell * 0.022, size.height),
        edge,
      );
      canvas.drawLine(
        Offset(0, offset - cell * 0.022),
        Offset(size.width, offset - cell * 0.022),
        edge,
      );
    }
  }

  /// Ряд выезда подсвечен зелёным, у правого края — «рампа» со стрелками.
  void _exit(Canvas canvas, Size size) {
    final row = Rect.fromLTWH(0, exitRow * cell, size.width, cell);
    canvas.drawRect(
      row,
      Paint()..color = _exitGreen.withValues(alpha: .13),
    );

    final lane = Rect.fromLTWH(size.width - cell, exitRow * cell, cell, cell);
    canvas.drawRect(
      lane,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: <Color>[
            _exitGreen.withValues(alpha: .12),
            _exitGreen.withValues(alpha: .62),
          ],
        ).createShader(lane),
    );

    final arrow = Paint()..color = Colors.white.withValues(alpha: .90);
    for (var index = 0; index < 2; index++) {
      final centerX = lane.left + lane.width * (0.30 + index * 0.34);
      final centerY = lane.center.dy;
      final width = lane.width * 0.22;
      final height = lane.height * 0.26;
      final chevron = Path()
        ..moveTo(centerX - width / 2, centerY - height)
        ..lineTo(centerX + width / 2, centerY)
        ..lineTo(centerX - width / 2, centerY + height)
        ..lineTo(centerX - width * 0.15, centerY)
        ..close();
      canvas.drawPath(chevron, arrow);
    }

    // Полосатое ограждение у самого края — как настоящий выезд с парковки.
    final stripeHeight = cell * 0.16;
    for (var index = 0; index < 6; index++) {
      final top = exitRow * cell + index * stripeHeight;
      canvas.drawRect(
        Rect.fromLTWH(
          size.width - cell * 0.07,
          top,
          cell * 0.07,
          stripeHeight / 2,
        ),
        Paint()..color = Colors.white.withValues(alpha: .55),
      );
    }
  }

  @override
  bool shouldRepaint(LotPainter oldDelegate) => oldDelegate.cell != cell;
}
