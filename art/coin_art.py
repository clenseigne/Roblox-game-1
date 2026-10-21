"""Draws the food coin as clean flat line art (transparent PNG).

Run:  python coin_art.py  ->  game/art/coin.png (512px) and game/previews/coin_art_preview.png
Drawn at 4x and downsampled for smooth antialiased lines.
"""
import math
import os

from PIL import Image, ImageDraw

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
OUT = 512
SS = 4
S = OUT * SS

INK = (58, 36, 22, 255)
GOLD_DARK = (247, 178, 40, 255)
GOLD = (255, 216, 74, 255)
GOLD_LIGHT = (255, 240, 160, 255)
TICK = (214, 140, 24, 255)
BUN = (236, 145, 58, 255)
BUN_LIGHT = (250, 190, 110, 255)
PATTY = (110, 58, 32, 255)
LETTUCE = (108, 203, 69, 255)
CHEESE = (255, 196, 40, 255)
SEED = (255, 247, 222, 255)
WHITE = (255, 255, 255, 255)


def p(v):
    """Design units (0..512) -> supersampled pixels."""
    return round(v * SS)


def pts(points):
    return [(p(x), p(y)) for x, y in points]


def box(cx, cy, rx, ry):
    return [p(cx - rx), p(cy - ry), p(cx + rx), p(cy + ry)]


def dome(cx, base_y, rx, ry, corner=10, steps=32):
    """Upper half-ellipse with a flat bottom and softly rounded bottom corners."""
    out = []
    for i in range(steps + 1):
        a = math.pi + math.pi * i / steps
        out.append((cx + rx * math.cos(a), base_y + ry * math.sin(a)))
    out += [(cx + rx, base_y + corner * 0.6), (cx + rx - corner, base_y + corner),
            (cx - rx + corner, base_y + corner), (cx - rx, base_y + corner * 0.6)]
    return out


def draw_burger(img, d, c, by, line):
    """Burger icon; by = vertical center of the stack."""
    top = by - 85
    # bottom bun
    d.rounded_rectangle([p(c - 100), p(top + 132), p(c + 100), p(top + 170)], radius=p(18),
                        fill=BUN, outline=INK, width=line)
    # patty
    d.rounded_rectangle([p(c - 110), p(top + 98), p(c + 110), p(top + 138)], radius=p(20),
                        fill=PATTY, outline=INK, width=line)
    # cheese with two drips
    d.polygon(pts([(c - 106, top + 88), (c + 106, top + 88), (c + 80, top + 104), (c + 52, top + 106),
                   (c + 40, top + 126), (c + 26, top + 106), (c - 34, top + 106), (c - 46, top + 120),
                   (c - 58, top + 104), (c - 86, top + 104)]),
              fill=CHEESE, outline=INK, width=line)
    # lettuce: ruffled band
    ruffle = [(c - 118, top + 66)]
    for i in range(13):
        x = c - 118 + 236 * i / 12
        ruffle.append((x, top + 92 + (8 if i % 2 else 0)))
    ruffle.append((c + 118, top + 66))
    d.polygon(pts(ruffle), fill=LETTUCE, outline=INK, width=line)
    # top bun dome
    d.polygon(pts(dome(c, top + 66, 114, 70, corner=12)), fill=BUN, outline=INK, width=line)
    d.arc(box(c - 34, top + 40, 58, 40), start=195, end=245, fill=BUN_LIGHT, width=p(11))
    # sesame seeds
    for sx, sy, ang in ((-52, 26, 25), (-10, 12, -5), (34, 22, -25), (70, 42, -45), (-82, 46, 40), (12, 40, 10)):
        w, h = p(30), p(17)
        seed = Image.new("RGBA", (w + p(8), h + p(8)), (0, 0, 0, 0))
        ImageDraw.Draw(seed).ellipse([p(4), p(4), p(4) + w, p(4) + h], fill=SEED, outline=INK, width=p(4))
        seed = seed.rotate(ang, expand=True, resample=Image.BICUBIC)
        img.alpha_composite(seed, (p(c + sx) - seed.width // 2, p(top + sy) - seed.height // 2))


def draw_coin():
    img = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    c = 256
    # soft shadow, outer band, inner face
    d.ellipse(box(c + 5, c + 9, 228, 228), fill=(58, 36, 22, 60))
    d.ellipse(box(c, c, 228, 228), fill=GOLD_DARK, outline=INK, width=p(13))
    for i in range(28):
        a = 2 * math.pi * i / 28
        d.line([p(c + 194 * math.cos(a)), p(c + 194 * math.sin(a)),
                p(c + 212 * math.cos(a)), p(c + 212 * math.sin(a))], fill=TICK, width=p(6))
    d.ellipse(box(c, c, 180, 180), fill=GOLD, outline=INK, width=p(8))
    d.arc(box(c, c, 156, 156), start=195, end=255, fill=GOLD_LIGHT, width=p(16))
    draw_burger(img, d, c, c + 6, p(8))
    # sparkle star
    sx, sy = c + 154, c - 154
    star = [(sx, sy - 36), (sx + 9, sy - 9), (sx + 36, sy), (sx + 9, sy + 9),
            (sx, sy + 36), (sx - 9, sy + 9), (sx - 36, sy), (sx - 9, sy - 9)]
    d.polygon(pts(star), fill=WHITE, outline=INK, width=p(6))
    return img.resize((OUT, OUT), Image.LANCZOS)


def main():
    coin = draw_coin()
    coin.save(os.path.join(HERE, "coin.png"))
    prev = Image.new("RGBA", (OUT * 2, OUT), (242, 178, 121, 255))
    prev.alpha_composite(coin, (0, 0))
    flip = coin.resize((OUT // 3, OUT), Image.LANCZOS)  # mid-spin frame
    prev.alpha_composite(flip, (OUT + OUT // 3, 0))
    os.makedirs(os.path.join(ROOT, "previews"), exist_ok=True)
    prev.convert("RGB").save(os.path.join(ROOT, "previews", "coin_art_preview.png"))


if __name__ == "__main__":
    main()
