"""Crisp LEGO-plate stud tile for the shop-style UI: transparent, tints any color it sits on.

Each stud is a raised circle: a dark crescent shadow below-left, a light rim above-right and a
slightly lighter top. Draws at 4x and downsamples for clean edges. Writes art/ui/stud_tile2.png
and a preview on a few panel colors (art/ui/stud2_preview.png).
"""
import os

from PIL import Image, ImageDraw

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "art", "ui")
SIZE, SS = 128, 4
S = SIZE * SS


def tile() -> Image.Image:
    im = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    c = S / 2
    r = S * 0.30
    off = S * 0.045
    # shadow crescent (offset down-left)
    d.ellipse((c - r - off, c - r + off, c + r - off, c + r + off), fill=(0, 0, 0, 70))
    # light rim (offset up-right)
    d.ellipse((c - r + off * 0.6, c - r - off * 0.6, c + r + off * 0.6, c + r - off * 0.6), fill=(255, 255, 255, 70))
    # the stud top
    d.ellipse((c - r, c - r, c + r, c + r), fill=(255, 255, 255, 28))
    # thin dark outline for the chunky graphic look
    d.ellipse((c - r, c - r, c + r, c + r), outline=(0, 0, 0, 60), width=int(SS * 2.5))
    return im.resize((SIZE, SIZE), Image.LANCZOS)


def main():
    t = tile()
    t.save(os.path.join(OUT, "stud_tile2.png"))
    colors = [(92, 214, 64), (128, 128, 128), (226, 40, 40), (92, 64, 44)]
    prev = Image.new("RGBA", (SIZE * 4, SIZE * len(colors) // 2 * 1), (0, 0, 0, 255))
    prev = Image.new("RGBA", (SIZE * 4, SIZE * 2), (0, 0, 0, 255))
    for i, col in enumerate(colors):
        block = Image.new("RGBA", (SIZE * 2, SIZE), col + (255,))
        for x in range(0, SIZE * 2, SIZE // 2):
            small = t.resize((SIZE // 2, SIZE // 2), Image.LANCZOS)
            for y in range(0, SIZE, SIZE // 2):
                block.alpha_composite(small, (x, y))
        prev.paste(block, ((i % 2) * SIZE * 2, (i // 2) * SIZE))
    prev.save(os.path.join(OUT, "stud2_preview.png"))
    print("ok")


if __name__ == "__main__":
    main()
