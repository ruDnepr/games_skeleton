import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Машина сверху с объёмом: глянцевый кузов, крыша, стёкла, колёса, фары
/// и тень. Машина на 3 клетки рисуется грузовиком: кабина спереди и высокий
/// грузовой кузов с рёбрами.
///
/// Машина всегда рисуется «носом вправо», а для вертикальных машин картинка
/// поворачивается на 90 градусов. Длина кузова — [length] клеток, толщина —
/// одна клетка, поэтому рисунок масштабируется под любой размер поля.
class CarPainter extends CustomPainter {
  const CarPainter({
    required this.color,
    required this.length,
    required this.vertical,
    this.highlighted = false,
  });

  final Color color;
  final int length;
  final bool vertical;

  /// Подсветка машины, которой касается подсказка.
  final bool highlighted;

  bool get _isTruck => length >= 3;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width < 2 || size.height < 2) return;
    final long = vertical ? size.height : size.width;
    final thick = vertical ? size.width : size.height;
    canvas.save();
    if (vertical) {
      canvas.translate(size.width / 2, size.height / 2);
      canvas.rotate(-math.pi / 2);
      canvas.translate(-long / 2, -thick / 2);
    }
    _paintCar(canvas, long, thick);
    canvas.restore();
  }

  void _paintCar(Canvas canvas, double length, double thick) {
    final body = Rect.fromLTRB(
      length * 0.03,
      thick * 0.11,
      length * 0.97,
      thick * 0.89,
    );
    final rounded = _isTruck ? 0.16 : 0.30;
    final shape = RRect.fromRectAndRadius(
      body,
      Radius.circular(thick * rounded),
    );

    _shadow(canvas, shape, thick);
    _wheels(canvas, length, thick);
    _body(canvas, body, shape, thick);
    if (_isTruck) {
      _truck(canvas, body, thick);
    } else {
      _sedan(canvas, body, thick);
    }
    _lights(canvas, body, thick);
    if (highlighted) _highlight(canvas, shape, thick);
  }

  // ------------------------------------------------------------- кузов

  void _shadow(Canvas canvas, RRect shape, double thick) => canvas.drawRRect(
    shape.shift(Offset(thick * 0.02, thick * 0.12)),
    Paint()
      ..color = const Color(0xFF100B1A).withValues(alpha: .45)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, thick * 0.10),
  );

  /// Колёса видны по краям кузова — это даёт ощущение объёма.
  void _wheels(Canvas canvas, double length, double thick) {
    final tyre = Paint()..color = const Color(0xFF17121F);
    final hub = Paint()..color = const Color(0xFF5B5566);
    final axles = _isTruck
        ? const <double>[0.16, 0.72, 0.88]
        : const <double>[0.22, 0.74];
    final width = length * (_isTruck ? 0.075 : 0.10);
    final height = thick * 0.075;
    for (final axle in axles) {
      for (final top in <double>[thick * 0.05, thick * 0.95 - height]) {
        final rect = Rect.fromLTWH(
          axle * length - width / 2,
          top,
          width,
          height,
        );
        canvas.drawRRect(
          RRect.fromRectAndRadius(rect, Radius.circular(height * 0.45)),
          tyre,
        );
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            rect.deflate(width * 0.18),
            Radius.circular(height * 0.25),
          ),
          hub,
        );
      }
    }
  }

  void _body(Canvas canvas, Rect body, RRect shape, double thick) {
    canvas.drawRRect(
      shape,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[
            Color.lerp(color, Colors.white, .40)!,
            Color.lerp(color, Colors.white, .10)!,
            color,
            Color.lerp(color, const Color(0xFF18102A), .34)!,
          ],
          stops: const <double>[0, .22, .62, 1],
        ).createShader(body),
    );

    canvas.save();
    canvas.clipRRect(shape);
    // Глянцевый блик по левой (задней) части кузова.
    canvas.drawRect(
      body,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: <Color>[
            Colors.white.withValues(alpha: .26),
            Colors.white.withValues(alpha: .06),
            Colors.white.withValues(alpha: 0),
          ],
          stops: const <double>[0, .35, .70],
        ).createShader(body),
    );
    canvas.restore();

    canvas.drawRRect(
      shape,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(1, thick * 0.022)
        ..color = Color.lerp(color, Colors.black, .55)!.withValues(alpha: .58),
    );
  }

  // ------------------------------------------------------ легковая машина

  void _sedan(Canvas canvas, Rect body, double thick) {
    final length = body.width;
    final left = body.left;
    final top = body.top + thick * 0.10;
    final bottom = body.bottom - thick * 0.10;
    final height = bottom - top;

    _panel(
      canvas,
      Rect.fromLTRB(left + length * .74, top, left + length * .95, bottom),
      thick * 0.12,
    );
    _panel(
      canvas,
      Rect.fromLTRB(left + length * .05, top, left + length * .19, bottom),
      thick * 0.10,
    );
    _roof(
      canvas,
      Rect.fromLTRB(left + length * .30, top, left + length * .62, bottom),
      thick * 0.14,
    );
    // Блик по верхней кромке кузова — читается как глянцевый металл.
    canvas.drawLine(
      Offset(left + length * .22, top + thick * .02),
      Offset(left + length * .80, top + thick * .02),
      Paint()
        ..strokeWidth = math.max(1, thick * 0.018)
        ..color = Colors.white.withValues(alpha: .35),
    );
    _glass(
      canvas,
      Rect.fromLTRB(
        left + length * .62,
        top + thick * .02,
        left + length * .72,
        top + height - thick * .02,
      ),
      thick * 0.07,
    );
    _glass(
      canvas,
      Rect.fromLTRB(
        left + length * .21,
        top + thick * .06,
        left + length * .29,
        top + height - thick * .06,
      ),
      thick * 0.05,
    );
    _seam(canvas, left + length * .74, top, bottom, thick);
    _seam(canvas, left + length * .19, top, bottom, thick);
  }

  // ------------------------------------------------------------- грузовик

  void _truck(Canvas canvas, Rect body, double thick) {
    final length = body.width;
    final left = body.left;
    final top = body.top + thick * 0.08;
    final bottom = body.bottom - thick * 0.08;
    final height = bottom - top;

    // Грузовой кузов: светлая будка с рёбрами и рамой.
    final box = Rect.fromLTRB(
      left + length * .03,
      top,
      left + length * .60,
      bottom,
    );
    final boxShape = RRect.fromRectAndRadius(
      box,
      Radius.circular(thick * 0.07),
    );
    canvas.drawRRect(
      boxShape,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[
            Color.lerp(color, Colors.white, .62)!,
            Color.lerp(color, Colors.white, .46)!,
            Color.lerp(color, Colors.black, .10)!,
          ],
          stops: const <double>[0, .40, 1],
        ).createShader(box),
    );
    final rib = Paint()
      ..color = Color.lerp(color, Colors.black, .55)!.withValues(alpha: .30)
      ..strokeWidth = math.max(1, thick * 0.016);
    for (var index = 1; index < 5; index++) {
      final x = box.left + box.width * index / 5;
      canvas.drawLine(
        Offset(x, box.top + thick * 0.04),
        Offset(x, box.bottom - thick * 0.04),
        rib,
      );
    }
    // Продольные рёбра жёсткости.
    for (final y in <double>[box.top + height * .30, box.top + height * .70]) {
      canvas.drawLine(
        Offset(box.left + thick * 0.03, y),
        Offset(box.right - thick * 0.03, y),
        rib,
      );
    }
    canvas.drawRRect(
      boxShape,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(1, thick * 0.030)
        ..color = Color.lerp(color, Colors.black, .60)!.withValues(alpha: .70),
    );
    // Задний борт.
    canvas.drawRect(
      Rect.fromLTRB(
        box.left,
        box.top + thick * 0.06,
        box.left + length * .025,
        box.bottom - thick * 0.06,
      ),
      Paint()
        ..color = Color.lerp(color, Colors.black, .45)!.withValues(alpha: .70),
    );

    // Зазор между кузовом и кабиной.
    canvas.drawRect(
      Rect.fromLTRB(
        left + length * .605,
        top + thick * 0.10,
        left + length * .635,
        bottom - thick * 0.10,
      ),
      Paint()..color = const Color(0xFF2A2436).withValues(alpha: .55),
    );

    // Кабина: своя крыша, лобовое стекло и короткий нос.
    final cab = Rect.fromLTRB(
      left + length * .64,
      top,
      left + length * .97,
      bottom,
    );
    final cabShape = RRect.fromRectAndRadius(
      cab,
      Radius.circular(thick * 0.12),
    );
    canvas.drawRRect(
      cabShape,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[
            Color.lerp(color, Colors.white, .55)!,
            color,
            Color.lerp(color, const Color(0xFF18102A), .30)!,
          ],
          stops: const <double>[0, .55, 1],
        ).createShader(cab),
    );
    canvas.drawRRect(
      cabShape,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(1, thick * 0.022)
        ..color = Color.lerp(color, Colors.black, .55)!.withValues(alpha: .55),
    );
    _roof(
      canvas,
      Rect.fromLTRB(
        left + length * .66,
        top + thick * .05,
        left + length * .80,
        bottom - thick * .05,
      ),
      thick * 0.10,
    );
    _glass(
      canvas,
      Rect.fromLTRB(
        left + length * .80,
        top + thick * .05,
        left + length * .90,
        bottom - thick * .05,
      ),
      thick * 0.06,
    );
    _panel(
      canvas,
      Rect.fromLTRB(
        left + length * .90,
        top + thick * .06,
        left + length * .96,
        bottom - thick * .06,
      ),
      thick * 0.06,
    );
  }

  // --------------------------------------------------------- отделка

  void _panel(
    Canvas canvas,
    Rect rect,
    double radius, {
    double fill = 0,
  }) {
    final shape = RRect.fromRectAndRadius(rect, Radius.circular(radius));
    final base = fill >= 0
        ? Color.lerp(color, Colors.white, fill)!
        : Color.lerp(color, Colors.black, -fill)!;
    canvas.drawRRect(shape, Paint()..color = base);
    canvas.drawRRect(
      shape,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(0.8, rect.height * 0.03)
        ..color = Colors.black.withValues(alpha: .09),
    );
  }

  void _roof(Canvas canvas, Rect rect, double radius) {
    final shape = RRect.fromRectAndRadius(rect, Radius.circular(radius));
    canvas.drawRRect(
      shape,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[
            Color.lerp(color, Colors.white, .30)!,
            Color.lerp(color, Colors.white, .16)!,
            Color.lerp(color, Colors.black, .10)!,
          ],
          stops: const <double>[0, .55, 1],
        ).createShader(rect),
    );
    canvas.drawRRect(
      shape,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(0.8, rect.height * 0.03)
        ..color = Colors.black.withValues(alpha: .12),
    );
  }

  void _glass(Canvas canvas, Rect rect, double radius) {
    if (rect.width < 1) return;
    final shape = RRect.fromRectAndRadius(rect, Radius.circular(radius));
    canvas.drawRRect(
      shape,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: <Color>[
            Color(0xFF9FC2D8),
            Color(0xFF6E8CA6),
            Color(0xFF313F50),
          ],
          stops: <double>[0, .55, 1],
        ).createShader(rect),
    );
    canvas.drawRRect(
      shape,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(0.8, rect.width * 0.06)
        ..color = Colors.white.withValues(alpha: .32),
    );
  }

  /// Шов между кузовными панелями.
  void _seam(Canvas canvas, double x, double top, double bottom, double thick) {
    canvas.drawLine(
      Offset(x, top),
      Offset(x, bottom),
      Paint()
        ..strokeWidth = math.max(0.8, thick * 0.014)
        ..color = Colors.black.withValues(alpha: .12),
    );
  }

  void _lights(Canvas canvas, Rect body, double thick) {
    final length = body.width;
    final height = thick * 0.07;
    const head = Color(0xFFFFF8D8);
    const tail = Color(0xFFFF4E5C);
    for (final top in <double>[
      body.top + thick * 0.14,
      body.bottom - thick * 0.14 - height,
    ]) {
      final front = Rect.fromLTRB(
        body.left + length * .945,
        top,
        body.left + length * .975,
        top + height,
      );
      final back = Rect.fromLTRB(
        body.left + length * .025,
        top,
        body.left + length * .055,
        top + height,
      );
      _lamp(canvas, front, head, height);
      _lamp(canvas, back, tail, height);
    }
  }

  void _lamp(Canvas canvas, Rect rect, Color color, double height) {
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        rect.inflate(height * 0.45),
        Radius.circular(height),
      ),
      Paint()
        ..color = color.withValues(alpha: .40)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, height * 0.55),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, Radius.circular(height * 0.45)),
      Paint()..color = color,
    );
  }

  void _highlight(Canvas canvas, RRect shape, double thick) {
    canvas.drawRRect(
      shape.inflate(thick * 0.03),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = thick * 0.12
        ..color = const Color(0xFFFFC53D).withValues(alpha: .82)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, thick * 0.06),
    );
    canvas.drawRRect(
      shape,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(2, thick * 0.035)
        ..color = const Color(0xFFFFE9A8),
    );
  }

  @override
  bool shouldRepaint(CarPainter oldDelegate) =>
      oldDelegate.color != color ||
      oldDelegate.length != length ||
      oldDelegate.vertical != vertical ||
      oldDelegate.highlighted != highlighted;
}
