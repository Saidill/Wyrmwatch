#!/usr/bin/env python3
"""Builds the mascot's sprite atlases (Resources/Dragon) from "Dragon - Fully Animated" by Cethiel (CC0).

The original frames (137 MB, 60 fps, 725 x 445) are not in the repo. Download and unzip
https://opengameart.org/content/dragon-fully-animated, then:

    python3 scripts/make-dragon-atlas.py "<folder>/Dragon - Fully Animated"

Needs Pillow. Every animation is cut to the same box (so the dragon stands on the same spot in all of them),
halved to 30 fps, scaled to 2x the largest size it is shown at, lifted a little (the render is very dark for a
black notch), turned to face right, and packed into one grid per animation. dragon.json describes the grids.
"""
import json
import os
import sys

from PIL import Image

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "Resources", "Dragon")
# One box around the dragon in every frame that is used (measured over all of them).
BOX = (108, 46, 708, 378)
HEIGHT = 96  # pixels: 2x the tallest the dragon is shown (48 pt)
FPS = 30
# name: (source folder, first frame, last frame (1-based, inclusive), loops)
ANIMATIONS = {
    "idle": ("Idle", 1, 160, True),            # 161 is the first frame again
    "working": ("Walking", 1, 161, True),
    "alert": ("Idle Battle", 1, 139, True),    # 140 is the first frame again
    "done": ("Attack 2", 1, 202, False),       # rears up and strikes, once
    "sleep": ("Death", 127, 301, False),       # lies down and settles; played backwards to wake
}
GAMMA, GAIN = 0.75, 1.15


def tone(image):
    lut = [min(255, int(255 * ((i / 255) ** GAMMA) * GAIN)) for i in range(256)]
    r, g, b, a = image.split()
    return Image.merge("RGBA", (r.point(lut), g.point(lut), b.point(lut), a))


def main(source):
    os.makedirs(OUT, exist_ok=True)
    width = round((BOX[2] - BOX[0]) * HEIGHT / (BOX[3] - BOX[1]))
    manifest = {"frameWidth": width, "frameHeight": HEIGHT, "scale": 2, "animations": {}}
    for name, (folder, first, last, loop) in ANIMATIONS.items():
        numbers = list(range(first, last + 1, 2))
        if not loop and numbers[-1] != last:
            numbers.append(last)
        frames = []
        for number in numbers:
            image = Image.open(os.path.join(source, folder, f"{number:03d}.png")).convert("RGBA").crop(BOX)
            image = tone(image.resize((width, HEIGHT), Image.LANCZOS)).transpose(Image.FLIP_LEFT_RIGHT)
            frames.append(image)
        columns = 1
        while columns * columns < len(frames):
            columns += 1
        rows = (len(frames) + columns - 1) // columns
        atlas = Image.new("RGBA", (columns * width, rows * HEIGHT), (0, 0, 0, 0))
        for index, frame in enumerate(frames):
            atlas.paste(frame, ((index % columns) * width, (index // columns) * HEIGHT))
        # 256 colours with alpha: the dragon is a handful of browns, and this cuts the files to about a third.
        atlas = atlas.quantize(colors=256, method=Image.FASTOCTREE, dither=Image.NONE)
        file = f"{name}.png"
        atlas.save(os.path.join(OUT, file), optimize=True)
        manifest["animations"][name] = {"file": file, "columns": columns, "rows": rows, "frames": len(frames),
                                        "fps": FPS, "loop": loop}
        print(name, len(frames), "frames", f"{columns}x{rows}", os.path.getsize(os.path.join(OUT, file)) // 1024, "KB")
    with open(os.path.join(OUT, "dragon.json"), "w") as out:
        json.dump(manifest, out, indent=2)
        out.write("\n")


if __name__ == "__main__":
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    main(sys.argv[1])
