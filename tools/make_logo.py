"""Generates placeholder Pickadoor branding into assets/branding/.

    python tools/make_logo.py

Outputs: icon_512.png (game icon), wordmark.png (transparent title), thumbnail_1920x1080.png.
Two arched doors: one ajar with warm lamplight spilling out, one shut with a thin red glow.
"""
import math
import os

from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "assets", "branding")
FONTS = os.path.join(os.environ.get("WINDIR", r"C:\Windows"), "Fonts")
SERIF_BOLD = os.path.join(FONTS, "GARABD.TTF")
SERIF = os.path.join(FONTS, "GARA.TTF")

GOLD = (214, 172, 98)
WARM = (255, 178, 92)
BG_CENTER = (52, 30, 20)
BG_EDGE = (8, 5, 4)


def radial_bg(w, h, center, inner, outer, radius):
    img = Image.new("RGB", (w, h), outer)
    px = img.load()
    cx, cy = center
    for y in range(h):
        for x in range(w):
            d = min(1.0, math.hypot(x - cx, y - cy) / radius)
            t = d * d
            px[x, y] = tuple(int(inner[i] * (1 - t) + outer[i] * t) for i in range(3))
    return img


def arch_door(draw, box, fill, outline=None, width=0):
    x0, y0, x1, y1 = box
    r = (x1 - x0) / 2
    draw.pieslice((x0, y0, x1, y0 + 2 * r), 180, 360, fill=fill)
    draw.rectangle((x0, y0 + r - 2, x1, y1), fill=fill)
    if outline:
        draw.arc((x0, y0, x1, y0 + 2 * r), 180, 360, fill=outline, width=width)
        draw.line((x0, y0 + r, x0, y1), fill=outline, width=width)
        draw.line((x1, y0 + r, x1, y1), fill=outline, width=width)


def doors_scene(size, show_text=True, transparent=False):
    S = size * 2  # supersample
    if transparent:
        img = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    else:
        img = radial_bg(S // 4, S // 4, (S // 8, S // 9), BG_CENTER, BG_EDGE, S // 5).resize((S, S), Image.BICUBIC)
        img = img.convert("RGBA")

    dw, dh = S * 0.24, S * 0.46
    top = S * 0.16
    gap = S * 0.08
    left = (S / 2 - gap / 2 - dw, top, S / 2 - gap / 2, top + dh)
    right = (S / 2 + gap / 2, top, S / 2 + gap / 2 + dw, top + dh)

    # warm light pouring from the left door onto the floor
    glow = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    g = ImageDraw.Draw(glow)
    lx0, ly0, lx1, ly1 = left
    g.polygon([(lx0 + dw * 0.1, ly1), (lx1, ly1), (lx1 + dw * 0.9, S * 0.97), (lx0 - dw * 0.6, S * 0.97)], fill=WARM + (110,))
    arch_door(g, (lx0 - S * 0.02, ly0 - S * 0.02, lx1 + S * 0.02, ly1), WARM + (150,))
    glow = glow.filter(ImageFilter.GaussianBlur(S * 0.025))
    img = Image.alpha_composite(img, glow)

    # thin red bleed around the right door
    red = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    arch_door(ImageDraw.Draw(red), (right[0] - S * 0.008, right[1] - S * 0.008, right[2] + S * 0.008, right[3]), (170, 30, 24, 170))
    red = red.filter(ImageFilter.GaussianBlur(S * 0.012))
    img = Image.alpha_composite(img, red)

    d = ImageDraw.Draw(img)
    frame_w = int(S * 0.012)
    # left: bright opening + door swung inward (a narrow dark slab)
    arch_door(d, left, (255, 214, 150, 255))
    slab = (left[0], left[1] + dw * 0.5, left[0] + dw * 0.32, left[3])
    d.polygon([(slab[0], slab[1] - dw * 0.08), (slab[2], slab[1] + dw * 0.06), (slab[2], slab[3]), (slab[0], slab[3])], fill=(44, 26, 18, 255))
    arch_door(d, left, None, GOLD, frame_w)
    # right: shut, dark wood, brass knob
    arch_door(d, right, (40, 24, 17, 255))
    arch_door(d, right, None, GOLD, frame_w)
    for i in (0.33, 0.66):
        y = right[1] + dh * i + dw * 0.25
        d.rectangle((right[0] + dw * 0.18, y - dh * 0.12, right[2] - dw * 0.18, y + dh * 0.1), outline=(64, 40, 28, 255), width=int(S * 0.005))
    k = S * 0.012
    kx, ky = right[2] - dw * 0.16, right[1] + dh * 0.6
    d.ellipse((kx - k, ky - k, kx + k, ky + k), fill=GOLD)

    # floor line
    d.line((S * 0.08, top + dh, S * 0.92, top + dh), fill=(90, 60, 40, 255), width=int(S * 0.004))

    if show_text:
        font = ImageFont.truetype(SERIF_BOLD, int(S * 0.13))
        text = "PICKADOOR"
        tw = d.textlength(text, font=font)
        ty = S * 0.70
        shadow = Image.new("RGBA", (S, S), (0, 0, 0, 0))
        ImageDraw.Draw(shadow).text(((S - tw) / 2, ty), text, font=font, fill=(0, 0, 0, 220))
        img = Image.alpha_composite(img, shadow.filter(ImageFilter.GaussianBlur(S * 0.01)))
        d = ImageDraw.Draw(img)
        d.text(((S - tw) / 2, ty), text, font=font, fill=GOLD)
        small = ImageFont.truetype(SERIF, int(S * 0.045))
        tag = "choose your fate"
        sw = d.textlength(tag, font=small)
        d.text(((S - sw) / 2, ty + S * 0.15), tag, font=small, fill=(200, 180, 150))

    return img.resize((size, size), Image.LANCZOS)


def wordmark(width=1600, height=420):
    S = 2
    img = Image.new("RGBA", (width * S, height * S), (0, 0, 0, 0))
    font = ImageFont.truetype(SERIF_BOLD, int(height * S * 0.62))
    d = ImageDraw.Draw(img)
    text = "PICKADOOR"
    tw = d.textlength(text, font=font)
    x, y = (width * S - tw) / 2, height * S * 0.08
    glow = Image.new("RGBA", img.size, (0, 0, 0, 0))
    ImageDraw.Draw(glow).text((x, y), text, font=font, fill=WARM + (160,))
    img = Image.alpha_composite(img, glow.filter(ImageFilter.GaussianBlur(18)))
    d = ImageDraw.Draw(img)
    d.text((x, y), text, font=font, fill=GOLD, stroke_width=4, stroke_fill=(60, 36, 22))
    return img.resize((width, height), Image.LANCZOS)


def thumbnail():
    w, h = 1920, 1080
    bg = radial_bg(w // 4, h // 4, (w // 8, h // 8), BG_CENTER, BG_EDGE, w // 5).resize((w, h), Image.BICUBIC).convert("RGBA")
    scene = doors_scene(1000, show_text=False, transparent=True)
    bg.alpha_composite(scene.crop((0, 60, 1000, 1000)), ((w - 1000) // 2, 40))
    mark = wordmark(1300, 300)
    bg.alpha_composite(mark, ((w - 1300) // 2, 760))
    return bg


def main():
    os.makedirs(OUT, exist_ok=True)
    doors_scene(512).save(os.path.join(OUT, "icon_512.png"))
    wordmark().save(os.path.join(OUT, "wordmark.png"))
    thumbnail().convert("RGB").save(os.path.join(OUT, "thumbnail_1920x1080.png"))
    print("wrote", OUT)


if __name__ == "__main__":
    main()
