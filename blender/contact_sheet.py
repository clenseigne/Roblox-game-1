"""Tiles preview PNGs into one labeled sheet.  python contact_sheet.py out.png Name1 Name2 ..."""
import os
import sys

from PIL import Image, ImageDraw, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
PREVIEWS = os.path.join(os.path.dirname(HERE), "previews")


def main():
    out, names = sys.argv[1], sys.argv[2:]
    cell, cols = 400, 4
    rows = (len(names) + cols - 1) // cols
    sheet = Image.new("RGB", (cell * cols, (cell + 36) * rows), "white")
    draw = ImageDraw.Draw(sheet)
    try:
        font = ImageFont.truetype("arialbd.ttf", 26)
    except OSError:
        font = ImageFont.load_default()
    for i, name in enumerate(names):
        img = Image.open(os.path.join(PREVIEWS, f"{name}.png")).convert("RGB").resize((cell, cell))
        x, y = (i % cols) * cell, (i // cols) * (cell + 36)
        sheet.paste(img, (x, y + 36))
        draw.text((x + 10, y + 4), name, fill="black", font=font)
    sheet.save(os.path.join(PREVIEWS, out))


if __name__ == "__main__":
    main()
