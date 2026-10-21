"""Draws the burger sticker that goes on both faces of the 3D food coin (transparent PNG).

Run:  python coin_emblem.py  ->  game/art/coin_emblem.png (512px) + previews/coin_emblem_preview.png
Clean line art: thick ink outlines, flat fills, a cute face, and a white die-cut sticker border.
The burger fits inside the coin's gold face (the rim covers the outer ~20%).
"""
import math
import os

from PIL import Image, ImageDraw, ImageFilter

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
OUT = 512
SS = 4

INK = (58, 36, 22, 255)
BUN = (240, 150, 60, 255)
BUN_SHADE = (214, 118, 40, 255)
BUN_LIGHT = (255, 196, 120, 255)
PATTY = (112, 60, 34, 255)
PATTY_DARK = (80, 40, 22, 255)
LETTUCE = (112, 206, 72, 255)
CHEESE = (255, 200, 44, 255)
TOMATO = (232, 64, 52, 255)
SEED = (255, 247, 222, 255)
BLUSH = (255, 140, 160, 255)
WHITE = (255, 255, 255, 255)


def p(v):
    return round(v * SS)


def pts(points):
    return [(p(x), p(y)) for x, y in points]


def box(cx, cy, rx, ry):
    return [p(cx - rx), p(cy - ry), p(cx + rx), p(cy + ry)]


def draw_burger():
    img = Image.new("RGBA", (OUT * SS, OUT * SS), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    c = 256
    line = p(9)

    # layers drawn bottom-up; each one's visible strip sits below the layer drawn after it
    # bottom bun
    d.rounded_rectangle([p(c - 128), p(356), p(c + 128), p(402)], radius=p(22), fill=BUN, outline=INK, width=line)
    d.line([p(c - 104), p(390), p(c + 104), p(390)], fill=BUN_SHADE, width=p(6))
    # patty with grill marks
    d.rounded_rectangle([p(c - 144), p(316), p(c + 144), p(366)], radius=p(25), fill=PATTY, outline=INK, width=line)
    for x in (-80, -20, 40, 100):
        d.line([p(c + x - 14), p(352), p(c + x + 14), p(332)], fill=PATTY_DARK, width=p(6))
    # cheese with drips
    d.polygon(pts([(c - 140, 290), (c + 140, 290), (c + 140, 320), (c + 96, 320), (c + 80, 348), (c + 64, 320),
                   (c - 44, 320), (c - 62, 342), (c - 80, 320), (c - 140, 320)]),
              fill=CHEESE, outline=INK, width=line)
    # tomato slices
    for x in (-70, 70):
        d.chord(box(c + x, 292, 52, 18), start=0, end=180, fill=TOMATO, outline=INK, width=p(7))
    # lettuce: scalloped band
    ruffle = [(c - 154, 262)]
    steps = 16
    for i in range(steps + 1):
        x = c - 154 + 308 * i / steps
        ruffle.append((x, 284 + 13 * abs(math.sin(i * math.pi / 2))))
    ruffle.append((c + 154, 262))
    d.polygon(pts(ruffle), fill=LETTUCE, outline=INK, width=line)

    # top bun dome
    dome = []
    for i in range(41):
        a = math.pi + math.pi * i / 40
        dome.append((c + 150 * math.cos(a), 262 + 120 * math.sin(a)))
    dome += [(c + 150, 262), (c + 140, 272), (c - 140, 272), (c - 150, 262)]
    d.polygon(pts(dome), fill=BUN, outline=INK, width=line)
    d.arc(box(c - 30, 212, 92, 70), start=200, end=250, fill=BUN_LIGHT, width=p(14))

    # sesame seeds (kept off the face)
    for sx, sy, ang in ((-96, 196, 35), (-52, 166, 15), (0, 156, -5), (52, 166, -20), (98, 194, -40),
                        (-118, 236, 55), (122, 234, -60)):
        w, h = p(26), p(15)
        seed = Image.new("RGBA", (w + p(8), h + p(8)), (0, 0, 0, 0))
        ImageDraw.Draw(seed).ellipse([p(4), p(4), p(4) + w, p(4) + h], fill=SEED, outline=INK, width=p(4))
        seed = seed.rotate(ang, expand=True, resample=Image.BICUBIC)
        img.alpha_composite(seed, (p(c + sx) - seed.width // 2, p(sy) - seed.height // 2))

    # cute face on the bun
    for ex in (-34, 34):
        d.ellipse(box(c + ex, 218, 13, 17), fill=INK)
        d.ellipse(box(c + ex + 4, 211, 5, 5), fill=WHITE)
    d.arc(box(c, 232, 16, 13), start=20, end=160, fill=INK, width=p(6))
    for bx in (-66, 66):
        d.ellipse(box(c + bx, 240, 15, 8), fill=BLUSH)
    return img.resize((OUT, OUT), Image.LANCZOS)


def sticker(art, border=10, ink=2.5):
    """White die-cut border with a thin ink edge around the art's silhouette."""
    alpha = art.split()[3]

    def grow(radius):
        # round dilation: blur, hard threshold, then a hair of blur for antialiased edges
        blurred = alpha.filter(ImageFilter.GaussianBlur(radius))
        hard = blurred.point(lambda v: 255 if v > 10 else 0)
        return hard.filter(ImageFilter.GaussianBlur(0.8))

    out = Image.new("RGBA", art.size, (0, 0, 0, 0))
    out.paste(Image.new("RGBA", art.size, INK), (0, 0), grow(border + ink))
    out.paste(Image.new("RGBA", art.size, WHITE), (0, 0), grow(border))
    out.alpha_composite(art)
    return out


def main():
    art = sticker(draw_burger())
    # shrink into the middle so it sits inside the coin's rim
    canvas = Image.new("RGBA", (OUT, OUT), (0, 0, 0, 0))
    inner = art.resize((int(OUT * 0.78), int(OUT * 0.78)), Image.LANCZOS)
    canvas.alpha_composite(inner, ((OUT - inner.width) // 2, (OUT - inner.height) // 2 + 6))
    canvas.save(os.path.join(HERE, "coin_emblem.png"))

    prev = Image.new("RGBA", (OUT, OUT), (242, 178, 121, 255))
    gold = ImageDraw.Draw(prev)
    gold.ellipse([12, 12, OUT - 12, OUT - 12], fill=(247, 190, 42, 255), outline=INK, width=8)
    gold.ellipse([62, 62, OUT - 62, OUT - 62], fill=(255, 216, 74, 255))
    prev.alpha_composite(canvas)
    os.makedirs(os.path.join(ROOT, "previews"), exist_ok=True)
    prev.convert("RGB").save(os.path.join(ROOT, "previews", "coin_emblem_preview.png"))


if __name__ == "__main__":
    main()
