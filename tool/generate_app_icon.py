#!/usr/bin/env python3
"""Regenerate the KashU app icon: a gold rupee coin on the C-Soft gradient.

    python3 tool/generate_app_icon.py assets/images/app_icon.png

Writes a 1024x1024 master. To reinstall every platform size from that master,
see the icon commit — web/favicon.png, web/icons/*, android mipmap-*/ and
ios/Runner/Assets.xcassets/AppIcon.appiconset/ are all plain resizes of it,
except the maskable pair which is rendered with coin_scale=0.44 so Android's
circular crop does not shave the coin.

Requires Pillow and fontTools. The rupee sign (U+20B9) is rendered to pixels,
so the shipped assets carry no font dependency.
"""
from PIL import Image, ImageDraw, ImageFilter, ImageFont

# Brand tokens, lifted from lib/core/constants/app_colors.dart
INDIGO   = (0x63, 0x66, 0xF1)   # AppColors.primary
LAVENDER = (0xA7, 0x8B, 0xFA)   # AppColors.primaryLight
GOLD_HI  = (0xFC, 0xD3, 0x4D)   # CoinMascot radial start
GOLD_LO  = (0xF5, 0x9E, 0x0B)   # CoinMascot radial end
GLYPH    = (0x7C, 0x2D, 0x12)   # deep amber-brown, reads on gold

SS   = 2            # supersample factor
SIZE = 1024
W    = SIZE * SS


def pick_font():
    """First preference whose cmap genuinely maps U+20B9.

    Pillow's getmask() is not a usable test: a missing glyph renders as a
    .notdef box, which still has a bounding box. Arial Unicode fails this
    check despite the name; Flutter's bundled Roboto carries the glyph.
    """
    from fontTools.ttLib import TTFont
    import os, shutil
    prefs = []
    flutter = shutil.which("flutter")
    if flutter:
        fonts = os.path.join(
            os.path.dirname(os.path.dirname(os.path.realpath(flutter))),
            "bin", "cache", "artifacts", "material_fonts")
        prefs += [os.path.join(fonts, n)
                  for n in ("Roboto-Black.ttf", "Roboto-Bold.ttf")]
    prefs += ["/System/Library/Fonts/SFNSRounded.ttf"]
    for path in prefs:
        if not os.path.exists(path):
            continue
        try:
            f = TTFont(path, fontNumber=0, lazy=True)
            if any(0x20B9 in t.cmap for t in f["cmap"].tables):
                return path, 0
        except Exception:
            continue
    raise SystemExit("no font with a real rupee glyph")


def linear_gradient(size, c1, c2):
    """Diagonal gradient, computed small then scaled up (cheap and smooth)."""
    n = 128
    g = Image.new("RGB", (n, n))
    px = g.load()
    for y in range(n):
        for x in range(n):
            t = (x + y) / (2 * (n - 1))
            px[x, y] = tuple(round(a + (b - a) * t) for a, b in zip(c1, c2))
    return g.resize((size, size), Image.BICUBIC)


def radial_gradient(size, c1, c2, cx=-0.30, cy=-0.40, radius=0.95):
    """Off-centre radial highlight, mirroring CoinMascot's RadialGradient."""
    n = 160
    g = Image.new("RGB", (n, n))
    px = g.load()
    for y in range(n):
        for x in range(n):
            nx = (x / (n - 1)) * 2 - 1
            ny = (y / (n - 1)) * 2 - 1
            d = (((nx - cx) ** 2 + (ny - cy) ** 2) ** 0.5) / radius
            t = min(1.0, max(0.0, d))
            px[x, y] = tuple(round(a + (b - a) * t) for a, b in zip(c1, c2))
    return g.resize((size, size), Image.BICUBIC)


def render(coin_scale=0.62, out="icon.png"):
    font_path, font_idx = pick_font()
    img = linear_gradient(W, INDIGO, LAVENDER).convert("RGBA")

    d = int(W * coin_scale)                 # coin diameter
    cx = cy = W // 2
    box = (cx - d // 2, cy - d // 2, cx + d // 2, cy + d // 2)

    # Soft drop shadow under the coin (AppShadows.glow, in spirit)
    sh = Image.new("RGBA", (W, W), (0, 0, 0, 0))
    ImageDraw.Draw(sh).ellipse(
        (box[0], box[1] + int(d * 0.07), box[2], box[3] + int(d * 0.07)),
        fill=(0x4A, 0x24, 0x00, 150),
    )
    sh = sh.filter(ImageFilter.GaussianBlur(d * 0.055))
    img = Image.alpha_composite(img, sh)

    # Coin face
    coin = radial_gradient(d, GOLD_HI, GOLD_LO).convert("RGBA")
    mask = Image.new("L", (d, d), 0)
    ImageDraw.Draw(mask).ellipse((0, 0, d - 1, d - 1), fill=255)
    img.paste(coin, box[:2], mask)

    # Inner rim, a touch darker than the coin's low tone
    rim = Image.new("RGBA", (W, W), (0, 0, 0, 0))
    inset = int(d * 0.055)
    ImageDraw.Draw(rim).ellipse(
        (box[0] + inset, box[1] + inset, box[2] - inset, box[3] - inset),
        outline=(0xD9, 0x7A, 0x06, 160), width=max(2, int(d * 0.022)),
    )
    img = Image.alpha_composite(img, rim)

    # ₹
    layer = Image.new("RGBA", (W, W), (0, 0, 0, 0))
    dl = ImageDraw.Draw(layer)
    fs = int(d * 0.60)
    font = ImageFont.truetype(font_path, fs, index=font_idx)
    l, t, r, b = dl.textbbox((0, 0), "₹", font=font)
    dl.text((cx - (l + r) / 2, cy - (t + b) / 2), "₹", font=font, fill=GLYPH + (255,))
    img = Image.alpha_composite(img, layer)

    img.resize((SIZE, SIZE), Image.LANCZOS).convert("RGB").save(out)
    return font_path


if __name__ == "__main__":
    import sys
    p = render(out=sys.argv[1] if len(sys.argv) > 1 else "icon.png")
    print("font used:", p)
