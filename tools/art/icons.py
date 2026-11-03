import sys
sys.path.insert(0, ".")
from kit import *

N = 1024

def head_on(img, scale, cx, cy, angle, **kw):
    c = character(scale, **kw)
    # crop to just the head (and a bit of shoulders)
    c = c.crop((0, 0, c.width, int(270 * scale)))
    r = rotated(c, angle)
    paste_center(img, r, cx, cy + 20 * scale)

# 1: shocked face getting bonked
img = layer(N, N)
rays(img, 560, 560, 22, (40, 165, 240), (80, 200, 252))
head_on(img, 2.6, 600, 620, -14, shirt=(80, 140, 255), face="shock", hair=(230, 120, 40))
noodle(img, (-60, 260), (180, -80), (440, 330), 120, ow=12)
motion_lines(img, 300, 120, 200, 3, 170, 55, 14)
burst(img, 380, 400, 190, 120, 12, YELLOW, 10, seed=11)
paste_center(img, rotated(text_layer("BONK!", 92, (255, 70, 120), 10), 14), 380, 400)
for x, y, r in [(820, 820, 30), (880, 720, 20), (760, 900, 18), (900, 860, 14)]:
    ImageDraw.Draw(img).ellipse([x - r, y - r * 1.4, x + r, y + r * 1.4], fill=(150, 220, 255), outline=INK, width=6)
finish(img, (512, 512), "icon_1_bonk_face.png")

# 2: the giant duck boss getting bonked
img = layer(N, N)
rays(img, 512, 560, 22, (120, 60, 200), (160, 100, 238))
duck = rubber_duck(1.0, angry=True)
paste(img, duck, 80, 250)
noodle(img, (1150, 760), (1000, 20), (560, 250), 120, ow=12)
motion_lines(img, 900, 110, 150, 3, 150, 55, 14)
burst(img, 450, 270, 170, 105, 12, YELLOW, 10, seed=12)
paste_center(img, rotated(text_layer("BONK!", 78, (255, 70, 120), 9), -12), 450, 270)
finish(img, (512, 512), "icon_2_duck.png")

# 3: grinning noodle bonker, mid-swing
img = layer(N, N)
rays(img, 512, 512, 22, (255, 150, 40), (255, 190, 70))
water(img, 860, top=(80, 205, 245), bottom=(30, 110, 200))
S = 1.45
c = character(S, shirt=(70, 200, 110), face="grin", arm_l=30, arm_r=-140, leg_l=10, leg_r=-10)
cx0, cy0 = 330 - 320 * S, 980 - 560 * S
hx, hy = hand_point(S, -140, 1)
noodle(img, (cx0 + hx, cy0 + hy), (720, -120), (880, 400), 110, ow=12)
paste(img, c, cx0, cy0)
motion_lines(img, 870, 150, 120, 3, 160, 55, 14)
burst(img, 840, 520, 190, 120, 12, YELLOW, 10, seed=13)
paste_center(img, rotated(text_layer("BONK!", 88, (255, 70, 120), 10), 12), 840, 520)
finish(img, (512, 512), "icon_3_bonker.png")

# preview: all three, with Roblox-style rounded corners
from PIL import Image as I
prev = I.new("RGB", (1600, 540), (235, 235, 240))
for i, name in enumerate(["icon_1_bonk_face.png", "icon_2_duck.png", "icon_3_bonker.png"]):
    im = I.open(name).convert("RGBA")
    mask = I.new("L", im.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, 511, 511], radius=90, fill=255)
    prev.paste(im, (14 + i * 530, 14), mask)
prev.save("check_icons.jpg")
