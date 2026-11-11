#!/usr/bin/env python3
"""Composes the Blender hero renders into every icon, splash and store graphic both apps ship.

Pipeline (re-run both steps after changing a scene or a colour):

  "C:\\Program Files\\Blender Foundation\\Blender 4.5\\blender.exe" --background --factory-startup \
      --python pipeline/blender/render_icons.py -- apps/foldshift/assets/models store/_renders all
  python tools/compose_icons.py [--sheet _scratch/qa/icons_new.png]

Inputs: store/_renders/<app>_fg.png (transparent 1024 px hero renders from render_icons.py).
Outputs per app (paths are referenced by export_presets.cfg / the store listing, keep the names):

  store/<app>/icon_512.png                 Play Store icon, full bleed (Play applies its own mask)
  store/<app>/feature_graphic.png          1024x500 Play feature graphic: hero left, app name right
  apps/<app>/icon.png                      256 px rounded Godot project icon
  apps/<app>/assets/icons/main_192.png     legacy launcher icon (rounded square)
  apps/<app>/assets/icons/adaptive_fg_432.png  adaptive foreground: subject inside the 66 dp safe circle
  apps/<app>/assets/icons/adaptive_bg_432.png  adaptive background: full-bleed gradient + paper crease
  apps/<app>/assets/icons/monochrome_432.png   Android 13 themed icon: white silhouette with alpha
  apps/<app>/assets/splash/emblem.png      640 px transparent hero (soft shadow) for the splash screen

--sheet PATH also writes a QA contact sheet: icons at 512/192/96/48 px, adaptive previews through
circle / squircle / rounded-square launcher masks, the themed icon, the splash emblem and feature graphic.
"""
import argparse
import io
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = Path(__file__).resolve().parent.parent
RENDERS = ROOT / "store" / "_renders"
FONT = ROOT / "shared-core" / "addons" / "origamiverse_core" / "ui" / "fonts" / "Outfit-Variable.ttf"

# Adaptive icons: 108 dp layers, launchers show the central 72 dp, the 66 dp circle is always visible.
SAFE_RADIUS = 33 / 108

APPS = {
    "foldshift": {
        "name": "FoldShift",
        "tagline": "Origami Puzzle",
        "top_left": (250, 150, 112), "bottom_right": (222, 78, 62),   # coral to deep coral
        "glow": (255, 196, 160), "glow_at": (0.5, 0.40), "glow_r": 0.62, "glow_a": 0.8,
        "crease": 0.5,                   # crease brightness (0..1)
        "shadow": (122, 34, 26), "shadow_a": 0.38,
        "halo": (255, 240, 214), "halo_a": 0.0,
        "bloom": "warm",                 # lantern glow comes from its warm emissive pixels
        "fill": 0.84, "center_y": 0.53,  # Play icon: subject size (max bbox side) and vertical centre
        "title": (255, 255, 255), "sub": (255, 238, 220), "brand": (43, 38, 64),
    },
    "paperverse": {
        "name": "PaperVerse",
        "tagline": "3D Origami Studio",
        "top_left": (70, 88, 214), "bottom_right": (82, 34, 156),     # indigo #4a5fd6 to violet
        "glow": (128, 140, 255), "glow_at": (0.5, 0.42), "glow_r": 0.6, "glow_a": 0.7,
        "crease": 0.35,
        "shadow": (16, 8, 56), "shadow_a": 0.5,
        "halo": (190, 200, 255), "halo_a": 0.32,
        "bloom": None,
        "fill": 0.86, "center_y": 0.5,
        "title": (255, 255, 255), "sub": (214, 220, 255), "brand": (226, 230, 255),
    },
}


# ---------------------------------------------------------------- numpy <-> PIL
# Image.fromarray / np.asarray(image) go through Image.frombytes / tobytes, which fail with the Pillow 12.2
# build on the dev machine ("setimage() takes exactly 2 arguments"). Round-tripping through in-memory
# PPM/PGM uses the file codecs instead, which work everywhere and are just as fast.

def to_image(arr: np.ndarray) -> Image.Image:
    """uint8 array (H, W) / (H, W, 3) / (H, W, 4) -> PIL image (L / RGB / RGBA)."""
    arr = np.ascontiguousarray(arr, dtype=np.uint8)
    if arr.ndim == 3 and arr.shape[2] == 4:
        rgb, a = to_image(arr[..., :3]), to_image(arr[..., 3])
        rgb.putalpha(a)
        return rgb
    magic = b"P6" if arr.ndim == 3 else b"P5"
    h, w = arr.shape[:2]
    im = Image.open(io.BytesIO(magic + b"\n%d %d\n255\n" % (w, h) + arr.tobytes()))
    im.load()
    return im


def to_array(im: Image.Image) -> np.ndarray:
    """PIL image -> uint8 array; RGBA keeps 4 channels."""
    if im.mode == "RGBA":
        return np.dstack([to_array(im.convert("RGB")), to_array(im.split()[3])])
    if im.mode not in ("L", "RGB"):
        im = im.convert("RGB")
    buf = io.BytesIO()
    im.save(buf, "PPM")
    data = buf.getvalue().split(b"\n", 3)[3]
    shape = (im.height, im.width, 3) if im.mode == "RGB" else (im.height, im.width)
    return np.frombuffer(data, np.uint8).reshape(shape)


# ---------------------------------------------------------------- backgrounds

def background(w: int, h: int, cfg: dict, glow_at=None, zoom: float = 1.0) -> Image.Image:
    """Diagonal two-tone gradient + soft radial glow + one subtle diagonal paper crease, in float, dithered.
    zoom > 1 draws the same design larger (used for the adaptive layer whose outer third is masked away)."""
    ys, xs = np.mgrid[0:h, 0:w].astype(np.float32)
    s = float(max(w, h))
    u = ((xs + 0.5) - w / 2) / (s * zoom) + 0.5
    v = ((ys + 0.5) - h / 2) / (s * zoom) + 0.5
    if w != h:  # wide graphics: keep the design square-based, centred vertically
        v = ((ys + 0.5) - h / 2) / (h * zoom) + 0.5
        u = ((xs + 0.5)) / (h * zoom)
    tl, br = np.array(cfg["top_left"], np.float32), np.array(cfg["bottom_right"], np.float32)
    t = np.clip((u + v) / 2, 0, 1)[..., None]
    img = tl * (1 - t) + br * t
    gx, gy = glow_at or cfg["glow_at"]
    d = np.hypot(u - gx, v - gy) / cfg["glow_r"]
    g = (np.clip(1 - d, 0, 1) ** 1.6 * cfg["glow_a"])[..., None]
    img = img * (1 - g) + np.array(cfg["glow"], np.float32) * g
    # Paper crease along the anti-diagonal: the upper-left panel is a touch lighter (it faces the light),
    # a thin bright ridge and a soft shadow on the lower side.
    k = cfg["crease"]
    dist = (u + v - 1.0) / np.sqrt(2)  # signed distance to the crease line, in design units
    upper = (dist < 0)[..., None]
    img = np.where(upper, img + (255 - img) * 0.06 * k, img)
    px = 1.0 / (s * zoom)
    ridge = np.clip(1 - np.abs(dist) / (1.6 * px), 0, 1)[..., None]
    img = img + (255 - img) * ridge * 0.45 * k
    shade = (np.clip(dist / (0.05), 0, 1) * np.exp(-np.clip(dist, 0, None) / 0.05))[..., None]
    img = img * (1 - shade * 0.18 * k)
    img += np.random.default_rng(7).uniform(-0.6, 0.6, img.shape).astype(np.float32)  # kill banding
    return to_image(np.clip(img, 0, 255)).convert("RGBA")


# ---------------------------------------------------------------- subject placement

def subject(fg: Image.Image) -> Image.Image:
    return fg.crop(fg.split()[3].point(lambda a: 255 if a > 8 else 0).getbbox())


def scaled(img: Image.Image, scale: float) -> Image.Image:
    return img.resize((max(1, round(img.width * scale)), max(1, round(img.height * scale))), Image.LANCZOS)


def circle_scale(crop: Image.Image, radius: float) -> float:
    """Largest scale at which every clearly opaque pixel of the bbox-centred crop fits in `radius` px."""
    a = to_array(crop.split()[3]).astype(np.float32)
    ys, xs = np.nonzero(a > 48)
    cx, cy = crop.width / 2, crop.height / 2
    far = np.max(np.hypot(xs + 0.5 - cx, ys + 0.5 - cy))
    return radius / far


def effects(layer: Image.Image, size: int, cfg: dict, shadow: bool = True) -> Image.Image:
    """Return layer padded on every side, with a soft drop shadow, optional halo and lantern bloom.
    The padding keeps blurs from being clipped by the subject's bounding box; centring is unchanged."""
    pad = max(4, int(size * 0.09))
    padded = Image.new("RGBA", (layer.width + 2 * pad, layer.height + 2 * pad), (0, 0, 0, 0))
    padded.alpha_composite(layer, (pad, pad))
    layer = padded
    out = Image.new("RGBA", layer.size, (0, 0, 0, 0))
    alpha = layer.split()[3]
    if cfg["halo_a"] > 0:
        halo = Image.new("RGBA", layer.size, cfg["halo"] + (0,))
        halo.putalpha(alpha.filter(ImageFilter.GaussianBlur(size / 18)).point(lambda a: int(a * cfg["halo_a"])))
        out.alpha_composite(halo)
    if shadow:
        sh = Image.new("RGBA", layer.size, cfg["shadow"] + (0,))
        sh.putalpha(alpha.filter(ImageFilter.GaussianBlur(size / 70)).point(lambda a: int(a * cfg["shadow_a"])))
        out.alpha_composite(sh, (0, max(1, size // 60)))
    out.alpha_composite(layer)
    if cfg["bloom"] == "warm":
        # Only the lantern's emissive paper is this saturated yellow; the lit cream sheet keeps B > 150.
        rgb = to_array(layer).astype(np.float32)
        warm = (rgb[..., 0] > 230) & (rgb[..., 1] > 200) & (rgb[..., 2] < 150) & (rgb[..., 3] > 128)
        mask = to_image(warm * 255)
        for radius, strength in ((size / 45, 0.55), (size / 16, 0.35)):
            glow = Image.new("RGBA", layer.size, (255, 200, 110, 0))
            glow.putalpha(mask.filter(ImageFilter.GaussianBlur(radius)).point(lambda a, s=strength: min(255, int(a * s * 2.2))))
            out = Image.alpha_composite(out, glow)
    return out


def place(crop: Image.Image, size: int, scale: float, center=(0.5, 0.5), canvas=None) -> Image.Image:
    sub = scaled(crop, scale)
    if canvas is None:
        canvas = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    canvas.alpha_composite(sub, (round(canvas.width * center[0] - sub.width / 2),
                                 round(canvas.height * center[1] - sub.height / 2)))
    return canvas


def rounded_mask(size: int, radius: float) -> Image.Image:
    m = Image.new("L", (size * 4, size * 4), 0)
    ImageDraw.Draw(m).rounded_rectangle([0, 0, size * 4 - 1, size * 4 - 1], radius=int(size * 4 * radius), fill=255)
    return m.resize((size, size), Image.LANCZOS)


# ---------------------------------------------------------------- text

def font(size: int, weight: int) -> ImageFont.FreeTypeFont:
    f = ImageFont.truetype(str(FONT), size)
    try:
        f.set_variation_by_axes([weight])
    except (OSError, AttributeError):
        pass
    return f


def text_layer(size, xy, text, f, fill, shadow=(0, 0, 0), shadow_a=70, blur=6, dy=4):
    layer = Image.new("RGBA", size, (0, 0, 0, 0))
    sh = Image.new("RGBA", size, (0, 0, 0, 0))
    ImageDraw.Draw(sh).text((xy[0], xy[1] + dy), text, font=f, fill=shadow + (shadow_a,))
    layer.alpha_composite(sh.filter(ImageFilter.GaussianBlur(blur)))
    ImageDraw.Draw(layer).text(xy, text, font=f, fill=fill + (255,))
    return layer


def feature_graphic(crop: Image.Image, cfg: dict) -> Image.Image:
    W, H = 1024, 500
    img = background(W, H, cfg, glow_at=(0.62, 0.48))
    # Hero on the left, as large as the height allows.
    scale = min(0.9 * H / crop.height, 0.5 * W / crop.width)
    hero = effects(scaled(crop, scale), H, cfg)
    img.alpha_composite(hero, (round(W * 0.27 - hero.width / 2), round(H * 0.5 - hero.height / 2)))
    # App name on the right, heavy rounded sans, sized to fit the right half.
    left, right = int(W * 0.53), int(W * 0.96)
    size = 150
    while size > 40:
        f = font(size, 800)
        if f.getbbox(cfg["name"])[2] <= right - left:
            break
        size -= 2
    sub = font(int(size * 0.42), 650)
    brand = font(max(26, int(size * 0.28)), 700)
    tb, sb, bb = f.getbbox(cfg["name"]), sub.getbbox(cfg["tagline"]), brand.getbbox("F7 DEVELOPER")
    gap = int(size * 0.12)
    block = (tb[3] - tb[1]) + gap + (sb[3] - sb[1]) + gap * 2 + (bb[3] - bb[1])
    y = (H - block) // 2
    img.alpha_composite(text_layer((W, H), (left - tb[0], y - tb[1]), cfg["name"], f, cfg["title"], cfg["shadow"], 110, 8, 5))
    y += tb[3] - tb[1] + gap
    img.alpha_composite(text_layer((W, H), (left - sb[0] + 4, y - sb[1]), cfg["tagline"], sub, cfg["sub"], cfg["shadow"], 90, 5, 3))
    y += sb[3] - sb[1] + gap * 2
    ImageDraw.Draw(img).text((left - bb[0] + 5, y - bb[1]), "F7 DEVELOPER", font=brand, fill=cfg["brand"] + (255,))
    return img.convert("RGB")


# ---------------------------------------------------------------- per app

def build(app: str, cfg: dict) -> dict:
    src = RENDERS / f"{app}_fg.png"
    if not src.exists():
        print(f"skip {app}: {src} missing (run pipeline/blender/render_icons.py first)")
        return {}
    crop = subject(Image.open(src).convert("RGBA"))
    store, app_dir = ROOT / "store" / app, ROOT / "apps" / app
    icons, splash = app_dir / "assets" / "icons", app_dir / "assets" / "splash"
    for p in (store, icons, splash):
        p.mkdir(parents=True, exist_ok=True)

    # Play Store icon: full-bleed 1024 master, downscaled to 512.
    S = 1024
    scale = cfg["fill"] * S / max(crop.size)
    big = background(S, S, cfg)
    big.alpha_composite(place(effects(scaled(crop, scale), S, cfg), S, 1.0, (0.5, cfg["center_y"])))
    icon512 = big.convert("RGB").resize((512, 512), Image.LANCZOS)
    icon512.save(store / "icon_512.png")
    # Godot project icon and legacy launcher icon: rounded square.
    rounded = big.copy()
    rounded.putalpha(rounded_mask(S, 0.22))
    rounded.resize((256, 256), Image.LANCZOS).save(app_dir / "icon.png")
    rounded.resize((192, 192), Image.LANCZOS).save(icons / "main_192.png")

    # Adaptive layers at 432: subject (no backdrop) inside the safe circle; background full bleed.
    A = 432
    a_scale = circle_scale(crop, SAFE_RADIUS * A)
    sub_a = scaled(crop, a_scale)
    fg_layer = place(effects(sub_a, int(A / 1.5), cfg), A, 1.0)
    fg_layer.save(icons / "adaptive_fg_432.png")
    bg_layer = background(A, A, cfg, zoom=1.5).convert("RGB")
    bg_layer.save(icons / "adaptive_bg_432.png")
    # Monochrome: plain white silhouette of the subject with its alpha (launcher tints it).
    mono = Image.new("RGBA", (A, A), (255, 255, 255, 0))
    sil = place(sub_a, A, 1.0)
    mono.putalpha(sil.split()[3])
    mono.save(icons / "monochrome_432.png")

    # Splash emblem: the hero alone, transparent, soft shadow.
    E = 640
    e_scale = 0.88 * E / max(crop.size)
    emblem = place(effects(scaled(crop, e_scale), E, cfg), E, 1.0, (0.5, 0.49))
    emblem.save(splash / "emblem.png")

    fg_path = store / "feature_graphic.png"
    feature_graphic(crop, cfg).save(fg_path)
    print(f"{app}: icon_512, icon.png, main_192, adaptive fg/bg/mono, splash emblem, feature graphic written")
    return {"icon": icon512, "fg": fg_layer, "bg": bg_layer, "mono": mono, "emblem": emblem,
            "feature": Image.open(fg_path).convert("RGB"), "rounded": rounded}


# ---------------------------------------------------------------- QA contact sheet

def squircle_mask(size: int, n: float = 4.0) -> Image.Image:
    ys, xs = np.mgrid[0:size * 4, 0:size * 4].astype(np.float32)
    c = size * 2
    m = (np.abs((xs - c) / c) ** n + np.abs((ys - c) / c) ** n) <= 1
    return to_image(m * 255).resize((size, size), Image.LANCZOS)


def circle_mask(size: int) -> Image.Image:
    m = Image.new("L", (size * 4, size * 4), 0)
    ImageDraw.Draw(m).ellipse([0, 0, size * 4 - 1, size * 4 - 1], fill=255)
    return m.resize((size, size), Image.LANCZOS)


def adaptive_preview(bg: Image.Image, fg: Image.Image, size: int, shape: str) -> Image.Image:
    full = bg.convert("RGBA").copy()
    full.alpha_composite(fg)
    vis = full.crop((72, 72, 360, 360)).resize((size, size), Image.LANCZOS)  # launcher viewport 72/108
    mask = {"circle": circle_mask, "squircle": squircle_mask}.get(shape, lambda s: rounded_mask(s, 0.2))(size)
    vis.putalpha(mask)
    return vis


def themed_preview(mono: Image.Image, size: int) -> Image.Image:
    base = Image.new("RGBA", (432, 432), (42, 46, 64, 255))
    tint = Image.new("RGBA", (432, 432), (200, 214, 255, 255))
    tint.putalpha(mono.split()[3])
    base.alpha_composite(tint)
    vis = base.crop((72, 72, 360, 360)).resize((size, size), Image.LANCZOS)
    vis.putalpha(circle_mask(size))
    return vis


def contact_sheet(results: dict, path: Path) -> None:
    pad = 28
    W, row_h = 2200, 44 + 648 + pad + 500 + pad + 20
    sheet = Image.new("RGB", (W, row_h * len(results) + 20), (226, 224, 220))
    d = ImageDraw.Draw(sheet)
    label = font(26, 600)
    for r, (app, res) in enumerate(results.items()):
        y0 = r * row_h + 20
        d.text((pad, y0), f"{APPS[app]['name']}:  Play icon 512 / 192 / 96 / 48   |   adaptive through circle, "
                          f"squircle, rounded masks at 192 / 96 / 48   |   themed icon", font=label, fill=(40, 40, 50))
        y = y0 + 44
        x = pad
        sheet.paste(res["icon"], (x, y))
        x += 512 + pad
        for s in (192, 96, 48):
            im = res["rounded"].resize((s, s), Image.LANCZOS)
            sheet.paste(im, (x, y), im)
            x += s + pad
        # Dark wallpaper panel so the launcher sizes are judged in context.
        panel_x = x
        d.rounded_rectangle([panel_x, y, W - pad, y + 648], radius=18, fill=(34, 36, 48))
        yy = y + 18
        for shape in ("circle", "squircle", "rounded"):
            xx = panel_x + pad
            for s in (192, 96, 48):
                im = adaptive_preview(res["bg"], res["fg"], s, shape)
                sheet.paste(im, (xx, yy + (192 - s) // 2), im)
                xx += s + pad
            yy += 192 + 18
        tx = panel_x + pad + 192 + 96 + 48 + pad * 3 + 40
        d.line([tx - 30, y + 20, tx - 30, y + 628], fill=(70, 74, 92), width=2)
        yy = y + 18
        for s in (192, 96, 48):
            im = themed_preview(res["mono"], s)
            sheet.paste(im, (tx, yy + (192 - s) // 2), im)
            yy += 192 + 18
        # Second line: splash emblem on the splash colour, feature graphic, raw monochrome layer.
        y2 = y + 648 + pad
        tile = Image.new("RGBA", (500, 500), (247, 242, 232, 255) if app == "foldshift" else (243, 241, 236, 255))
        tile.alpha_composite(res["emblem"].resize((500, 500), Image.LANCZOS))
        sheet.paste(tile.convert("RGB"), (pad, y2))
        sheet.paste(res["feature"], (pad + 500 + pad, y2))
        mono_tile = Image.new("RGBA", (216, 216), (90, 90, 100, 255))
        mono_tile.alpha_composite(res["mono"].resize((216, 216), Image.LANCZOS))
        sheet.paste(mono_tile.convert("RGB"), (pad + 500 + pad + 1024 + pad, y2))
        fgl = Image.new("RGBA", (216, 216), (120, 120, 130, 255))
        fgl.alpha_composite(res["fg"].resize((216, 216), Image.LANCZOS))
        dd = ImageDraw.Draw(fgl)
        r_safe = SAFE_RADIUS * 216
        dd.ellipse([108 - r_safe, 108 - r_safe, 108 + r_safe, 108 + r_safe], outline=(0, 255, 160, 255), width=2)
        sheet.paste(fgl.convert("RGB"), (pad + 500 + pad + 1024 + pad, y2 + 216 + pad))
    path.parent.mkdir(parents=True, exist_ok=True)
    sheet.save(path)
    print("contact sheet:", path)


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--sheet", type=Path, help="also write a QA contact sheet PNG to this path")
    ap.add_argument("apps", nargs="*", default=list(APPS), help="subset of apps (default: all)")
    args = ap.parse_args()
    results = {app: res for app in args.apps if (res := build(app, APPS[app]))}
    if args.sheet and results:
        contact_sheet(results, args.sheet if args.sheet.is_absolute() else ROOT / args.sheet)


if __name__ == "__main__":
    main()
