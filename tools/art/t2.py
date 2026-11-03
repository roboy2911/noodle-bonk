import sys
sys.path.insert(0, ".")
from kit import *

W, H = 3840, 2160
img = layer(W, H)
rays(img, 2700, 800, 30, (120, 60, 200), (155, 95, 235))
water(img, 1640, top=(70, 190, 245), bottom=(30, 100, 190))
deck(img, -60, 3900, 1500, 130)

# the giant duck, angry, on the right
duck = rubber_duck(1.75, angry=True)
paste(img, duck, 3840 - duck.width + 60, 1515 - duck.height + 20)
hp_bar(img, 2180, 70, 1500, 120, 0.62, "GIANT DUCK  1240 / 2000")

# players ganging up on it
def fighter(x, shirt, arm_r, tip, ctrl, scale=1.25, face="grin"):
    c = character(scale, shirt=shirt, face=face, arm_l=30, arm_r=arm_r, leg_l=12, leg_r=-14)
    cx0, cy0 = x - c.width / 2, 1500 - 560 * scale
    hx, hy = hand_point(scale, arm_r, 1)
    noodle(img, (cx0 + hx, cy0 + hy), ctrl, tip, 95, ow=11)
    paste(img, c, cx0, cy0)

fighter(1350, (70, 200, 110), -120, (2280, 860), (1700, 300))
fighter(1900, (255, 120, 60), -100, (2420, 1180), (2250, 700), scale=1.1)

# someone getting belly-bumped into the air
bumped = character(1.0, shirt=(80, 140, 255), face="shock", arm_l=140, arm_r=-150, leg_l=40, leg_r=-30, hair=(230, 120, 40))
paste_center(img, rotated(bumped, 35), 2330, 560)
motion_lines(img, 2520, 790, 40, 4, 200, 55, 16)
burst(img, 2330, 990, 210, 130, 12, YELLOW, 12, seed=8)
paste_center(img, rotated(text_layer("QUACK!", 105, (255, 90, 40), 12), -10), 2330, 990)

# title
paste(img, rotated(text_layer("GIANT DUCK", 255, YELLOW, 22, shadow=16), 3), 70, 60)
paste(img, rotated(text_layer("BOSS!", 380, (255, 80, 80), 30, shadow=20), 3), 90, 320)
burst(img, 1520, 560, 190, 130, 12, (255, 80, 80), 12, seed=4)
paste_center(img, rotated(text_layer("NEW", 105, WHITE, 12), -12), 1520, 560)

# logo
paste(img, text_layer("NOODLE BONK", 200, WHITE, 18, shadow=12), 70, 1820)

finish(img, (1920, 1080), "thumb_2_duck_boss.png")
