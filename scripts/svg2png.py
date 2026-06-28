#!/usr/bin/env python3
"""Render a simple SVG (rect + path) to PNG at any size using Pillow.

macOS NSImage SVG rendering is broken for fill colors, so we bypass it
by parsing our extremely simple SVG format directly and drawing with Pillow.

Usage: python3 scripts/svg2png.py <input.svg> <output.png> <width> [height]
"""

import re
import sys
from PIL import Image, ImageDraw


def parse_color(hex_str: str) -> tuple[int, int, int]:
    """Parse #RRGGBB or #RGB to (R, G, B)."""
    hex_str = hex_str.lstrip('#')
    if len(hex_str) == 3:
        hex_str = ''.join(c * 2 for c in hex_str)
    return tuple(int(hex_str[i:i+2], 16) for i in (0, 2, 4))


def render_svg(svg_path: str, output_path: str, target_w: int, target_h: int):
    """Render our simple SVG (rounded rect + path) to PNG."""
    with open(svg_path) as f:
        svg = f.read()

    # Parse viewBox
    vb_match = re.search(r'viewBox="([^"]*)"', svg)
    if vb_match:
        parts = list(map(float, vb_match.group(1).split()))
        svg_w, svg_h = int(parts[2]), int(parts[3])
    else:
        wm = re.search(r'width="([^"]*)"', svg)
        hm = re.search(r'height="([^"]*)"', svg)
        svg_w = int(float(wm.group(1))) if wm else 64
        svg_h = int(float(hm.group(1))) if hm else 64

    scale_x = target_w / svg_w
    scale_y = target_h / svg_h

    # Parse <rect>
    rect_m = re.search(r'<rect\s+([^>]*)/>', svg)
    rx_val = 13
    r_x, r_y, r_w, r_h = 0, 0, svg_w, svg_h
    rect_fill = '#000000'
    if rect_m:
        attrs = dict(re.findall(r'(\w+)="([^"]*)"', rect_m.group(1)))
        r_x = int(float(attrs.get('x', 0)) * scale_x)
        r_y = int(float(attrs.get('y', 0)) * scale_y)
        r_w = int(float(attrs.get('width', svg_w)) * scale_x)
        r_h = int(float(attrs.get('height', svg_h)) * scale_y)
        rx_val = int(float(attrs.get('rx', 13)))
        rect_fill = attrs.get('fill', '#000000')

    rx_px = int(rx_val * scale_x)
    rect_color = parse_color(rect_fill) + (255,)

    # Parse <path>
    path_m = re.search(r'<path\s+([^/>]*)/?>', svg)
    path_fill = '#FFFFFF'
    path_d = ''
    if path_m:
        attrs = dict(re.findall(r'(\w+)="([^"]*)"', path_m.group(1)))
        path_d = attrs.get('d', '')
        path_fill = attrs.get('fill', '#FFFFFF')

    path_color = parse_color(path_fill) + (255,)

    # Render
    img = Image.new('RGBA', (target_w, target_h), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)

    # Rounded rect
    if rx_px > 0:
        draw.rounded_rectangle([r_x, r_y, r_x + r_w, r_y + r_h],
                               radius=rx_px, fill=rect_color)
    else:
        draw.rectangle([r_x, r_y, r_x + r_w, r_y + r_h], fill=rect_color)

    # SVG path polygon
    if path_d:
        pts = []
        for cmd, args_str in re.findall(r'([MLZ])\s*([\d,.\s-]*)', path_d):
            if cmd in ('M', 'L'):
                args = list(map(float, re.findall(r'[\d.]+', args_str)))
                if len(args) >= 2:
                    pts.append((int(args[0] * scale_x), int(args[1] * scale_y)))
        if len(pts) >= 3:
            draw.polygon(pts, fill=path_color)

    img.save(output_path, 'PNG')
    return target_w, target_h


if __name__ == '__main__':
    if len(sys.argv) < 4:
        print(f"Usage: python3 {sys.argv[0]} <input.svg> <output.png> <width> [height]")
        sys.exit(1)

    input_path = sys.argv[1]
    output_path = sys.argv[2]
    width = int(sys.argv[3])
    height = int(sys.argv[4]) if len(sys.argv) >= 5 else width

    w, h = render_svg(input_path, output_path, width, height)
    print(f"[OK] {w}x{h} -> {output_path}")
