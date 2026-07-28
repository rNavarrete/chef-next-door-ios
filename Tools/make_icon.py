#!/usr/bin/env python3
"""Build the app icon from the chef illustration.

    python3 Tools/make_icon.py

Replaces Tools/MakeIcon.swift, which drew a burger in CoreGraphics back when the
app was called Lit Kitchen. There is real artwork now, so the icon is a crop of
it rather than a second drawing that has to be kept in sync with the first.

## Why a crop and not the whole figure

An icon is a ~60pt object. The full running chef — accents, motion lines, pot,
legs — turns to mush at that size; the generator it replaces said as much in its
own comments. Head, hat and ponytail survive, and the ponytail is worth keeping
because it is the only part that still says *running*.

The crop box is hand-read off a coordinate grid rather than found by colour
masks. Masking was tried: "white" catches the jacket as well as the hat, and
"skin" catches her hands, so every automatic box swallowed the whole torso.

## Opaque on purpose

The App Store rejects an icon with an alpha channel, so the figure is composited
onto a marigold ground and saved as RGB. The ground is allowed to be the brand
colour here for the reason the old generator gave: it is the one surface with no
interface on it, so nothing has to stay legible against it.
"""

from pathlib import Path
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parent.parent
SOURCE = ROOT / "Sources/LitKitchen/Assets.xcassets/ChefRunning.imageset/chef-running.png"
OUT = ROOT / "Sources/LitKitchen/Assets.xcassets/AppIcon.appiconset/icon-1024.png"

# Read off the grid in the 994px source: hat crown y≈40, ponytail out to x≈165,
# chin y≈490, face right edge x≈700.
CROP = (152, 5, 712, 565)

SIDE = 1024
GROUND_TOP = (0xE8, 0x99, 0x1E)
GROUND_BOTTOM = (0xC9, 0x7A, 0x0C)
FIGURE_SCALE = 0.90
FIGURE_TOP = 0.06


def main() -> None:
    src = Image.open(SOURCE).convert("RGBA")
    crop = src.crop(CROP)

    icon = Image.new("RGB", (SIDE, SIDE))
    draw = ImageDraw.Draw(icon)
    for y in range(SIDE):
        t = y / SIDE
        draw.line(
            [(0, y), (SIDE, y)],
            fill=tuple(
                int(GROUND_TOP[i] + (GROUND_BOTTOM[i] - GROUND_TOP[i]) * t)
                for i in range(3)
            ),
        )

    size = int(SIDE * FIGURE_SCALE)
    figure = crop.resize((size, size), Image.LANCZOS)
    icon.paste(figure, ((SIDE - size) // 2, int(SIDE * FIGURE_TOP)), figure)

    assert icon.mode == "RGB", "icon must not carry an alpha channel"
    icon.save(OUT)
    print(f"wrote {OUT.relative_to(ROOT)} ({icon.size[0]}x{icon.size[1]}, {icon.mode})")


if __name__ == "__main__":
    main()
