"""Generate cute animal vector-style art for puzzle game — with gradient backgrounds."""
import math
import os
import random
from PIL import Image, ImageDraw

W, H = 800, 1200
ASSETS = os.path.join(os.path.dirname(__file__), "..", "assets")
LINE_W = 8


def lerp_color(c1, c2, t):
    t = max(0, min(1, t))
    return tuple(int(c1[i] + (c2[i] - c1[i]) * t) for i in range(3))


def make_gradient(w, h, colors, style="diagonal"):
    """Create a gradient background image.
    style: 'diagonal', 'radial', 'vertical', 'conic'
    """
    img = Image.new("RGB", (w, h))
    px = img.load()
    cx, cy = w // 2, h // 2
    for y in range(h):
        for x in range(w):
            if style == "diagonal":
                t = (x / w + y / h) / 2.0
            elif style == "radial":
                t = math.sqrt((x - cx) ** 2 + (y - cy) ** 2) / (math.sqrt(cx ** 2 + cy ** 2))
            elif style == "vertical":
                t = y / h
            elif style == "conic":
                angle = math.atan2(y - cy, x - cx)
                t = (angle + math.pi) / (2 * math.pi)
            else:
                t = y / h
            t = max(0, min(1, t))
            seg = t * (len(colors) - 1)
            i = min(int(seg), len(colors) - 2)
            local_t = seg - i
            px[x, y] = lerp_color(colors[i], colors[i + 1], local_t)
    return img


def draw_on(img, func):
    """Run a drawing function on an image, return it."""
    func(ImageDraw.Draw(img))
    return img


# ============================================================
# 1. CAT — soft orange tabby on lavender-to-rose diagonal gradient
# ============================================================
print("Generating cat.png ...")
img = make_gradient(W, H, [
    (180, 150, 210), (200, 160, 200), (230, 170, 190), (240, 180, 195)
], style="diagonal")
d = ImageDraw.Draw(img)

cx, cy = W // 2, H // 2 + 40

# Ears (triangles)
ear_color = (240, 160, 80)
ear_inner = (255, 180, 150)
for side in [-1, 1]:
    ex = cx + side * 180
    ey = cy - 250
    pts_outer = [(ex - 80, ey + 120), (ex, ey - 80), (ex + 80, ey + 120)]
    pts_inner = [(ex - 45, ey + 90), (ex, ey - 30), (ex + 45, ey + 90)]
    d.polygon(pts_outer, fill=ear_color, outline="black", width=LINE_W)
    d.polygon(pts_inner, fill=ear_inner)

# Head
d.ellipse([cx - 200, cy - 200, cx + 200, cy + 200], fill=ear_color, outline="black", width=LINE_W)

# Eyes
for side in [-1, 1]:
    ex = cx + side * 75
    ey = cy - 40
    d.ellipse([ex - 35, ey - 40, ex + 35, ey + 40], fill="white", outline="black", width=LINE_W)
    d.ellipse([ex - 18, ey - 25, ex + 18, ey + 25], fill=(40, 40, 40))
    d.ellipse([ex - 8, ey - 15, ex + 4, ey - 5], fill="white")

# Nose
d.polygon([(cx, cy + 10), (cx - 18, cy + 40), (cx + 18, cy + 40)],
          fill=(255, 130, 130), outline="black", width=LINE_W)

# Mouth
d.arc([cx - 50, cy + 30, cx, cy + 80], 0, 180, fill="black", width=LINE_W)
d.arc([cx, cy + 30, cx + 50, cy + 80], 0, 180, fill="black", width=LINE_W)

# Whiskers
for side in [-1, 1]:
    bx = cx + side * 50
    by = cy + 50
    for angle in [-15, 0, 15]:
        ex = bx + side * 180
        ey = by + int(50 * math.sin(math.radians(angle)))
        d.line([(bx, by), (ex, ey)], fill="black", width=LINE_W)

img.save(os.path.join(ASSETS, "cat.png"))

# ============================================================
# 2. DOG — happy golden retriever on teal-to-mint radial gradient
# ============================================================
print("Generating dog.png ...")
img = make_gradient(W, H, [
    (30, 80, 90), (50, 130, 120), (100, 190, 170), (150, 220, 200)
], style="radial")
d = ImageDraw.Draw(img)

cx, cy = W // 2, H // 2 + 40
dog_color = (210, 170, 100)
dog_dark = (170, 130, 70)

# Floppy ears
for side in [-1, 1]:
    ex = cx + side * 190
    ey = cy - 120
    d.ellipse([ex - 60, ey - 40, ex + 60, ey + 160], fill=dog_dark, outline="black", width=LINE_W)

# Head
d.ellipse([cx - 190, cy - 200, cx + 190, cy + 200], fill=dog_color, outline="black", width=LINE_W)

# Muzzle (lighter area)
d.ellipse([cx - 100, cy + 10, cx + 100, cy + 150], fill=(240, 220, 180), outline="black", width=LINE_W)

# Eyes
for side in [-1, 1]:
    ex = cx + side * 70
    ey = cy - 50
    d.ellipse([ex - 28, ey - 28, ex + 28, ey + 28], fill=(40, 30, 20), outline="black", width=LINE_W)
    d.ellipse([ex - 10, ey - 15, ex + 2, ey - 5], fill="white")

# Nose
d.ellipse([cx - 25, cy + 25, cx + 25, cy + 60], fill=(50, 40, 35), outline="black", width=LINE_W)

# Mouth / smile
d.arc([cx - 60, cy + 50, cx, cy + 110], 0, 180, fill="black", width=LINE_W)
d.arc([cx, cy + 50, cx + 60, cy + 110], 0, 180, fill="black", width=LINE_W)

# Tongue
d.ellipse([cx - 20, cy + 90, cx + 20, cy + 150], fill=(240, 120, 120), outline="black", width=LINE_W)

img.save(os.path.join(ASSETS, "dog.png"))

# ============================================================
# 3. BUNNY — white bunny on pink-to-peach vertical gradient
# ============================================================
print("Generating bunny.png ...")
img = make_gradient(W, H, [
    (230, 140, 170), (240, 170, 180), (250, 200, 180), (255, 220, 190)
], style="vertical")
d = ImageDraw.Draw(img)

cx, cy = W // 2, H // 2 + 80
bunny = (250, 248, 245)
bunny_inner = (255, 200, 200)

# Long ears
for side in [-1, 1]:
    ex = cx + side * 85
    ey = cy - 350
    d.ellipse([ex - 45, ey, ex + 45, ey + 280], fill=bunny, outline="black", width=LINE_W)
    d.ellipse([ex - 25, ey + 30, ex + 25, ey + 240], fill=bunny_inner)

# Head
d.ellipse([cx - 170, cy - 170, cx + 170, cy + 170], fill=bunny, outline="black", width=LINE_W)

# Eyes
for side in [-1, 1]:
    ex = cx + side * 65
    ey = cy - 20
    d.ellipse([ex - 22, ey - 22, ex + 22, ey + 22], fill=(40, 20, 30), outline="black", width=LINE_W)
    d.ellipse([ex - 8, ey - 12, ex + 2, ey - 4], fill="white")

# Nose
d.polygon([(cx, cy + 30), (cx - 12, cy + 50), (cx + 12, cy + 50)],
          fill=(255, 150, 160), outline="black", width=LINE_W)

# Mouth
d.arc([cx - 30, cy + 45, cx, cy + 80], 0, 180, fill="black", width=LINE_W)
d.arc([cx, cy + 45, cx + 30, cy + 80], 0, 180, fill="black", width=LINE_W)

# Cheek blush
for side in [-1, 1]:
    bx = cx + side * 120
    by = cy + 40
    d.ellipse([bx - 30, by - 15, bx + 30, by + 15], fill=(255, 180, 190))

img.save(os.path.join(ASSETS, "bunny.png"))

# ============================================================
# 4. OWL — wise owl on deep blue-to-purple conic gradient
# ============================================================
print("Generating owl.png ...")
img = make_gradient(W, H, [
    (15, 10, 50), (20, 30, 80), (30, 50, 100), (50, 30, 90), (40, 15, 60)
], style="conic")
d = ImageDraw.Draw(img)

cx, cy = W // 2, H // 2
owl_body = (140, 100, 60)
owl_belly = (200, 175, 140)

# Ear tufts
for side in [-1, 1]:
    tx = cx + side * 140
    ty = cy - 230
    pts = [(tx - 40, ty + 80), (tx, ty - 50), (tx + 40, ty + 80)]
    d.polygon(pts, fill=owl_body, outline="black", width=LINE_W)

# Body
d.ellipse([cx - 180, cy - 180, cx + 180, cy + 250], fill=owl_body, outline="black", width=LINE_W)

# Belly patch
d.ellipse([cx - 110, cy - 20, cx + 110, cy + 220], fill=owl_belly, outline="black", width=LINE_W)

# Belly feather lines
for i in range(5):
    yy = cy + 30 + i * 35
    d.arc([cx - 80, yy, cx + 80, yy + 25], 0, 180, fill=(160, 120, 70), width=3)

# Big eyes
for side in [-1, 1]:
    ex = cx + side * 80
    ey = cy - 50
    d.ellipse([ex - 60, ey - 60, ex + 60, ey + 60], fill=(240, 230, 200), outline="black", width=LINE_W)
    d.ellipse([ex - 38, ey - 38, ex + 38, ey + 38], fill=(200, 150, 30), outline="black", width=LINE_W)
    d.ellipse([ex - 20, ey - 20, ex + 20, ey + 20], fill=(30, 20, 10))
    d.ellipse([ex - 10, ey - 18, ex + 2, ey - 8], fill="white")

# Beak
d.polygon([(cx, cy + 10), (cx - 18, cy + 40), (cx + 18, cy + 40)],
          fill=(230, 160, 50), outline="black", width=LINE_W)

# Feet
for side in [-1, 1]:
    fx = cx + side * 70
    fy = cy + 240
    for toe in [-1, 0, 1]:
        d.ellipse([fx + toe * 25 - 12, fy, fx + toe * 25 + 12, fy + 30],
                  fill=(230, 160, 50), outline="black", width=LINE_W)

img.save(os.path.join(ASSETS, "owl.png"))

# ============================================================
# 5. BEAR — brown bear on warm yellow-to-orange diagonal gradient
# ============================================================
print("Generating bear.png ...")
img = make_gradient(W, H, [
    (255, 200, 80), (255, 170, 60), (240, 130, 50), (220, 90, 40)
], style="diagonal")
d = ImageDraw.Draw(img)

cx, cy = W // 2, H // 2 + 30
bear = (140, 95, 55)
bear_light = (190, 150, 100)

# Ears
for side in [-1, 1]:
    ex = cx + side * 175
    ey = cy - 200
    d.ellipse([ex - 55, ey - 55, ex + 55, ey + 55], fill=bear, outline="black", width=LINE_W)
    d.ellipse([ex - 30, ey - 30, ex + 30, ey + 30], fill=bear_light)

# Head
d.ellipse([cx - 210, cy - 210, cx + 210, cy + 210], fill=bear, outline="black", width=LINE_W)

# Muzzle
d.ellipse([cx - 90, cy + 10, cx + 90, cy + 140], fill=bear_light, outline="black", width=LINE_W)

# Eyes
for side in [-1, 1]:
    ex = cx + side * 80
    ey = cy - 30
    d.ellipse([ex - 22, ey - 22, ex + 22, ey + 22], fill=(30, 20, 10), outline="black", width=LINE_W)
    d.ellipse([ex - 8, ey - 12, ex + 2, ey - 4], fill="white")

# Nose
d.ellipse([cx - 22, cy + 30, cx + 22, cy + 60], fill=(50, 40, 30), outline="black", width=LINE_W)

# Mouth
d.arc([cx - 40, cy + 55, cx, cy + 95], 0, 180, fill="black", width=LINE_W)
d.arc([cx, cy + 55, cx + 40, cy + 95], 0, 180, fill="black", width=LINE_W)

img.save(os.path.join(ASSETS, "bear.png"))

print("Done! Generated 5 animal images with gradient backgrounds.")
