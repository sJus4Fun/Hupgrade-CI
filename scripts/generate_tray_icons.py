#!/usr/bin/env python3
"""
Generate branded system tray icons from logo.svg.

Produces four states (disconnected / connected / disconnecting / dark-mode),
each in PNG (128×128, for macOS/Linux) and ICO (multi-resolution, for Windows).

Usage: python3 generate_tray_icons.py <logo.svg> <output_dir>
Output:  <output_dir>/tray_icon.png          — blue  (disconnected, light mode)
         <output_dir>/tray_icon.ico
         <output_dir>/tray_icon_connected.png  — green (connected)
         <output_dir>/tray_icon_connected.ico
         <output_dir>/tray_icon_disconnected.png — red  (connecting / disconnecting)
         <output_dir>/tray_icon_disconnected.ico
         <output_dir>/tray_icon_dark.png        — light (disconnected, dark mode)
         <output_dir>/tray_icon_dark.ico
"""

import io
import os
import struct
import subprocess
import sys
from collections import Counter

from PIL import Image

LANCZOS = Image.LANCZOS  # compat: Pillow <10 uses Image.LANCZOS; Pillow 10+ has Image.Resampling.LANCZOS


def render_svg(svg_path: str, size: int) -> Image.Image:
    """Render an SVG file to a Pillow RGBA image of the given square size."""
    tmp = "/tmp/_traygen_temp.png"
    subprocess.run(
        [sys.executable, "scripts/svg2png.py", svg_path, tmp, str(size)],
        capture_output=True,
        check=True,
    )
    return Image.open(tmp).convert("RGBA")


def extract_lightning(logo_path: str) -> Image.Image:
    """
    Extract the white-ish lightning bolt shape from the logo.

    Strategy: render the logo at 512×512, keep only pixels with
    R,G,B > 200 (white / near-white), then crop to bounding box.
    Falls back to the full logo if no white pixels are found
    (e.g. a monochromatic logo with no lightning bolt).
    """
    full = render_svg(logo_path, 512)

    bolt = Image.new("RGBA", (512, 512), (0, 0, 0, 0))
    white_count = 0
    for x in range(512):
        for y in range(512):
            r, g, b, a = full.getpixel((x, y))
            if a == 0:
                continue
            if r > 200 and g > 200 and b > 200:
                bolt.putpixel((x, y), (255, 255, 255, 255))
                white_count += 1

    bbox = bolt.getbbox()
    if bbox is None or white_count < 50:
        # No lightning bolt found — fall back to full logo
        scaled = full.resize((128, 128), LANCZOS)
        canvas = Image.new("RGBA", (128, 128), (0, 0, 0, 0))
        canvas.paste(scaled, (0, 0))
        return canvas

    bolt_crop = bolt.crop(bbox)
    bw, bh = bolt_crop.size

    # Scale bolt to fill ~70% of the 128×128 tray icon
    scale = min(90 / bw, 90 / bh)
    new_w, new_h = int(bw * scale), int(bh * scale)
    scaled_bolt = bolt_crop.resize((new_w, new_h), LANCZOS)

    canvas = Image.new("RGBA", (128, 128), (0, 0, 0, 0))
    x = (128 - new_w) // 2
    y = (128 - new_h) // 2
    canvas.paste(scaled_bolt, (x, y), scaled_bolt)
    return canvas


def recolor(img: Image.Image, target_color: tuple[int, int, int]) -> Image.Image:
    """Replace every opaque pixel's RGB with *target_color*, preserving alpha."""
    pixels = img.getdata()
    new_pixels = [
        (*target_color, a) if a else (0, 0, 0, 0)
        for r, g, b, a in pixels
    ]
    result = Image.new("RGBA", img.size)
    result.putdata(new_pixels)
    return result


def make_ico(png_path: str, sizes: list[int] = (16, 32, 48, 64, 128)) -> bytes:
    """Create a multi-resolution ICO byte-string from a PNG source."""
    img = Image.open(png_path).convert("RGBA")

    png_parts: list[bytes] = []
    for s in sizes:
        resized = img.resize((s, s), LANCZOS)
        buf = io.BytesIO()
        resized.save(buf, format="PNG")
        png_parts.append(buf.getvalue())

    out = io.BytesIO()
    out.write(struct.pack("<HHH", 0, 1, len(sizes)))  # ICO header
    offset = 6 + 16 * len(sizes)
    for s, data in zip(sizes, png_parts):
        w = 0 if s >= 256 else s
        h = 0 if s >= 256 else s
        out.write(struct.pack("<BBBBHHII", w, h, 0, 0, 1, 32, len(data), offset))
        offset += len(data)
    for data in png_parts:
        out.write(data)
    return out.getvalue()


# ── main ────────────────────────────────────────────────────────────────
def main() -> None:
    if len(sys.argv) < 3:
        print(f"Usage: {sys.argv[0]} <logo.svg> <output_dir>", file=sys.stderr)
        sys.exit(2)

    logo_svg = sys.argv[1]
    out_dir = sys.argv[2]

    if not os.path.isfile(logo_svg):
        print(f"Error: {logo_svg} not found", file=sys.stderr)
        sys.exit(1)

    os.makedirs(out_dir, exist_ok=True)

    print("  [INFO] Generating tray icons from logo ...")

    lightning = extract_lightning(logo_svg)

    # Colour palette for each tray state
    states: list[tuple[str, tuple[int, int, int]]] = [
        ("tray_icon",              (64, 80, 224)),    # blue – disconnected (light mode)
        ("tray_icon_connected",    (0, 180, 0)),      # green – connected
        ("tray_icon_disconnected", (200, 40, 40)),    # red – connecting / disconnecting
        ("tray_icon_dark",         (220, 220, 240)),  # light – disconnected (dark mode)
    ]

    for stem, color in states:
        img = recolor(lightning, color)

        png_path = os.path.join(out_dir, f"{stem}.png")
        img.save(png_path)

        # Use PNG as intermediate for ICO generation
        ico_data = make_ico(png_path)
        ico_path = os.path.join(out_dir, f"{stem}.ico")
        with open(ico_path, "wb") as f:
            f.write(ico_data)

        png_kb = os.path.getsize(png_path) // 1024
        ico_kb = os.path.getsize(ico_path) // 1024
        print(f"    {stem}: {png_kb} KB PNG  +  {ico_kb} KB ICO")

    print("  [OK] System tray icons (4 PNGs + 4 ICOs)")


if __name__ == "__main__":
    main()
