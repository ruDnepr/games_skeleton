"""Рисует иконку приложения «Игры для Дианы» из палитры каркаса.

Иконка повторяет логотип главного окна: наклонённая подложка с сеткой, два
жетона и звёздочка. Сетка на подложке нейтральная: ни фигур, ни позиции
конкретной игры.

Запуск (нужен Pillow):

    python3 tool/make_icon.py

Скрипт перезаписывает android/app/src/main/res/mipmap-*/ic_launcher.png и все
размеры ios/Runner/Assets.xcassets/AppIcon.appiconset/*.png. Иконки iOS
сохраняются без альфа-канала: App Store не принимает прозрачность.
"""
from __future__ import annotations

import math
from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[1]

CREAM = (255, 248, 237)
WOOD = (140, 88, 49)
WOOD_LIGHT = (166, 108, 61)
BOARD_LIGHT = (255, 243, 218)
BOARD_DARK = (231, 221, 247)
PURPLE = (130, 102, 213)
YELLOW = (255, 214, 109)
GOLD = (240, 190, 72)
WHITE = (255, 255, 255)
INK = (61, 49, 84)

ANDROID_SIZES = {
    'mipmap-mdpi': 48,
    'mipmap-hdpi': 72,
    'mipmap-xhdpi': 96,
    'mipmap-xxhdpi': 144,
    'mipmap-xxxhdpi': 192,
}

IOS_SIZES = {
    'Icon-App-20x20@1x.png': 20,
    'Icon-App-20x20@2x.png': 40,
    'Icon-App-20x20@3x.png': 60,
    'Icon-App-29x29@1x.png': 29,
    'Icon-App-29x29@2x.png': 58,
    'Icon-App-29x29@3x.png': 87,
    'Icon-App-40x40@1x.png': 40,
    'Icon-App-40x40@2x.png': 80,
    'Icon-App-40x40@3x.png': 120,
    'Icon-App-60x60@2x.png': 120,
    'Icon-App-60x60@3x.png': 180,
    'Icon-App-76x76@1x.png': 76,
    'Icon-App-76x76@2x.png': 152,
    'Icon-App-83.5x83.5@2x.png': 167,
    'Icon-App-1024x1024@1x.png': 1024,
}


def star(draw: ImageDraw.ImageDraw, center: tuple[float, float], radius: float,
         fill: tuple[int, int, int]) -> None:
    points = []
    for index in range(10):
        angle = -math.pi / 2 + index * math.pi / 5
        length = radius if index % 2 == 0 else radius * 0.45
        points.append(
            (
                center[0] + math.cos(angle) * length,
                center[1] + math.sin(angle) * length,
            )
        )
    draw.polygon(points, fill=fill)


def chip(image: Image.Image, center: tuple[float, float], radius: float,
         color: tuple[int, int, int]) -> None:
    draw = ImageDraw.Draw(image)
    box = [
        center[0] - radius,
        center[1] - radius,
        center[0] + radius,
        center[1] + radius,
    ]
    draw.ellipse(box, fill=color, outline=WHITE, width=max(2, int(radius * 0.12)))
    inner = radius * 0.34
    draw.ellipse(
        [
            center[0] - inner,
            center[1] - inner,
            center[0] + inner,
            center[1] + inner,
        ],
        fill=WHITE,
    )


def render(size: int) -> Image.Image:
    """Рисует иконку в четыре раза крупнее и уменьшает — так края гладкие."""
    scale = 4
    side = size * scale
    image = Image.new('RGBA', (side, side), CREAM + (255,))

    # Тень и подложка доски лежат на отдельном слое: слой поворачивается целиком.
    layer = Image.new('RGBA', (side, side), (0, 0, 0, 0))
    draw = ImageDraw.Draw(layer)
    board = side * 0.66
    left = (side - board) / 2
    radius = board * 0.20
    draw.rounded_rectangle(
        [left, left + board * 0.05, left + board, left + board * 1.05],
        radius=radius,
        fill=WOOD_LIGHT + (255,),
    )
    draw.rounded_rectangle(
        [left, left, left + board, left + board],
        radius=radius,
        fill=WOOD + (255,),
    )
    # Сетка 4×4 внутри подложки, обрезанная по её скруглённым углам.
    inset = board * 0.07
    inner = board - inset * 2
    cell = inner / 4
    grid = Image.new('RGBA', (side, side), (0, 0, 0, 0))
    grid_draw = ImageDraw.Draw(grid)
    for row in range(4):
        for column in range(4):
            color = BOARD_LIGHT if (row + column) % 2 == 0 else BOARD_DARK
            grid_draw.rectangle(
                [
                    left + inset + column * cell,
                    left + inset + row * cell,
                    left + inset + (column + 1) * cell,
                    left + inset + (row + 1) * cell,
                ],
                fill=color + (255,),
            )
    mask = Image.new('L', (side, side), 0)
    ImageDraw.Draw(mask).rounded_rectangle(
        [left + inset, left + inset, left + board - inset, left + board - inset],
        radius=radius - inset,
        fill=255,
    )
    layer.paste(grid, mask=mask)
    layer = layer.rotate(-9, resample=Image.BICUBIC, center=(side / 2, side / 2))
    image = Image.alpha_composite(image, layer)

    # Два жетона поверх доски, как в логотипе главного окна.
    chip(image, (side * 0.30, side * 0.40), side * 0.115, PURPLE)
    chip(image, (side * 0.70, side * 0.66), side * 0.125, YELLOW)

    # Звёздочка в правом верхнем углу.
    draw = ImageDraw.Draw(image)
    star(draw, (side * 0.80, side * 0.22), side * 0.085, GOLD)

    return image.resize((size, size), Image.LANCZOS)


def main() -> None:
    big = render(1024)
    flat = Image.new('RGB', big.size, CREAM)
    flat.paste(big, mask=big.split()[3])

    for folder, size in ANDROID_SIZES.items():
        target = ROOT / 'android/app/src/main/res' / folder / 'ic_launcher.png'
        target.parent.mkdir(parents=True, exist_ok=True)
        render(size).save(target)

    icons = ROOT / 'ios/Runner/Assets.xcassets/AppIcon.appiconset'
    for name, size in IOS_SIZES.items():
        if size == 1024:
            flat.save(icons / name)
        else:
            icon = render(size)
            opaque = Image.new('RGB', icon.size, CREAM)
            opaque.paste(icon, mask=icon.split()[3])
            opaque.save(icons / name)

    print('Иконки обновлены: Android', len(ANDROID_SIZES),
          'размеров, iOS', len(IOS_SIZES), 'файлов')


if __name__ == '__main__':
    main()
