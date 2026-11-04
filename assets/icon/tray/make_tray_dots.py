"""Builds the tray icons that carry a state dot from the plain mark.

Run from anywhere: python assets/icon/tray/make_tray_dots.py  (needs Pillow)

Inputs (kept as they are): tray.ico (16, 20, 24, 32, 48 px) and
tray-{16,20,24,32}.png, both made from tray.svg.
Outputs: tray-shared.ico, tray-stopped.ico and
tray-{16,20,24,32}-{shared,stopped}.png.

The dot is a plain filled circle in the bottom-right corner, 40% of the icon.
The mark is cut away in a thin transparent ring around it, so the dot reads
on a light and on a dark taskbar. Colours are the light-theme --ok-ink and
--danger-ink of the BubbleBuffer design tokens.
"""

from pathlib import Path

from PIL import Image, ImageDraw

HERE = Path(__file__).resolve().parent
DOTS = {"shared": (0x39, 0x77, 0x48), "stopped": (0xAD, 0x4B, 0x4B)}
SIZES = (16, 20, 24, 32)
SCALE = 8  # supersampling for a smooth circle
DIAMETER = 0.40  # of the icon
GAP = 0.07  # transparent ring width, of the icon (about 1 px at 16)
EDGE = 0.02  # distance of the ring's outer edge from the icon border


def with_dot(mark: Image.Image, colour: tuple[int, int, int]) -> Image.Image:
    size = mark.width
    big = size * SCALE
    r = DIAMETER * size / 2
    gap = max(GAP * size, 1.0)
    cx = cy = size - EDGE * size - gap - r
    cut = Image.new("L", (big, big), 0)
    dot = Image.new("L", (big, big), 0)
    for mask, radius in ((cut, r + gap), (dot, r)):
        d = ImageDraw.Draw(mask)
        d.ellipse(
            [(cx - radius) * SCALE, (cy - radius) * SCALE,
             (cx + radius) * SCALE, (cy + radius) * SCALE],
            fill=255,
        )
    cut = cut.resize((size, size), Image.LANCZOS)
    dot = dot.resize((size, size), Image.LANCZOS)
    out = mark.convert("RGBA")
    alpha = out.getchannel("A")
    keep = Image.eval(cut, lambda v: 255 - v)
    out.putalpha(Image.composite(alpha, Image.new("L", out.size, 0), keep))
    paint = Image.new("RGBA", out.size, colour + (255,))
    out.alpha_composite(Image.composite(paint, Image.new("RGBA", out.size, 0), dot))
    return out


def main() -> None:
    ico = Image.open(HERE / "tray.ico")
    sizes = sorted(s[0] for s in ico.ico.sizes())
    for name, colour in DOTS.items():
        for size in SIZES:
            mark = Image.open(HERE / f"tray-{size}.png").convert("RGBA")
            with_dot(mark, colour).save(HERE / f"tray-{size}-{name}.png")
        frames = [with_dot(ico.ico.getimage((s, s)), colour) for s in sizes]
        frames[-1].save(
            HERE / f"tray-{name}.ico",
            format="ICO",
            sizes=[(s, s) for s in sizes],
            append_images=frames[:-1],
        )


if __name__ == "__main__":
    main()
