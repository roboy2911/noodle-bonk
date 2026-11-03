import sys
sys.path.insert(0, ".")
from kit import *

W, H = 3840, 2160
img = layer(W, H)
rays(img, 2300, 700, 28, (40, 165, 240), (75, 195, 252))
water(img, 1400)
deck(img, -60, 1500, 1250, 130)

# attacker on the deck, swinging up and across
S = 1.75
arm_r = -128
att = character(S, shirt=(70, 200, 110), face="grin", arm_l=35, arm_r=arm_r, leg_l=14, leg_r=-10)
ax, ay = 420 - 140 * S, 1250 - 560 * S  # top-left so feet land on the deck
hx, hy = hand_point(S, arm_r, 1)
noodle(img, (ax + hx, ay + hy), (1350, -60), (2250, 560), 140, ow=14)
paste(img, att, ax, ay)
motion_lines(img, 1500, 200, 170, 4, 260, 70, 22)

# victim flying off, with a splash below
vic = character(2.1, shirt=(80, 140, 255), face="shock", arm_l=150, arm_r=-150, leg_l=30, leg_r=-35, hair=(230, 120, 40))
paste_center(img, rotated(vic, -28), 3080, 640)
motion_lines(img, 2700, 900, 205, 5, 330, 75, 20)
splash(img, 3250, 1560, 250)

# BONK! burst at the impact
burst(img, 2300, 560, 420, 260, 14, YELLOW, 16)
paste_center(img, rotated(text_layer("BONK!", 240, (255, 70, 120), 20), 12), 2300, 560)

# title
title1 = text_layer("NOODLE", 290, WHITE, 24, shadow=16)
title2 = text_layer("BONK", 400, YELLOW, 30, shadow=20)
paste(img, rotated(title1, 3), 70, 1330)
paste(img, rotated(title2, 3), 90, 1600)

finish(img, (1920, 1080), "thumb_1_bonk.png")
