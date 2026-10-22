#!/usr/bin/env python3
"""Regenerate the bundled fonts in assets/fonts/.

    pip install fonttools skia-pathops
    python3 tool/build_fonts.py

KashU ships Quicksand and Plus Jakarta Sans inside the app so nothing is
fetched from Google at runtime (offline first launch, and the privacy policy
promises the network is only used for prices).

Quicksand's licence reserves the name "Quicksand", and a static instance we
cut ourselves would be a Modified Version that may not carry it. So Quicksand
is copied byte for byte from the official static build its own project
publishes (pinned commit below). Plus Jakarta Sans reserves no name; google/fonts
ships it as a variable font only, so one static TTF per weight/style the app
uses is cut from a pinned google/fonts commit.

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

# andrew-paglinawan/QuicksandFamily, 2026-10-22: official static builds.
QUICKSAND_COMMIT = "be4b9d638e1c79fa42d4a0ab0aa7fe29466419c7"
QUICKSAND_RAW = (
    "https://raw.githubusercontent.com/andrew-paglinawan/QuicksandFamily/"
    f"{QUICKSAND_COMMIT}/fonts")
QUICKSAND_STATICS = ["Quicksand-Bold"]

# google/fonts dir -> (assets/fonts subdir, {variable file: [(wght, name)]})
FAMILIES = {
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


def fetch(path, base=RAW):
    url = f"{base}/{urllib.parse.quote(path)}"
    with urllib.request.urlopen(url) as response:
        return response.read()


def main():
    dest = OUT / "quicksand"
    dest.mkdir(parents=True, exist_ok=True)
    (dest / "OFL.txt").write_bytes(fetch("OFL.txt", QUICKSAND_RAW))
    for name in QUICKSAND_STATICS:
        (dest / f"{name}.ttf").write_bytes(
            fetch(f"statics/{name}.ttf", QUICKSAND_RAW))
        print(f"quicksand/{name}.ttf  (upstream static, unmodified)")

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
