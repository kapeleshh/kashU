#!/usr/bin/env python3
"""Generate the Google Play listing graphics from the app icon's design tokens.

    python3 tool/generate_store_assets.py

Writes store/play/icon-512.png (Play's hi-res icon) and
store/play/feature-graphic-1024x500.png. Both reuse the gradient and coin from
tool/generate_app_icon.py so the listing cannot drift from the shipped icon.

Requires Pillow and fontTools.
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from PIL import Image, ImageDraw, ImageFilter  # noqa: E402
from generate_app_icon import (  # noqa: E402
    INDIGO, LAVENDER, GOLD_HI, GOLD_LO, GLYPH,
    linear_gradient, radial_gradient, pick_font,
)

OUT = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
                   "store", "play")


def _coin(d):
    """A gold coin of diameter d, as an RGBA tile with its own alpha mask."""
    coin = radial_gradient(d, GOLD_HI, GOLD_LO).convert("RGBA")
    mask = Image.new("L", (d, d), 0)
    ImageDraw.Draw(mask).ellipse((0, 0, d - 1, d - 1), fill=255)
    coin.putalpha(mask)
    rim = ImageDraw.Draw(coin)
    inset = int(d * 0.055)
    rim.ellipse((inset, inset, d - 1 - inset, d - 1 - inset),
                outline=(0xD9, 0x7A, 0x06, 160), width=max(2, int(d * 0.022)))
    return coin


def _draw_coin_with_glyph(canvas, cx, cy, d, font_path, font_idx):
    """Paste a coin centred at (cx, cy) with the rupee sign on it."""
    from PIL import ImageFont
    shadow = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    ImageDraw.Draw(shadow).ellipse(
        (cx - d // 2, cy - d // 2 + int(d * 0.07),
         cx + d // 2, cy + d // 2 + int(d * 0.07)),
        fill=(0x4A, 0x24, 0x00, 150))
    canvas.alpha_composite(shadow.filter(ImageFilter.GaussianBlur(d * 0.055)))

    coin = _coin(d)
    canvas.alpha_composite(coin, (cx - d // 2, cy - d // 2))

    layer = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    dl = ImageDraw.Draw(layer)
    font = ImageFont.truetype(font_path, int(d * 0.60), index=font_idx)
    l, t, r, b = dl.textbbox((0, 0), "₹", font=font)
    dl.text((cx - (l + r) / 2, cy - (t + b) / 2), "₹",
            font=font, fill=GLYPH + (255,))
    canvas.alpha_composite(layer)


def icon_512():
    """Play's hi-res icon. Same composition as the launcher icon."""
    from generate_app_icon import render
    tmp = os.path.join(OUT, ".tmp-master.png")
    render(out=tmp)
    Image.open(tmp).resize((512, 512), Image.LANCZOS).save(
        os.path.join(OUT, "icon-512.png"))
    os.remove(tmp)
    return "store/play/icon-512.png"


def feature_graphic():
    """1024x500 banner shown at the top of the Play listing."""
    from PIL import ImageFont
    W, H, SS = 1024, 500, 2
    font_path, font_idx = pick_font()

    canvas = linear_gradient(max(W, H) * SS, INDIGO, LAVENDER).convert("RGBA")
    canvas = canvas.crop((0, 0, W * SS, H * SS))

    _draw_coin_with_glyph(canvas, int(265 * SS), int(250 * SS), int(290 * SS),
                          font_path, font_idx)

    layer = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    dl = ImageDraw.Draw(layer)
    title = ImageFont.truetype(font_path, int(96 * SS), index=font_idx)
    sub = ImageFont.truetype(font_path, int(34 * SS), index=font_idx)
    dl.text((int(470 * SS), int(185 * SS)), "KashU", font=title,
            fill=(255, 255, 255, 255))
    dl.text((int(474 * SS), int(300 * SS)),
            "Track every investment. Privately.", font=sub,
            fill=(0xEC, 0xE9, 0xFF, 230))
    canvas.alpha_composite(layer)

    canvas.resize((W, H), Image.LANCZOS).convert("RGB").save(
        os.path.join(OUT, "feature-graphic-1024x500.png"))
    return "store/play/feature-graphic-1024x500.png"


if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    for f in (icon_512(), feature_graphic()):
        print("wrote", f)
