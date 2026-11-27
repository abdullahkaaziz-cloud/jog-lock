"""Cut the app's three Archivo fonts from Google's variable Archivo.

Archivo is licensed under the SIL Open Font License 1.1 (no reserved font
name), which allows instances like these. Google ships it only as a variable
font, so this fixes the width and weight the design uses and renames the
result "Archivo Track" so iOS can load each style by its PostScript name.

    pip install fonttools
    python3 Tools/fonts/make_fonts.py VARIABLE_FONT_DIR JogLockTracker/Fonts

VARIABLE_FONT_DIR holds Archivo[wdth,wght].ttf and Archivo-Italic[wdth,wght].ttf
from https://github.com/google/fonts/tree/main/ofl/archivo.

The Live Activity carries its own copies of the Display and Heading cuts:
copy them, with OFL.txt, into JogLockWidgets/Fonts after making them.
"""

import sys
from pathlib import Path

from fontTools.ttLib import TTFont
from fontTools.varLib import instancer

FAMILY = "Archivo Track"

# (variable font, axis values, style name, output file)
CUTS = [
    ("Archivo[wdth,wght].ttf", {"wdth": 122, "wght": 900}, "Display", "ArchivoTrack-Display.ttf"),
    ("Archivo-Italic[wdth,wght].ttf", {"wdth": 122, "wght": 900}, "Display Italic", "ArchivoTrack-DisplayItalic.ttf"),
    ("Archivo[wdth,wght].ttf", {"wdth": 112, "wght": 800}, "Heading", "ArchivoTrack-Heading.ttf"),
]

# Name IDs: family, subfamily, unique ID, full name, PostScript name,
# typographic family, typographic subfamily, variations PostScript prefix.
NAME_IDS = (1, 2, 3, 4, 6, 16, 17, 25)


def find(source_dir: Path, name: str) -> Path:
    """The variable font, saved either with brackets or URL-escaped."""
    for candidate in (name, name.replace("[", "%5B").replace("]", "%5D")):
        path = source_dir / candidate
        if path.exists():
            return path
    raise SystemExit(f"missing {name} in {source_dir}")


def rename(font: TTFont, style: str) -> str:
    postscript = "ArchivoTrack-" + style.replace(" ", "")
    names = font["name"]
    for record in list(names.names):
        if record.nameID in NAME_IDS:
            names.removeNames(nameID=record.nameID)
    for platform, encoding, language in ((3, 1, 0x409), (1, 0, 0)):
        names.setName(f"{FAMILY} {style}", 1, platform, encoding, language)
        names.setName("Regular", 2, platform, encoding, language)
        names.setName(f"{postscript};cut-from-Archivo", 3, platform, encoding, language)
        names.setName(f"{FAMILY} {style}", 4, platform, encoding, language)
        names.setName(postscript, 6, platform, encoding, language)
        names.setName(FAMILY, 16, platform, encoding, language)
        names.setName(style, 17, platform, encoding, language)
    if "STAT" in font:
        del font["STAT"]
    return postscript


def main() -> None:
    if len(sys.argv) != 3:
        raise SystemExit(__doc__)
    source_dir, out_dir = Path(sys.argv[1]), Path(sys.argv[2])
    out_dir.mkdir(parents=True, exist_ok=True)
    for source, axes, style, filename in CUTS:
        font = instancer.instantiateVariableFont(TTFont(find(source_dir, source)), axes)
        postscript = rename(font, style)
        font.save(out_dir / filename)
        print(f"{filename}: {postscript}, {(out_dir / filename).stat().st_size} bytes")


if __name__ == "__main__":
    main()
