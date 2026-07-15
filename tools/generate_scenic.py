"""Generate scenic landscape art for puzzle game."""
import math
import os
import random
from PIL import Image, ImageDraw

W, H = 800, 1200
ASSETS = os.path.join(os.path.dirname(__file__), "assets")
random.seed(99)


def lerp_color(c1, c2, t):
    t = max(0, min(1, t))
    return tuple(int(c1[i] + (c2[i] - c1[i]) * t) for i in range(3))


def vertical_gradient(img, top_color, bottom_color):
    px = img.load()
    w, h = img.size
    for y in range(h):
        c = lerp_color(top_color, bottom_color, y / h)
        for x in range(w):
            px[x, y] = c


# ============================================================
# 1. MOUNTAIN SUNSET — layered mountain silhouettes
# ============================================================
print("Generating mountain_sunset.png ...")
img = Image.new("RGB", (W, H))
px = img.load()

# Sky gradient
for y in range(H):
    t = y / H
    if t < 0.45:
        # Sky: deep blue to warm orange
        st = t / 0.45
        c = lerp_color((20, 20, 80), (255, 140, 60), st)
    elif t < 0.55:
        # Horizon glow
        st = (t - 0.45) / 0.1
        c = lerp_color((255, 140, 60), (255, 200, 100), st)
    else:
        # Ground
        st = (t - 0.55) / 0.45
        c = lerp_color((60, 40, 30), (30, 20, 15), st)
    for x in range(W):
        px[x, y] = c

draw = ImageDraw.Draw(img)

# Sun
sun_y = int(H * 0.42)
for r in range(120, 0, -1):
    alpha_t = r / 120
    c = lerp_color((255, 255, 200), (255, 180, 80), alpha_t)
    draw.ellipse([W // 2 - r, sun_y - r, W // 2 + r, sun_y + r], fill=c)

# Mountain layers (back to front, darker to lighter)
mountain_colors = [(60, 50, 70), (50, 40, 55), (40, 35, 40), (35, 30, 30)]
mountain_heights = [0.35, 0.42, 0.50, 0.58]
mountain_roughness = [0.12, 0.10, 0.08, 0.06]

for layer_idx in range(len(mountain_colors)):
    base_y = int(H * mountain_heights[layer_idx])
    rough = mountain_heights[layer_idx]
    points = [(0, H)]
    for x in range(0, W + 1, 4):
        # Multiple sine waves for natural-looking ridgeline
        n = 0
        n += math.sin(x / 200.0 + layer_idx * 2) * rough * H * 0.4
        n += math.sin(x / 80.0 + layer_idx * 5) * rough * H * 0.15
        n += math.sin(x / 350.0 + layer_idx) * rough * H * 0.25
        y = base_y + int(n)
        points.append((x, y))
    points.append((W, H))
    draw.polygon(points, fill=mountain_colors[layer_idx])

img.save(os.path.join(ASSETS, "mountain_sunset.png"))

# ============================================================
# 2. OCEAN WAVES — beach scene with layered waves
# ============================================================
print("Generating ocean_waves.png ...")
img = Image.new("RGB", (W, H))
px = img.load()

# Sky
for y in range(H):
    t = y / H
    if t < 0.35:
        st = t / 0.35
        c = lerp_color((100, 180, 240), (180, 220, 255), st)
    elif t < 0.42:
        # Horizon haze
        st = (t - 0.35) / 0.07
        c = lerp_color((180, 220, 255), (200, 210, 200), st)
    elif t < 0.55:
        # Ocean
        st = (t - 0.42) / 0.13
        c = lerp_color((40, 120, 180), (20, 80, 140), st)
    elif t < 0.65:
        # Shallow water / surf
        st = (t - 0.55) / 0.1
        c = lerp_color((100, 180, 200), (200, 210, 180), st)
    else:
        # Sand
        st = (t - 0.65) / 0.35
        c = lerp_color((220, 200, 150), (180, 150, 100), st)
    for x in range(W):
        px[x, y] = c

draw = ImageDraw.Draw(img)

# Waves (white foam lines)
for wave_y in [0.44, 0.48, 0.52]:
    for x in range(0, W, 2):
        wy = int(H * wave_y + math.sin(x / 60.0) * 8 + math.sin(x / 25.0) * 3)
        for dy in range(-2, 3):
            if 0 <= wy + dy < H:
                alpha = 1.0 - abs(dy) / 3.0
                orig = px[x, wy + dy]
                px[x, wy + dy] = lerp_color(orig, (255, 255, 255), alpha * 0.7)

# Sun reflection on water
for y in range(int(H * 0.38), int(H * 0.55)):
    t = (y - H * 0.38) / (H * 0.17)
    width = int(30 + t * 60)
    center_x = W // 2 + int(math.sin(y / 30.0) * 15)
    brightness = 0.4 * (1.0 - t)
    for x in range(center_x - width, center_x + width):
        if 0 <= x < W:
            orig = px[x, y]
            px[x, y] = lerp_color(orig, (255, 240, 200), brightness)

img.save(os.path.join(ASSETS, "ocean_waves.png"))

# ============================================================
# 3. FOREST PATH — trees lining a path with dappled light
# ============================================================
print("Generating forest_path.png ...")
img = Image.new("RGB", (W, H))
px = img.load()

# Sky peeking through canopy
for y in range(H):
    t = y / H
    if t < 0.3:
        c = lerp_color((120, 180, 220), (80, 140, 100), t / 0.3)
    elif t < 0.5:
        c = lerp_color((80, 140, 100), (40, 80, 40), (t - 0.3) / 0.2)
    else:
        c = lerp_color((40, 80, 40), (50, 40, 25), (t - 0.5) / 0.5)
    for x in range(W):
        px[x, y] = c

draw = ImageDraw.Draw(img)

# Tree trunks (perspective — wider at bottom, narrower at top)
trunks = [
    (-0.15, 0.3), (0.15, 0.35), (0.35, 0.4), (0.65, 0.4),
    (0.85, 0.35), (1.15, 0.3)
]
for tx_ratio, base_t in trunks:
    tx = int(W * tx_ratio)
    base_y = int(H * 0.55)
    top_y = int(H * 0.15)
    width_base = 40
    width_top = 15
    for y in range(top_y, base_y):
        yt = (y - top_y) / (base_y - top_y)
        w = int(width_top + (width_base - width_top) * yt)
        c = lerp_color((80, 55, 30), (60, 40, 20), yt)
        for x in range(tx - w, tx + w):
            if 0 <= x < W:
                px[x, y] = c

# Canopy blobs (overlapping green circles)
for _ in range(60):
    cx = random.randint(-50, W + 50)
    cy = random.randint(int(H * 0.05), int(H * 0.45))
    r = random.randint(40, 120)
    green = random.randint(60, 140)
    c = (random.randint(20, 50), green, random.randint(20, 50))
    for angle_deg in range(0, 360, 3):
        for dist in range(0, r, 2):
            angle = math.radians(angle_deg)
            px2 = int(cx + dist * math.cos(angle))
            py = int(cy + dist * math.sin(angle))
            if 0 <= px2 < W and 0 <= py < H:
                blend = 1.0 - dist / r
                orig = px[px2, py]
                px[px2, py] = lerp_color(orig, c, blend * 0.7)

# Path (perspective triangular shape)
path_points = [(W // 2 - 10, int(H * 0.55)), (W // 2 + 10, int(H * 0.55)),
               (W + 50, H), (-50, H)]
draw.polygon(path_points, fill=(120, 100, 60))

# Path texture — horizontal dirt lines
for y in range(int(H * 0.55), H, 6):
    yt = (y - H * 0.55) / (H * 0.45)
    shade = lerp_color((140, 120, 70), (100, 80, 50), yt)
    half_w = int(10 + yt * (W // 2 + 50))
    center = W // 2
    for x in range(center - half_w, center + half_w):
        if 0 <= x < W and random.random() < 0.3:
            px[x, y] = shade

# Light rays
for _ in range(8):
    rx = random.randint(int(W * 0.2), int(W * 0.8))
    for y in range(0, int(H * 0.6), 2):
        x_off = int((y / H) * 80)
        for dx in range(-3, 4):
            xx = rx + x_off + dx
            if 0 <= xx < W:
                orig = px[xx, y]
                px[xx, y] = lerp_color(orig, (255, 255, 200), 0.15)

img.save(os.path.join(ASSETS, "forest_path.png"))

# ============================================================
# 4. STARRY NIGHT — dark sky with stars, moon, and aurora
# ============================================================
print("Generating starry_night.png ...")
img = Image.new("RGB", (W, H))
px = img.load()

# Dark sky gradient
for y in range(H):
    t = y / H
    if t < 0.65:
        c = lerp_color((5, 5, 25), (10, 15, 40), t / 0.65)
    else:
        # Ground silhouette
        st = (t - 0.65) / 0.35
        c = lerp_color((15, 25, 15), (10, 15, 10), st)
    for x in range(W):
        px[x, y] = c

draw = ImageDraw.Draw(img)

# Aurora borealis (wavy colored bands)
for band in range(3):
    base_y = int(H * (0.15 + band * 0.1))
    hue_offset = band * 80
    for x in range(W):
        wave = math.sin(x / 120.0 + band * 1.5) * 40
        y_center = base_y + int(wave)
        for dy in range(-30, 31):
            y = y_center + dy
            if 0 <= y < H:
                fade = 1.0 - abs(dy) / 30.0
                g = int(100 + hue_offset * 0.5 + fade * 80)
                r = int(20 + hue_offset * 0.3)
                b_val = int(80 + fade * 60)
                orig = px[x, y]
                px[x, y] = lerp_color(orig, (r, g, b_val), fade * 0.3)

# Moon (crescent)
moon_cx, moon_cy = int(W * 0.75), int(H * 0.15)
moon_r = 50
for y in range(moon_cy - moon_r - 5, moon_cy + moon_r + 5):
    for x in range(moon_cx - moon_r - 5, moon_cx + moon_r + 5):
        if 0 <= x < W and 0 <= y < H:
            dist = math.sqrt((x - moon_cx) ** 2 + (y - moon_cy) ** 2)
            if dist < moon_r:
                # Moon face
                px[x, y] = lerp_color((255, 250, 220), (240, 230, 190), dist / moon_r)
            elif dist < moon_r + 3:
                px[x, y] = (200, 195, 170)

# Dark circle to make crescent
for y in range(moon_cy - moon_r, moon_cy + moon_r):
    for x in range(moon_cx, moon_cx + moon_r + 10):
        if 0 <= x < W and 0 <= y < H:
            dist = math.sqrt((x - (moon_cx + 20)) ** 2 + (y - (moon_cy - 5)) ** 2)
            if dist < moon_r - 5:
                t = y / H
                c = lerp_color((5, 5, 25), (10, 15, 40), min(1, t / 0.65))
                px[x, y] = c

# Stars
for _ in range(200):
    sx = random.randint(0, W - 1)
    sy = random.randint(0, int(H * 0.6))
    brightness = random.randint(150, 255)
    size = random.choice([1, 1, 1, 2])
    if size == 1:
        px[sx, sy] = (brightness, brightness, brightness)
    else:
        for dx in range(-1, 2):
            for dy in range(-1, 2):
                if 0 <= sx + dx < W and 0 <= sy + dy < H:
                    px[sx + dx, sy + dy] = (brightness, brightness, brightness)

# Ground silhouette (treeline)
ground_y = int(H * 0.65)
treeline_points = [(0, H)]
for x in range(0, W + 10, 10):
    tree_h = random.randint(10, 40)
    treeline_points.append((x, ground_y - tree_h))
treeline_points.append((W, H))
draw.polygon(treeline_points, fill=(8, 12, 8))

img.save(os.path.join(ASSETS, "starry_night.png"))

# ============================================================
# 5. FLOWER FIELD — rolling hills with wildflowers
# ============================================================
print("Generating flower_field.png ...")
img = Image.new("RGB", (W, H))
px = img.load()

# Sky
for y in range(H):
    t = y / H
    if t < 0.4:
        c = lerp_color((130, 190, 255), (200, 230, 255), t / 0.4)
    elif t < 0.45:
        c = lerp_color((200, 230, 255), (180, 210, 180), (t - 0.4) / 0.05)
    else:
        st = (t - 0.45) / 0.55
        c = lerp_color((80, 160, 60), (50, 120, 30), st)
    for x in range(W):
        px[x, y] = c

draw = ImageDraw.Draw(img)

# Rolling hills
hill_colors = [(90, 170, 70), (75, 150, 55), (60, 130, 45)]
for i, (base_t, color) in enumerate([(0.42, hill_colors[0]), (0.47, hill_colors[1]), (0.52, hill_colors[2])]):
    points = [(0, H)]
    for x in range(0, W + 1, 4):
        y = int(H * base_t + math.sin(x / 300.0 + i * 2) * 30 + math.sin(x / 100.0) * 15)
        points.append((x, y))
    points.append((W, H))
    draw.polygon(points, fill=color)

# Flowers scattered across the field
flower_colors = [
    (255, 80, 80), (255, 200, 50), (255, 150, 200),
    (200, 100, 255), (255, 120, 60), (255, 255, 100),
    (255, 255, 255), (200, 200, 255)
]

for _ in range(300):
    fx = random.randint(20, W - 20)
    fy = random.randint(int(H * 0.48), H - 30)
    fc = random.choice(flower_colors)
    petal_r = random.randint(4, 10)
    # Draw petals
    for angle in range(0, 360, 60):
        px_f = fx + int(petal_r * 0.7 * math.cos(math.radians(angle)))
        py_f = fy + int(petal_r * 0.7 * math.sin(math.radians(angle)))
        draw.ellipse([px_f - petal_r // 2, py_f - petal_r // 2,
                       px_f + petal_r // 2, py_f + petal_r // 2], fill=fc)
    # Center
    draw.ellipse([fx - 3, fy - 3, fx + 3, fy + 3], fill=(255, 220, 50))

# Clouds
for _ in range(4):
    cx = random.randint(50, W - 50)
    cy = random.randint(30, int(H * 0.2))
    for _ in range(5):
        ox = random.randint(-80, 80)
        oy = random.randint(-20, 20)
        r = random.randint(30, 60)
        draw.ellipse([cx + ox - r, cy + oy - r, cx + ox + r, cy + oy + r],
                      fill=(255, 255, 255))

img.save(os.path.join(ASSETS, "flower_field.png"))

print("Done! Generated 5 scenic landscape images.")
