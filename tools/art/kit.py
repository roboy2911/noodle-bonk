"""Tiny 2D cartoon kit for Noodle Bonk thumbnails (Pillow). Everything is drawn
at 2x and scaled down at the end for smooth edges."""
import math, random
from PIL import Image, ImageDraw, ImageFont, ImageFilter

FONT = "/usr/share/fonts/opentype/inter/Inter-Black.otf"
INK = (20, 20, 35)
SKIN = (255, 206, 60)
PINK = (255, 92, 178)
PINK_DARK = (214, 50, 140)
YELLOW = (255, 222, 60)
DUCK = (255, 212, 40)
ORANGE = (255, 140, 30)
WHITE = (255, 255, 255)

def font(size):
    return ImageFont.truetype(FONT, int(size))

def layer(w, h):
    return Image.new("RGBA", (int(w), int(h)), (0, 0, 0, 0))

def paste(base, top, x, y):
    base.alpha_composite(top, (int(x), int(y)))

def paste_center(base, top, cx, cy):
    paste(base, top, cx - top.width / 2, cy - top.height / 2)

def lerp(a, b, t):
    return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(len(a)))

# --- backgrounds -----------------------------------------------------------

def vertical_gradient(img, top, bottom, y0=0, y1=None):
    d = ImageDraw.Draw(img)
    y1 = img.height if y1 is None else y1
    for y in range(int(y0), int(y1)):
        d.line([(0, y), (img.width, y)], fill=lerp(top, bottom, (y - y0) / max(1, y1 - y0)))

def rays(img, cx, cy, count, color_a, color_b, spin=0):
    d = ImageDraw.Draw(img)
    r = max(img.width, img.height) * 2
    d.rectangle([0, 0, img.width, img.height], fill=color_a)
    for i in range(count):
        if i % 2:
            continue
        a0 = spin + i * 2 * math.pi / count
        a1 = spin + (i + 1) * 2 * math.pi / count
        d.polygon([(cx, cy), (cx + r * math.cos(a0), cy + r * math.sin(a0)), (cx + r * math.cos(a1), cy + r * math.sin(a1))], fill=color_b)

def water(img, y, top=(60, 200, 245), bottom=(20, 110, 200), seed=1):
    vertical_gradient(img, top, bottom, y, img.height)
    d = ImageDraw.Draw(img)
    rnd = random.Random(seed)
    s = img.width / 3840
    for row in range(7):
        yy = y + 40 * s + row * (img.height - y) / 7
        for _ in range(5):
            x = rnd.uniform(-100, img.width)
            w = rnd.uniform(160, 420) * s
            pts = [(x + t * w, yy + math.sin(t * math.pi * 2) * 10 * s) for t in [i / 20 for i in range(21)]]
            d.line(pts, fill=(140, 225, 255), width=int(10 * s), joint="curve")

def deck(img, x0, x1, y, depth, seed=2):
    """A slice of pool deck seen from the front: white tiles + cyan coping."""
    d = ImageDraw.Draw(img)
    s = img.width / 3840
    d.rectangle([x0, y, x1, y + depth], fill=(245, 245, 240), outline=INK, width=int(8 * s))
    tile = 120 * s
    for x in range(int(x0), int(x1), int(tile)):
        d.line([(x, y), (x, y + depth)], fill=(215, 220, 225), width=int(4 * s))
    d.rectangle([x0, y + depth, x1, y + depth + 34 * s], fill=(70, 215, 235), outline=INK, width=int(8 * s))

# --- shapes --------------------------------------------------------------------

def outlined_ellipse(d, box, fill, w):
    d.ellipse(box, fill=fill, outline=INK, width=int(w))

def rot_rect(d, cx, cy, w, h, angle, fill, ow, pivot=None, radius=0):
    """Rectangle rotated by `angle` degrees around `pivot` (default its center)."""
    px, py = pivot if pivot else (cx, cy)
    a = math.radians(angle)
    pts = []
    for dx, dy in [(-w / 2, -h / 2), (w / 2, -h / 2), (w / 2, h / 2), (-w / 2, h / 2)]:
        x, y = cx + dx - px, cy + dy - py
        pts.append((px + x * math.cos(a) - y * math.sin(a), py + x * math.sin(a) + y * math.cos(a)))
    d.polygon(pts, fill=fill, outline=INK, width=int(ow))
    return pts

def burst(img, cx, cy, r_out, r_in, points, fill, ow, seed=3, outline=INK):
    d = ImageDraw.Draw(img)
    rnd = random.Random(seed)
    pts = []
    for i in range(points * 2):
        a = i * math.pi / points
        r = (r_out * rnd.uniform(0.85, 1.1)) if i % 2 == 0 else r_in
        pts.append((cx + r * math.cos(a), cy + r * math.sin(a)))
    d.polygon(pts, fill=fill, outline=outline, width=int(ow))

def text_layer(text, size, fill, stroke, stroke_fill=INK, shadow=0):
    f = font(size)
    bbox = f.getbbox(text, stroke_width=int(stroke))
    w, h = bbox[2] - bbox[0] + shadow + 20, bbox[3] - bbox[1] + shadow + 20
    t = layer(w, h)
    d = ImageDraw.Draw(t)
    if shadow:
        d.text((10 - bbox[0] + shadow, 10 - bbox[1] + shadow), text, font=f, fill=INK, stroke_width=int(stroke), stroke_fill=INK)
    d.text((10 - bbox[0], 10 - bbox[1]), text, font=f, fill=fill, stroke_width=int(stroke), stroke_fill=stroke_fill)
    return t

def rotated(img, angle):
    return img.rotate(angle, resample=Image.BICUBIC, expand=True)

# --- noodle ------------------------------------------------------------------------

def bezier(p0, p1, p2, steps=80):
    out = []
    for i in range(steps + 1):
        t = i / steps
        out.append(((1 - t) ** 2 * p0[0] + 2 * (1 - t) * t * p1[0] + t * t * p2[0],
                    (1 - t) ** 2 * p0[1] + 2 * (1 - t) * t * p1[1] + t * t * p2[1]))
    return out

def noodle(img, p0, p1, p2, width, color=PINK, ridge=PINK_DARK, ow=8):
    d = ImageDraw.Draw(img)
    pts = bezier(p0, p1, p2)
    r = width / 2
    for x, y in pts:
        d.ellipse([x - r - ow, y - r - ow, x + r + ow, y + r + ow], fill=INK)
    for x, y in pts:
        d.ellipse([x - r, y - r, x + r, y + r], fill=color)
    # ridges across the foam
    for i in range(6, len(pts) - 4, 7):
        (x0, y0), (x1, y1) = pts[i - 1], pts[i + 1]
        nx, ny = -(y1 - y0), x1 - x0
        n = math.hypot(nx, ny) or 1
        nx, ny = nx / n * r * 0.85, ny / n * r * 0.85
        x, y = pts[i]
        d.line([(x - nx, y - ny), (x + nx, y + ny)], fill=ridge, width=int(width * 0.12))
    # shine: one soft highlight along the top edge
    shine = [(x - r * 0.15, y - r * 0.5) for x, y in pts[5:-6]]
    d.line(shine, fill=(255, 185, 225), width=int(width * 0.16), joint="curve")
    # hollow end
    ex, ey = pts[-1]
    d.ellipse([ex - r * 0.45, ey - r * 0.45, ex + r * 0.45, ey + r * 0.45], fill=PINK_DARK, outline=INK, width=int(ow * 0.6))
    return pts

def motion_lines(img, x, y, angle, count, length, spread, width, color=WHITE):
    d = ImageDraw.Draw(img)
    a = math.radians(angle)
    ux, uy = math.cos(a), math.sin(a)
    nx, ny = -uy, ux
    for i in range(count):
        off = (i - (count - 1) / 2) * spread
        l = length * (0.6 + 0.4 * ((i * 7) % 5) / 4)
        sx, sy = x + nx * off, y + ny * off
        d.line([(sx, sy), (sx + ux * l, sy + uy * l)], fill=INK, width=int(width + 8))
        d.line([(sx, sy), (sx + ux * l, sy + uy * l)], fill=color, width=int(width))

def splash(img, cx, cy, size, seed=5):
    d = ImageDraw.Draw(img)
    rnd = random.Random(seed)
    ow = max(4, size * 0.04)
    # body of the splash
    pts = []
    for i in range(14):
        a = math.pi + i * math.pi / 13
        r = size * (1.0 if i % 2 else 0.55) * rnd.uniform(0.8, 1.2)
        pts.append((cx + r * math.cos(a) * 1.3, cy + r * math.sin(a)))
    d.polygon(pts, fill=(225, 248, 255), outline=INK, width=int(ow))
    d.ellipse([cx - size * 1.3, cy - size * 0.18, cx + size * 1.3, cy + size * 0.18], fill=(225, 248, 255), outline=INK, width=int(ow))
    # flying drops
    for _ in range(9):
        a = rnd.uniform(math.pi * 1.1, math.pi * 1.9)
        r = rnd.uniform(size * 1.1, size * 1.8)
        x, y = cx + math.cos(a) * r * 1.2, cy + math.sin(a) * r
        s = rnd.uniform(size * 0.07, size * 0.14)
        d.ellipse([x - s, y - s, x + s, y + s], fill=(225, 248, 255), outline=INK, width=int(ow * 0.8))

# --- characters ------------------------------------------------------------------------

def character(scale, shirt=(80, 200, 120), pants=(50, 60, 90), face="grin",
              arm_l=20, arm_r=-20, leg_l=8, leg_r=-8, hair=(60, 40, 30)):
    """A blocky cartoon avatar drawn upright on its own layer. Arm/leg angles in
    degrees (0 = hanging down, positive = swung toward the left of the image)."""
    s = scale
    w, h = int(640 * s), int(640 * s)  # wide, so raised arms aren't cut off
    img = layer(w, h)
    d = ImageDraw.Draw(img)
    ow = 9 * s
    cx = w / 2
    # legs (behind torso)
    hip_y = 410 * s
    for side, ang in ((-1, leg_l), (1, leg_r)):
        hx = cx + side * 38 * s
        rot_rect(d, hx, hip_y + 70 * s, 76 * s, 150 * s, ang, pants, ow, pivot=(hx, hip_y))
    # torso
    d.rounded_rectangle([cx - 85 * s, 235 * s, cx + 85 * s, 420 * s], radius=int(16 * s), fill=shirt, outline=INK, width=int(ow))
    # arms
    sh_y = 255 * s
    for side, ang in ((-1, arm_l), (1, arm_r)):
        sx = cx + side * 115 * s
        pts = rot_rect(d, sx, sh_y + 75 * s, 64 * s, 160 * s, ang, shirt, ow, pivot=(sx, sh_y))
        # hand
        hx = (pts[2][0] + pts[3][0]) / 2
        hy = (pts[2][1] + pts[3][1]) / 2
        d.ellipse([hx - 30 * s, hy - 30 * s, hx + 30 * s, hy + 30 * s], fill=SKIN, outline=INK, width=int(ow))
    # head
    d.rounded_rectangle([cx - 105 * s, 30 * s, cx + 105 * s, 235 * s], radius=int(60 * s), fill=SKIN, outline=INK, width=int(ow))
    # hair
    d.chord([cx - 108 * s, 5 * s, cx + 108 * s, 150 * s], 180, 360, fill=hair, outline=INK, width=int(ow))
    # face
    ey = 130 * s
    if face == "shock":
        for ex in (cx - 45 * s, cx + 45 * s):
            d.ellipse([ex - 30 * s, ey - 34 * s, ex + 30 * s, ey + 34 * s], fill=WHITE, outline=INK, width=int(ow * 0.8))
            d.ellipse([ex - 11 * s, ey - 11 * s, ex + 11 * s, ey + 11 * s], fill=INK)
        d.ellipse([cx - 28 * s, 175 * s, cx + 28 * s, 222 * s], fill=(120, 30, 40), outline=INK, width=int(ow * 0.8))
    else:
        for ex in (cx - 45 * s, cx + 45 * s):
            d.ellipse([ex - 22 * s, ey - 26 * s, ex + 22 * s, ey + 26 * s], fill=WHITE, outline=INK, width=int(ow * 0.8))
            d.ellipse([ex - 6 * s, ey - 14 * s, ex + 14 * s, ey + 6 * s], fill=INK)
        # brows: mischievous
        d.line([(cx - 72 * s, 92 * s), (cx - 22 * s, 104 * s)], fill=INK, width=int(ow * 1.2))
        d.line([(cx + 72 * s, 92 * s), (cx + 22 * s, 104 * s)], fill=INK, width=int(ow * 1.2))
        d.chord([cx - 60 * s, 150 * s, cx + 60 * s, 222 * s], 0, 180, fill=WHITE, outline=INK, width=int(ow))
    return img

def hand_point(scale, arm_angle, side):
    """Where the hand ends up on a character() layer, for attaching noodles."""
    s = scale
    cx = 320 * s
    sx = cx + side * 115 * s
    sy = 255 * s
    a = math.radians(arm_angle)
    dx, dy = 0, 150 * s
    return (sx + dx * math.cos(a) - dy * math.sin(a), sy + dx * math.sin(a) + dy * math.cos(a))

# --- duck ------------------------------------------------------------------------------------

def rubber_duck(scale, angry=False, facing=-1):
    s = scale
    w, h = int(900 * s), int(820 * s)
    img = layer(w, h)
    d = ImageDraw.Draw(img)
    ow = 12 * s
    # body
    d.ellipse([60 * s, 330 * s, 860 * s, 800 * s], fill=DUCK, outline=INK, width=int(ow))
    # tail
    d.polygon([(800 * s, 470 * s), (890 * s, 330 * s), (830 * s, 560 * s)], fill=DUCK, outline=INK, width=int(ow))
    # wing
    d.chord([380 * s, 470 * s, 700 * s, 700 * s], 200, 360, fill=(240, 185, 20), outline=INK, width=int(ow))
    # head
    d.ellipse([150 * s, 60 * s, 520 * s, 430 * s], fill=DUCK, outline=INK, width=int(ow))
    # beak
    d.rounded_rectangle([20 * s, 250 * s, 230 * s, 330 * s], radius=int(40 * s), fill=ORANGE, outline=INK, width=int(ow))
    d.line([(40 * s, 292 * s), (210 * s, 292 * s)], fill=INK, width=int(ow * 0.7))
    # eye
    d.ellipse([235 * s, 150 * s, 335 * s, 260 * s], fill=WHITE, outline=INK, width=int(ow * 0.8))
    d.ellipse([255 * s, 185 * s, 300 * s, 235 * s], fill=INK)
    d.ellipse([268 * s, 192 * s, 284 * s, 208 * s], fill=WHITE)
    if angry:
        d.polygon([(215 * s, 130 * s), (360 * s, 160 * s), (350 * s, 185 * s), (210 * s, 160 * s)], fill=INK)
    # shine
    d.ellipse([380 * s, 120 * s, 440 * s, 170 * s], fill=(255, 245, 190))
    if facing > 0:
        img = img.transpose(Image.FLIP_LEFT_RIGHT)
    return img

def hp_bar(img, x, y, w, h, fraction, label=None):
    d = ImageDraw.Draw(img)
    ow = max(6, h * 0.12)
    d.rounded_rectangle([x, y, x + w, y + h], radius=int(h / 2), fill=(40, 40, 55), outline=INK, width=int(ow))
    d.rounded_rectangle([x + ow, y + ow, x + ow + (w - 2 * ow) * fraction, y + h - ow], radius=int(h / 2), fill=(240, 70, 60))
    if label:
        t = text_layer(label, h * 0.55, WHITE, h * 0.08)
        paste_center(img, t, x + w / 2, y + h / 2)

def finish(img, size, path):
    out = img.convert("RGB").resize(size, Image.LANCZOS)
    out.save(path, quality=95)
    return out
