import sys
sys.path.insert(0, ".")
from kit import *

W, H = 3840, 2160
img = layer(W, H)
rays(img, 2600, 700, 26, (20, 175, 200), (50, 205, 225))
water(img, 1560, top=(80, 205, 245), bottom=(25, 105, 195))
deck(img, -60, 1300, 1430, 130)

# attacker, small, on the deck edge, after the swing
S = 1.35
att = character(S, shirt=(255, 105, 180), face="grin", arm_l=40, arm_r=-95, leg_l=14, leg_r=-12, hair=(30, 30, 30))
ax, ay = 650 - 320 * S, 1430 - 560 * S
hx, hy = hand_point(S, -95, 1)
noodle(img, (ax + hx, ay + hy), (1150, 250), (1450, 700), 110, ow=12)
paste(img, att, ax, ay)

# water trail behind the soaked flyer
for i in range(10):
    t = i / 9
    x, y = 1500 + t * 1250, 900 - math.sin(t * math.pi) * 330 - t * 200
    r = 30 + 55 * (1 - t)
    ImageDraw.Draw(img).ellipse([x - r, y - r, x + r, y + r], fill=(225, 248, 255), outline=INK, width=8)
motion_lines(img, 2600, 620, 200, 6, 420, 80, 20)

# the soaked victim, launched hard
vic = character(1.75, shirt=(255, 210, 40), face="shock", arm_l=160, arm_r=-170, leg_l=55, leg_r=-20, hair=(120, 70, 30))
paste_center(img, rotated(vic, 55), 3120, 640)
# drips falling off them
for dx, dy in [(-260, 380), (-120, 470), (40, 520), (200, 430), (330, 330)]:
    x, y = 3120 + dx, 600 + dy
    ImageDraw.Draw(img).ellipse([x - 22, y - 32, x + 22, y + 32], fill=(150, 220, 255), outline=INK, width=7)

# the big number
pct = text_layer("200%", 560, (90, 200, 255), 40, stroke_fill=INK, shadow=26)
paste_center(img, rotated(pct, 8), 1900, 1240)
paste_center(img, rotated(text_layer("SOAKED!", 260, WHITE, 24, shadow=16), 8), 1980, 1660)

# logo
paste(img, rotated(text_layer("NOODLE", 230, WHITE, 20, shadow=14), 3), 60, 40)
paste(img, rotated(text_layer("BONK", 300, YELLOW, 24, shadow=16), 3), 80, 280)

finish(img, (1920, 1080), "thumb_3_soaked.png")
