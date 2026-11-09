#!/usr/bin/env python3
"""Composes Blender icon renders (transparent PNG) onto branded backgrounds and writes every size
Google Play and Godot's Android export need.

python tools/compose_icons.py
Outputs per app into store/<app>/ and apps/<app>/ (icon.png + android launcher icons).
"""
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parent.parent
RENDERS = ROOT / "store" / "_renders"

APPS = {
    "foldshift": {"fg": "foldshift_fg.png", "inner": (255, 236, 214), "outer": (232, 96, 76)},
    "paperverse": {"fg": "paperverse_fg.png", "inner": (226, 233, 255), "outer": (58, 72, 176)},
}


def background(size: int, inner, outer) -> Image.Image:
    img = Image.new("RGB", (size, size), outer)
    d = ImageDraw.Draw(img)
    steps = 120
    for i in range(steps):
        t = i / steps
        r = int(size * 0.95 * (1 - t))
        c = tuple(int(outer[k] + (inner[k] - outer[k]) * (t ** 1.4)) for k in range(3))
        cx, cy = size * 0.5, size * 0.42
        d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=c)
    img = img.filter(ImageFilter.GaussianBlur(size / 60))
    # Subtle paper fold lines across the background.
    over = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    od = ImageDraw.Draw(over)
    od.polygon([(0, 0), (size, 0), (0, size)], fill=(255, 255, 255, 14))
    od.line([(size, 0), (0, size)], fill=(255, 255, 255, 40), width=max(1, size // 256))
    return Image.alpha_composite(img.convert("RGBA"), over)


def fit(fg: Image.Image, size: int, fill: float) -> Image.Image:
    bbox = fg.getbbox()
    crop = fg.crop(bbox)
    scale = fill * size / max(crop.size)
    crop = crop.resize((int(crop.width * scale), int(crop.height * scale)), Image.LANCZOS)
    canvas = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    # Soft contact shadow under the subject.
    shadow = Image.new("RGBA", crop.size, (0, 0, 0, 0))
    shadow.putalpha(crop.split()[3].point(lambda a: int(a * 0.28)))
    shadow = shadow.filter(ImageFilter.GaussianBlur(size / 90))
    ox = (size - crop.width) // 2
    oy = int((size - crop.height) * 0.56)
    canvas.alpha_composite(shadow, (ox + size // 80, oy + size // 50))
    canvas.alpha_composite(crop, (ox, oy))
    return canvas


def rounded_mask(size: int, radius: float) -> Image.Image:
    m = Image.new("L", (size, size), 0)
    ImageDraw.Draw(m).rounded_rectangle([0, 0, size - 1, size - 1], radius=int(size * radius), fill=255)
    return m


def main() -> None:
    for app, cfg in APPS.items():
        src = RENDERS / cfg["fg"]
        if not src.exists():
            print(f"skip {app}: {src} missing")
            continue
        fg = Image.open(src).convert("RGBA")
        store = ROOT / "store" / app
        store.mkdir(parents=True, exist_ok=True)
        app_dir = ROOT / "apps" / app
        icons = app_dir / "assets" / "icons"
        icons.mkdir(parents=True, exist_ok=True)
        # Play Store icon: full bleed 512 (Play applies its own mask).
        big = background(1024, cfg["inner"], cfg["outer"])
        big.alpha_composite(fit(fg, 1024, 0.86))
        big.convert("RGB").resize((512, 512), Image.LANCZOS).save(store / "icon_512.png")
        # Godot project icon / legacy launcher icon with rounded corners.
        rounded = big.copy()
        rounded.putalpha(rounded_mask(1024, 0.22))
        rounded.resize((256, 256), Image.LANCZOS).save(app_dir / "icon.png")
        rounded.resize((192, 192), Image.LANCZOS).save(icons / "main_192.png")
        # Adaptive icon layers (432 px): foreground inside the 66 % safe zone, background full bleed.
        fg_layer = fit(fg, 432, 0.6)
        fg_layer.save(icons / "adaptive_fg_432.png")
        background(432, cfg["inner"], cfg["outer"]).convert("RGB").save(icons / "adaptive_bg_432.png")
        # Monochrome layer for Android 13 themed icons.
        mono = Image.new("RGBA", (432, 432), (0, 0, 0, 0))
        alpha = fg_layer.split()[3]
        mono.paste((255, 255, 255, 255), (0, 0), alpha)
        mono.save(icons / "monochrome_432.png")
        print(f"{app}: icons written")


if __name__ == "__main__":
    main()
