# 2D thumbnails and icons

Flat cartoon art for the game page, drawn with Python + Pillow (no 3D).
`kit.py` has the pieces (characters, noodles, rubber duck, comic bursts,
water); the other scripts compose them.

```bash
pip install pillow
cd tools/art && python t1.py && python t2.py && python t3.py && python icons.py
```

They write PNGs into the current folder; the finished ones live in
`marketing/v2/` (thumbnails 1920x1080, icons 512x512). The font path in
`kit.py` points at Inter Black; change `FONT` if you don't have it.
