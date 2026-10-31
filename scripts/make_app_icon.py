#!/usr/bin/env python3
# Generates the placeholder 1024x1024 no-alpha app icon (pickleball on the accent colour) into both asset catalogs; replace the PNGs to change the icon.
import math
from PIL import Image, ImageDraw

SIZE, SS = 1024, 4  # final size, supersampling factor
ACCENT = (10, 100, 220)  # AccentColor light value from Assets.xcassets (0.039, 0.392, 0.863)
CREAM = (255, 248, 230)

big = SS * SIZE
img = Image.new("RGB", (big, big), ACCENT)
d = ImageDraw.Draw(img)
c = big / 2
R = 0.36 * big
d.ellipse([c - R, c - R, c + R, c + R], fill=CREAM)

def hole(x, y, r):
    d.ellipse([x - r, y - r, x + r, y + r], fill=ACCENT)

hr = 0.034 * big
hole(c, c, hr)
for ring_r, count, offset in ((0.115 * big, 6, 0), (0.215 * big, 12, math.pi / 12)):
    for i in range(count):
        a = offset + 2 * math.pi * i / count - math.pi / 2
        hole(c + ring_r * math.cos(a), c + ring_r * math.sin(a), hr)

img = img.resize((SIZE, SIZE), Image.LANCZOS)
for path in ("ServerTwo/Assets.xcassets/AppIcon.appiconset/AppIcon.png",
             "ServerTwo Watch App/Assets.xcassets/AppIcon.appiconset/AppIcon.png"):
    img.save(path, "PNG")
