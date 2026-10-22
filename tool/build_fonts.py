#!/usr/bin/env python3
"""Regenerate the bundled fonts in assets/fonts/.

    pip install fonttools skia-pathops
    python3 tool/build_fonts.py

KashU ships Quicksand and Plus Jakarta Sans inside the app so nothing is
fetched from Google at runtime (offline first launch, and the privacy policy
promises the network is only used for prices). google/fonts publishes both
families as variable fonts only, so this downloads them from a pinned
google/fonts commit and cuts one static TTF per weight/style the app uses.

Adding a weight: add it below, rerun, and declare it under `fonts:` in
pubspec.yaml (test/core/theme/bundled_fonts_test.dart checks the two agree).
"""
import io
import pathlib
import urllib.parse
import urllib.request

from fontTools.ttLib import TTFont
from fontTools.varLib.instancer import OverlapMode, instantiateVariableFont

COMMIT = "45e3d5269e4a17d823f6d84470bc084dc5ae46f6"  # google/fonts, 2026-10-21
RAW = f"https://raw.githubusercontent.com/google/fonts/{COMMIT}/ofl"
OUT = pathlib.Path(__file__).resolve().parent.parent / "assets" / "fonts"

# google/fonts dir -> (assets/fonts subdir, {variable file: [(wght, name)]})
FAMILIES = {
    "quicksand": ("quicksand", {
        "Quicksand[wght].ttf": [(700, "Quicksand-Bold")],
    }),
    "plusjakartasans": ("plus_jakarta_sans", {
        "PlusJakartaSans[wght].ttf": [
            (500, "PlusJakartaSans-Medium"),
            (600, "PlusJakartaSans-SemiBold"),
            (700, "PlusJakartaSans-Bold"),
            (800, "PlusJakartaSans-ExtraBold"),
        ],
        "PlusJakartaSans-Italic[wght].ttf": [
            (500, "PlusJakartaSans-MediumItalic"),
        ],
    }),
}


def fetch(path):
    url = f"{RAW}/{urllib.parse.quote(path)}"
    with urllib.request.urlopen(url) as response:
        return response.read()


def main():
    for src_dir, (out_dir, variable_files) in FAMILIES.items():
        dest = OUT / out_dir
        dest.mkdir(parents=True, exist_ok=True)
        (dest / "OFL.txt").write_bytes(fetch(f"{src_dir}/OFL.txt"))
        for variable_file, instances in variable_files.items():
            data = fetch(f"{src_dir}/{variable_file}")
            for weight, name in instances:
                font = TTFont(io.BytesIO(data))
                static = instantiateVariableFont(
                    font, {"wght": weight}, static=True,
                    overlap=OverlapMode.REMOVE, updateFontNames=True)
                static.recalcTimestamp = False  # reproducible output
                static.save(dest / f"{name}.ttf")
                print(f"{out_dir}/{name}.ttf  wght={weight}")


if __name__ == "__main__":
    main()
