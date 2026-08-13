#!/usr/bin/env python3
"""Generate 1-bit thermal-friendly mana symbol PNGs."""

from __future__ import annotations

import math
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

OUT = Path(__file__).resolve().parents[1] / "assets" / "mana"
SIZE = 64
BLACK = 0
WHITE = 255


def font(size: int) -> ImageFont.FreeTypeFont:
    for path in (
        "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf",
        "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf",
    ):
        try:
            return ImageFont.truetype(path, size=size)
        except OSError:
            continue
    return ImageFont.load_default()


def new_image() -> Image.Image:
    return Image.new("1", (SIZE, SIZE), WHITE)


def circle(draw: ImageDraw.ImageDraw, fill: int, outline: int | None = BLACK) -> None:
    inset = 1
    draw.ellipse((inset, inset, SIZE - 1 - inset, SIZE - 1 - inset), fill=fill, outline=outline)


def draw_centered_text(
    img: Image.Image, text: str, fill: int, max_size: int = 38
) -> None:
    draw = ImageDraw.Draw(img)
    size = max_size
    while size >= 10:
        f = font(size)
        bbox = draw.textbbox((0, 0), text, font=f)
        w, h = bbox[2] - bbox[0], bbox[3] - bbox[1]
        if w <= SIZE - 10 and h <= SIZE - 10:
            x = (SIZE - w) / 2 - bbox[0]
            y = (SIZE - h) / 2 - bbox[1]
            draw.text((x, y), text, font=f, fill=fill)
            return
        size -= 2
    f = font(10)
    bbox = draw.textbbox((0, 0), text, font=f)
    w, h = bbox[2] - bbox[0], bbox[3] - bbox[1]
    draw.text(((SIZE - w) / 2 - bbox[0], (SIZE - h) / 2 - bbox[1]), text, font=f, fill=fill)


def save(img: Image.Image, code: str) -> None:
    name = code.replace("/", "_")
    img.save(OUT / f"{name}.png")


def generic(text: str, code: str | None = None) -> None:
    img = new_image()
    draw = ImageDraw.Draw(img)
    circle(draw, BLACK)
    draw_centered_text(img, text, WHITE, 36 if len(text) <= 2 else 22)
    save(img, code or text)


def split_hybrid(left: str, right: str, code: str) -> None:
    img = new_image()
    draw = ImageDraw.Draw(img)
    circle(draw, WHITE, BLACK)
    # Diagonal split: top-left black, bottom-right white.
    mask = Image.new("1", (SIZE, SIZE), WHITE)
    md = ImageDraw.Draw(mask)
    md.polygon([(0, 0), (SIZE - 1, 0), (0, SIZE - 1)], fill=BLACK)
    black_half = Image.new("1", (SIZE, SIZE), WHITE)
    bd = ImageDraw.Draw(black_half)
    circle(bd, BLACK)
    img.paste(black_half, (0, 0), mask)

    left_img = Image.new("1", (SIZE, SIZE), WHITE)
    draw_centered_text(left_img, left, BLACK, 26)
    # Paint left glyph only on black half by inverting onto black.
    left_on_black = Image.new("1", (SIZE, SIZE), WHITE)
    ld = ImageDraw.Draw(left_on_black)
    circle(ld, BLACK)
    # White letter: wherever left_img is black, punch white.
    pixels = left_on_black.load()
    src = left_img.load()
    mpx = mask.load()
    for y in range(SIZE):
        for x in range(SIZE):
            if mpx[x, y] == BLACK and src[x, y] == BLACK:
                pixels[x, y] = WHITE
    img.paste(left_on_black, (0, 0), mask)

    right_img = Image.new("1", (SIZE, SIZE), WHITE)
    draw_centered_text(right_img, right, BLACK, 26)
    inv = Image.new("1", (SIZE, SIZE), WHITE)
    ip = inv.load()
    rp = right_img.load()
    for y in range(SIZE):
        for x in range(SIZE):
            if mpx[x, y] == WHITE and rp[x, y] == BLACK:
                ip[x, y] = BLACK
    img.paste(inv, (0, 0), inv)
    draw = ImageDraw.Draw(img)
    circle(draw, None, BLACK)  # type: ignore[arg-type]
    draw.line((SIZE - 2, 2, 2, SIZE - 2), fill=BLACK, width=2)
    save(img, code)


def phyrexian(letter: str, code: str) -> None:
    img = new_image()
    draw = ImageDraw.Draw(img)
    circle(draw, BLACK)
    # Phi-like mark: circle + vertical bar, optional color letter small.
    cx = cy = SIZE / 2
    r = 14
    draw.ellipse((cx - r, cy - r + 4, cx + r, cy + r + 4), outline=WHITE, width=3)
    draw.line((cx, 14, cx, SIZE - 10), fill=WHITE, width=3)
    if letter and letter != "P":
        f = font(14)
        draw.text((SIZE - 22, 6), letter, font=f, fill=WHITE)
    save(img, code)


def tap_symbol() -> None:
    img = new_image()
    draw = ImageDraw.Draw(img)
    circle(draw, BLACK)
    # Curved arrow (tap).
    bbox = (16, 16, 48, 48)
    draw.arc(bbox, start=200, end=80, fill=WHITE, width=5)
    # Arrowhead at ~80 degrees.
    ang = math.radians(80)
    cx, cy = 32, 32
    r = 16
    x = cx + r * math.cos(ang)
    y = cy + r * math.sin(ang)
    draw.polygon(
        [(x, y), (x - 8, y - 2), (x - 2, y + 8)],
        fill=WHITE,
    )
    save(img, "T")


def untap_symbol() -> None:
    img = new_image()
    draw = ImageDraw.Draw(img)
    circle(draw, BLACK)
    bbox = (16, 16, 48, 48)
    draw.arc(bbox, start=20, end=260, fill=WHITE, width=5)
    ang = math.radians(260)
    cx, cy = 32, 32
    r = 16
    x = cx + r * math.cos(ang)
    y = cy + r * math.sin(ang)
    draw.polygon([(x, y), (x + 8, y - 2), (x + 2, y + 8)], fill=WHITE)
    save(img, "Q")


def energy() -> None:
    img = new_image()
    draw = ImageDraw.Draw(img)
    circle(draw, BLACK)
    draw.polygon([(32, 10), (22, 34), (32, 34), (28, 54), (46, 28), (34, 28)], fill=WHITE)
    save(img, "E")


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)

    for code, label in [
        ("W", "W"),
        ("U", "U"),
        ("B", "B"),
        ("R", "R"),
        ("G", "G"),
        ("C", "C"),
        ("S", "S"),
        ("X", "X"),
        ("Y", "Y"),
        ("Z", "Z"),
        ("H", "H"),
        ("A", "A"),
        ("P", "P"),
        ("L", "L"),
        ("D", "D"),
    ]:
        generic(label, code)

    for n in list(range(0, 21)) + [100, 1000000]:
        generic(str(n), str(n))

    pairs = [
        ("W", "U"),
        ("W", "B"),
        ("U", "B"),
        ("U", "R"),
        ("B", "R"),
        ("B", "G"),
        ("R", "G"),
        ("R", "W"),
        ("G", "W"),
        ("G", "U"),
        ("C", "W"),
        ("C", "U"),
        ("C", "B"),
        ("C", "R"),
        ("C", "G"),
        ("B", "U"),
        ("G", "B"),
        ("R", "U"),
        ("W", "G"),
        ("U", "W"),
    ]
    seen: set[str] = set()
    for a, b in pairs:
        code = f"{a}/{b}"
        if code not in seen:
            split_hybrid(a, b, code)
            seen.add(code)

    for color in ("W", "U", "B", "R", "G", "C"):
        split_hybrid("2", color, f"2/{color}")
        phyrexian(color, f"{color}/P")

    phyrexian("", "P")
    tap_symbol()
    untap_symbol()
    energy()
    generic("PW", "PW")
    generic("∞", "INFINITY")
    generic("½", "1/2")
    generic("CHAOS", "CHAOS")
    print(f"wrote {len(list(OUT.glob('*.png')))} icons to {OUT}")


if __name__ == "__main__":
    main()
