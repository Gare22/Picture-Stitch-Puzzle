"""Generate complex gradient backgrounds with geometric patterns for puzzle game."""
import math
import os
import random
from PIL import Image, ImageDraw

W, H = 800, 1200
random.seed(42)
ASSETS = os.path.join(os.path.dirname(__file__), "assets")


def lerp_color(c1, c2, t):
    return tuple(int(c1[i] + (c2[i] - c1[i]) * t) for i in range(3))


def diagonal_gradient(w, h, colors):
    """Multi-stop diagonal gradient."""
    img = Image.new("RGB", (w, h))
    px = img.load()
    for y in range(h):
        for x in range(w):
            t = (x / w + y / h) / 2.0
            t = max(0, min(1, t))
            # find which segment
            seg = t * (len(colors) - 1)
            i = min(int(seg), len(colors) - 2)
            local_t = seg - i
            px[x, y] = lerp_color(colors[i], colors[i + 1], local_t)
    return img


def radial_gradient(w, h, cx, cy, radius, colors):
    """Radial gradient from center."""
    img = Image.new("RGB", (w, h))
    px = img.load()
    for y in range(h):
        for x in range(w):
            dist = math.sqrt((x - cx) ** 2 + (y - cy) ** 2) / radius
            t = max(0, min(1, dist))
            seg = t * (len(colors) - 1)
            i = min(int(seg), len(colors) - 2)
            local_t = seg - i
            px[x, y] = lerp_color(colors[i], colors[i + 1], local_t)
    return img


def conic_gradient(w, h, cx, cy, colors):
    """Conic/angular gradient around a center point."""
    img = Image.new("RGB", (w, h))
    px = img.load()
    for y in range(h):
        for x in range(w):
            angle = math.atan2(y - cy, x - cx)  # -pi to pi
            t = (angle + math.pi) / (2 * math.pi)  # 0 to 1
            seg = t * (len(colors) - 1)
            i = min(int(seg), len(colors) - 2)
            local_t = seg - i
            px[x, y] = lerp_color(colors[i], colors[i + 1], local_t)
    return img


# --- Image 1: Diagonal gradient with scattered circles ---
print("Generating diagonal_gradient_circles.png ...")
img = diagonal_gradient(W, H, [
    (30, 10, 60), (80, 20, 120), (200, 50, 80),
    (255, 140, 50), (255, 200, 80)
])
draw = ImageDraw.Draw(img)
for _ in range(40):
    cx = random.randint(0, W)
    cy = random.randint(0, H)
    r = random.randint(20, 80)
    alpha = random.randint(40, 120)
    color = (255, 255, 255, alpha)
    # Draw unfilled circle with thick outline
    for offset in range(3):
        draw.ellipse([cx - r - offset, cy - r - offset, cx + r + offset, cy + r + offset],
                      outline=(255, 255, 255), width=2)
img.save(os.path.join(ASSETS, "diagonal_gradient_circles.png"))

# --- Image 2: Radial sunset with concentric rings ---
print("Generating radial_sunset_rings.png ...")
img = radial_gradient(W, H, W // 2, int(H * 0.4), H * 0.8, [
    (255, 255, 200), (255, 180, 80), (220, 80, 40),
    (120, 30, 80), (30, 10, 60)
])
draw = ImageDraw.Draw(img)
# Concentric rings
for i in range(8):
    r = 60 + i * 55
    for w_off in range(3):
        draw.ellipse([W // 2 - r - w_off, int(H * 0.4) - r - w_off,
                       W // 2 + r + w_off, int(H * 0.4) + r + w_off],
                      outline=(255, 255, 255), width=2)
img.save(os.path.join(ASSETS, "radial_sunset_rings.png"))

# --- Image 3: Conic blue-teal with triangles ---
print("Generating conic_teal_triangles.png ...")
img = conic_gradient(W, H, W // 2, H // 2, [
    (10, 30, 80), (20, 100, 140), (40, 180, 160),
    (80, 220, 200), (20, 100, 140), (10, 30, 80)
])
draw = ImageDraw.Draw(img)
for _ in range(25):
    cx = random.randint(50, W - 50)
    cy = random.randint(50, H - 50)
    size = random.randint(30, 90)
    # equilateral triangle
    points = []
    for k in range(3):
        angle = k * 2 * math.pi / 3 - math.pi / 2
        points.append((cx + size * math.cos(angle), cy + size * math.sin(angle)))
    draw.polygon(points, outline=(255, 255, 255))
    # double outline
    points2 = []
    for k in range(3):
        angle = k * 2 * math.pi / 3 - math.pi / 2
        points2.append((cx + (size + 4) * math.cos(angle), cy + (size + 4) * math.sin(angle)))
    draw.polygon(points2, outline=(255, 255, 255))
img.save(os.path.join(ASSETS, "conic_teal_triangles.png"))

# --- Image 4: Aurora gradient with diamond grid ---
print("Generating aurora_diamond_grid.png ...")
img = Image.new("RGB", (W, H))
px = img.load()
for y in range(H):
    for x in range(W):
        t = y / H
        wave = math.sin(x / 80.0 + t * 4) * 0.15
        t2 = max(0, min(1, t + wave))
        c1 = lerp_color((10, 60, 40), (20, 180, 120), t2)
        c2 = lerp_color((80, 200, 180), (180, 100, 200), t2)
        blend = max(0, min(1, math.sin(x / 200.0) * 0.5 + 0.5))
        px[x, y] = lerp_color(c1, c2, blend)

draw = ImageDraw.Draw(img)
# Diamond grid
spacing = 80
for row in range(-1, H // spacing + 2):
    for col in range(-1, W // spacing + 2):
        cx = col * spacing + (spacing // 2 if row % 2 else 0)
        cy = row * spacing
        s = 25
        diamond = [(cx, cy - s), (cx + s, cy), (cx, cy + s), (cx - s, cy)]
        draw.polygon(diamond, outline=(255, 255, 255))
img.save(os.path.join(ASSETS, "aurora_diamond_grid.png"))

# --- Image 5: Warm mosaic gradient with hexagons ---
print("Generating warm_mosaic_hexagons.png ...")
img = Image.new("RGB", (W, H))
px = img.load()
for y in range(H):
    for x in range(W):
        # Two-axis gradient: warm orange top-left to deep red bottom-right
        tx = x / W
        ty = y / H
        t = (tx * 0.6 + ty * 0.4)
        wave = math.sin(tx * 6 + ty * 4) * 0.1
        t = max(0, min(1, t + wave))
        c = lerp_color((255, 180, 50), (140, 20, 60), t)
        # Add subtle secondary hue shift
        shift = math.sin(ty * 8) * 0.08
        c2 = lerp_color(c, (200, 80, 120), max(0, min(1, 0.5 + shift)))
        px[x, y] = c2

draw = ImageDraw.Draw(img)
# Hexagonal pattern
hex_r = 40
hex_h = hex_r * math.sqrt(3)
for row in range(-1, int(H / hex_h) + 2):
    for col in range(-1, int(W / (hex_r * 1.5)) + 2):
        cx = col * hex_r * 1.5
        cy = row * hex_h + (hex_h / 2 if col % 2 else 0)
        points = []
        for k in range(6):
            angle = k * math.pi / 3
            points.append((cx + hex_r * math.cos(angle), cy + hex_r * math.sin(angle)))
        draw.polygon(points, outline=(255, 255, 255))
img.save(os.path.join(ASSETS, "warm_mosaic_hexagons.png"))

print("Done! Generated 5 gradient/pattern images.")
