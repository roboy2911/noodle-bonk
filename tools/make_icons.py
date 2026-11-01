"""Finishes the shop icons: sunburst background + Blender render + chunky text.

python3 tools/make_icons.py <renders_dir> <font.ttf> <out_dir>

Renders come from tools/blender/render_icons.py. Output is 512x512 PNGs.
Roblox shows game pass icons in a circle, so everything important stays in
the middle ~85%.
"""

import math
import os
import sys

from PIL import Image, ImageChops, ImageDraw, ImageEnhance, ImageFilter, ImageFont

RENDERS, FONT, OUT = sys.argv[1], sys.argv[2], sys.argv[3]
os.makedirs(OUT, exist_ok=True)
SIZE = 512
OUTLINE = (40, 20, 90)


def sunburst(inner, outer, ray, center=(256, 256), rays=16, rotation=0.1):
    img = Image.new("RGB", (SIZE, SIZE), outer)
    d = ImageDraw.Draw(img)
    reach = SIZE * 1.2
    for i in range(0, rays * 2, 2):
        a0 = rotation + i * math.pi / rays
        a1 = rotation + (i + 1) * math.pi / rays
        d.polygon([center, (center[0] + math.cos(a0) * reach, center[1] + math.sin(a0) * reach), (center[0] + math.cos(a1) * reach, center[1] + math.sin(a1) * reach)], fill=ray)
    glow = Image.new("L", (SIZE, SIZE), 0)
    gd = ImageDraw.Draw(glow)
    for r in range(330, 0, -3):
        gd.ellipse((center[0] - r, center[1] - r, center[0] + r, center[1] + r), fill=int(255 * (1 - r / 330) ** 1.4))
    img = Image.composite(Image.new("RGB", (SIZE, SIZE), inner), img, glow)
    # soft dark edge so the icon reads on any background
    edge = Image.new("L", (SIZE, SIZE), 0)
    ImageDraw.Draw(edge).ellipse((-60, -60, SIZE + 60, SIZE + 60), fill=255)
    edge = edge.filter(ImageFilter.GaussianBlur(50))
    return Image.composite(img, ImageEnhance.Brightness(img).enhance(0.6), edge)


def text(canvas, center, string, size, fill, angle=-6, stroke=10):
    font = ImageFont.truetype(FONT, size)
    l, t, r, b = font.getbbox(string, stroke_width=stroke)
    pad = stroke + 16
    layer = Image.new("RGBA", (r - l + pad * 2, b - t + pad * 2), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    origin = (pad - l, pad - t)
    d.text((origin[0] + 4, origin[1] + 7), string, font=font, fill=(0, 0, 0, 140), stroke_width=stroke, stroke_fill=(0, 0, 0, 140))
    d.text(origin, string, font=font, fill=fill, stroke_width=stroke, stroke_fill=OUTLINE)
    shine = Image.new("RGBA", layer.size, (0, 0, 0, 0))
    ImageDraw.Draw(shine).text(origin, string, font=font, fill=(255, 255, 255, 95))
    cut = Image.new("L", layer.size, 0)
    ImageDraw.Draw(cut).rectangle((0, 0, layer.size[0], origin[1] + (b - t) * 0.42), fill=255)
    shine.putalpha(ImageChops.multiply(shine.getchannel("A"), cut))
    layer = Image.alpha_composite(layer, shine).rotate(angle, resample=Image.BICUBIC, expand=True)
    canvas.alpha_composite(layer, (int(center[0] - layer.size[0] / 2), int(center[1] - layer.size[1] / 2)))


def render(name, scale=1.0, offset=(0, 0), saturation=1.35, outline=True):
    """The Blender render, punched up, with a white sticker outline."""
    img = Image.open(os.path.join(RENDERS, name)).convert("RGBA")
    rgb = ImageEnhance.Contrast(ImageEnhance.Color(img.convert("RGB")).enhance(saturation)).enhance(1.12)
    img = Image.merge("RGBA", (*rgb.split(), img.getchannel("A")))
    if scale != 1.0:
        img = img.resize((int(SIZE * scale), int(SIZE * scale)), Image.LANCZOS)
    layer = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    layer.alpha_composite(img, (int((SIZE - img.size[0]) / 2 + offset[0]), int((SIZE - img.size[1]) / 2 + offset[1])))
    if outline:
        alpha = layer.getchannel("A").point(lambda v: 255 if v > 40 else 0)
        sticker = alpha.filter(ImageFilter.MaxFilter(11)).filter(ImageFilter.GaussianBlur(1))
        white = Image.new("RGBA", (SIZE, SIZE), (255, 255, 255, 255))
        white.putalpha(sticker)
        shadow = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
        shadow.putalpha(sticker.filter(ImageFilter.GaussianBlur(8)).point(lambda v: int(v * 0.45)))
        base = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
        base.alpha_composite(shadow, (5, 9))
        base.alpha_composite(white)
        base.alpha_composite(layer)
        layer = base
    return layer


def save(img, name):
    img.convert("RGB").save(os.path.join(OUT, name), optimize=True)
    print("icon", name)


# Noodle Skins Pack: three skins, purple party background
icon = sunburst((255, 200, 255), (110, 40, 190), (150, 70, 220)).convert("RGBA")
icon.alpha_composite(render("skins.png", 0.86, (0, -36)))
text(icon, (256, 410), "SKINS", 104, (255, 226, 60))
save(icon, "pass_skins_512.png")

# VIP: golden crown, warm background
icon = sunburst((255, 245, 190), (235, 120, 20), (255, 165, 40)).convert("RGBA")
icon.alpha_composite(render("vip.png", 0.88, (0, -48)))
text(icon, (256, 400), "VIP", 150, (255, 226, 60), angle=-5, stroke=12)
save(icon, "pass_vip_512.png")

# 2x Bonks: pink noodle swoosh, blue background, huge 2X
icon = sunburst((210, 245, 255), (20, 110, 230), (60, 160, 255)).convert("RGBA")
icon.alpha_composite(render("double.png", 1.0, (0, 40)))
text(icon, (256, 205), "2X", 200, (255, 226, 60), angle=-8, stroke=14)
text(icon, (262, 392), "BONKS", 92, (255, 120, 195), angle=-5)
save(icon, "pass_2x_bonks_512.png")

# Pool Party: toys and confetti, pink/cyan background
icon = sunburst((255, 250, 220), (255, 90, 170), (60, 200, 255), rays=20).convert("RGBA")
icon.alpha_composite(render("party.png", 1.0, (0, -10), outline=False))
text(icon, (256, 100), "POOL", 88, (255, 226, 60), angle=-6)
text(icon, (256, 414), "PARTY!", 84, (255, 255, 255), angle=-6)
save(icon, "product_pool_party_512.png")
