#!/usr/bin/env python3
"""Builds the mascot's sprite atlases (Resources/Dragon) from "Dragon - Fully Animated" by Cethiel (CC0), with
the flame of "Lots of game effects" (Fire01.png, CC0) for its breath.

The originals are not in the repo. Download and unzip https://opengameart.org/content/dragon-fully-animated
(137 MB, 60 fps, 725 x 445) and get Fire01.png from https://opengameart.org/node/52692, then:

    python3 scripts/make-dragon-atlas.py "<folder>/Dragon - Fully Animated" "<folder>/Fire01.png"

Needs Pillow. Every animation is cut to the same box (so the dragon stands on the same spot in all of them),
halved to 30 fps, scaled to 2x the largest size it is shown at, recoloured (black scales; the belly, horns,
claws and eyes keep their colour), turned to face right, and packed into one grid per animation. "done" is wider
than the rest: the flame leaves the frame on the right. dragon.json describes the grids.
"""
import json
import os
import sys

from PIL import Image, ImageChops

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
    "done": ("Attack 1", 1, 161, False),       # draws back, then breathes fire, once
    "flourish": ("Attack 2", 1, 202, False),   # rears up and strikes: now and then while idle
    "sleep": ("Death", 127, 301, False),       # lies down and settles; played backwards to wake
}
GAMMA, GAIN = 0.75, 1.15
# The body: this much of its colour removed, then darkened (gamma) and tinted a little cold.
DESATURATE, BODY_GAMMA, BODY_TINT = 0.85, 1.15, (0.92, 0.94, 1.0)
# The flame: on between these source frames of "done", fading in and out over RAMP frames; it runs EXTRA pixels
# past the dragon's box.
FIRE_ON, FIRE_OFF, RAMP, EXTRA, FLAME = 58, 104, 8, 80, 96


def lut(f):
    return [max(0, min(255, int(f(i / 255) * 255))) for i in range(256)]


def smooth(lo, hi):
    def f(v):
        x = max(0.0, min(1.0, (v * 255 - lo) / (hi - lo)))
        return x * x * (3 - 2 * x)
    return lut(f)


def tone(image):
    """Lifts the render (it is very dark), then turns the scales black. Light parts (belly, horns, claws) and the
    eyes keep their colour."""
    table = lut(lambda v: (v ** GAMMA) * GAIN)
    r, g, b, alpha = image.split()
    rgb = Image.merge("RGB", (r.point(table), g.point(table), b.point(table)))
    grey = rgb.convert("L")
    body = Image.blend(rgb, Image.merge("RGB", (grey, grey, grey)), DESATURATE)
    body = Image.merge("RGB", tuple(c.point(lut(lambda v, k=k: (v ** BODY_GAMMA) * k)) for c, k in zip(body.split(), BODY_TINT)))
    _, s, v = rgb.convert("HSV").split()
    eye = ImageChops.multiply(s.point(smooth(150, 200)), v.point(smooth(120, 170)))
    out = Image.composite(rgb, body, ImageChops.lighter(v.point(smooth(120, 185)), eye)).convert("RGBA")
    out.putalpha(alpha)
    return out


def flames(path):
    """The 32 frames of the flame, lying on their side: base on the left, tongue to the right."""
    sheet = Image.open(path).convert("RGBA")
    cells = [sheet.crop((c * 128, r * 256, c * 128 + 128, r * 256 + 256)) for r in range(4) for c in range(8)]
    box = [128, 256, 0, 0]
    for cell in cells:
        l, t, r, b = cell.getbbox()
        box = [min(box[0], l), min(box[1], t), max(box[2], r), max(box[3], b)]
    return [cell.crop(tuple(box)).rotate(-90, expand=True) for cell in cells]


def breathe(frame, flame, strength):
    """The frame, EXTRA wider, with the flame at the snout (the dragon's right-most point)."""
    canvas = Image.new("RGBA", (frame.width + EXTRA, frame.height), (0, 0, 0, 0))
    canvas.alpha_composite(frame, (0, 0))
    if strength <= 0:
        return canvas
    right = frame.getbbox()[2]
    tip = frame.crop((right - 4, 0, right, frame.height)).getbbox()
    length = max(1, round(FLAME * strength))
    flame = flame.resize((length, max(1, round(flame.height * length / flame.width))), Image.LANCZOS)
    canvas.alpha_composite(flame, (right - 5, max(0, (tip[1] + tip[3]) // 2 - flame.height // 2)))
    return canvas


def main(source, fire):
    os.makedirs(OUT, exist_ok=True)
    width = round((BOX[2] - BOX[0]) * HEIGHT / (BOX[3] - BOX[1]))
    manifest = {"frameWidth": width, "frameHeight": HEIGHT, "scale": 2, "animations": {}}
    flame = flames(fire)
    for name, (folder, first, last, loop) in ANIMATIONS.items():
        numbers = list(range(first, last + 1, 2))
        if not loop and numbers[-1] != last:
            numbers.append(last)
        frames = []
        for number in numbers:
            image = Image.open(os.path.join(source, folder, f"{number:03d}.png")).convert("RGBA").crop(BOX)
            image = tone(image.resize((width, HEIGHT), Image.LANCZOS)).transpose(Image.FLIP_LEFT_RIGHT)
            if name == "done":
                strength = min(1.0, (number - FIRE_ON) / RAMP, (FIRE_OFF - number) / RAMP)
                image = breathe(image, flame[len(frames) % len(flame)], strength)
            frames.append(image)
        cell = frames[0].width
        columns = 1
        while columns * columns < len(frames):
            columns += 1
        rows = (len(frames) + columns - 1) // columns
        atlas = Image.new("RGBA", (columns * cell, rows * HEIGHT), (0, 0, 0, 0))
        for index, frame in enumerate(frames):
            atlas.paste(frame, ((index % columns) * cell, (index // columns) * HEIGHT))
        # 256 colours with alpha: the dragon is a handful of greys and bone, and this cuts the files to about a third.
        atlas = atlas.quantize(colors=256, method=Image.FASTOCTREE, dither=Image.NONE)
        file = f"{name}.png"
        atlas.save(os.path.join(OUT, file), optimize=True)
        manifest["animations"][name] = {"file": file, "columns": columns, "rows": rows, "frames": len(frames),
                                        "fps": FPS, "loop": loop}
        if cell != width:
            manifest["animations"][name]["frameWidth"] = cell
        print(name, len(frames), "frames", f"{columns}x{rows}", os.path.getsize(os.path.join(OUT, file)) // 1024, "KB")
    with open(os.path.join(OUT, "dragon.json"), "w") as out:
        json.dump(manifest, out, indent=2)
        out.write("\n")


if __name__ == "__main__":
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    main(sys.argv[1], sys.argv[2])
