"""Textures for the Forever Modern style, drawn from shapes and curves.
File names, regions and atlas coordinates match Widgets.lua's MODERN_ART table.
Needs Pillow. Usage: python tools/forever_textures.py [outdir [part ...]]
(default outdir TidyPlates_ThreatPlates/Media/Forever; parts: bar, health_fill,
cast_fill, sel, selected_lines, nameplates)"""
import math
import random
import sys
from PIL import Image

OUT = sys.argv[1] if len(sys.argv) > 1 else "TidyPlates_ThreatPlates/Media/Forever"
SS = 4  # supersampling per axis


def clamp(v, lo=0.0, hi=1.0):
    return lo if v < lo else hi if v > hi else v


def rrect_sdf(px, py, x0, y0, x1, y1, r):
    """Signed distance to a rounded rectangle (negative inside)."""
    cx, cy = (x0 + x1) / 2, (y0 + y1) / 2
    hx, hy = (x1 - x0) / 2 - r, (y1 - y0) / 2 - r
    qx, qy = abs(px - cx) - hx, abs(py - cy) - hy
    out = math.hypot(max(qx, 0), max(qy, 0))
    return out + min(max(qx, qy), 0) - r


def chamfer_inside(px, py, x0, y0, x1, y1, c):
    """Point inside a rectangle with 45 degree cut corners (cut length c along each axis)."""
    if px < x0 or px > x1 or py < y0 or py > y1:
        return False
    return (px - x0) + (py - y0) >= c and (x1 - px) + (py - y0) >= c and \
        (px - x0) + (y1 - py) >= c and (x1 - px) + (y1 - py) >= c


def coverage(fn, x, y):
    n = 0
    for i in range(SS):
        for j in range(SS):
            if fn(x + (i + 0.5) / SS, y + (j + 0.5) / SS):
                n += 1
    return n / (SS * SS)


def over(dst, src):
    """Straight-alpha 'over' of two (r, g, b, a) float tuples (0..1)."""
    sr, sg, sb, sa = src
    dr, dg, db, da = dst
    oa = sa + da * (1 - sa)
    if oa <= 0:
        return (sr, sg, sb, 0.0)
    f = da * (1 - sa)
    return ((sr * sa + dr * f) / oa, (sg * sa + dg * f) / oa, (sb * sa + db * f) / oa, oa)


def put(im, x, y, c):
    im.putpixel((x, y), tuple(int(round(clamp(v) * 255)) for v in c))


def save(im, name):
    # Pillow writes uncompressed TGA with bottom-left origin (descriptor 8), the
    # orientation this client loads
    im.save(f"{OUT}/{name}.tga")


# ---------------------------------------------------------------------------
# Bar.tga: dark bar background with a 1 px gray rim, rounded corners and a soft
# shadow to the bottom right. Region 88,0 - 220,18 (132 x 18).
def bar():
    im = Image.new("RGBA", (256, 32), (0, 0, 0, 0))
    X0, W, H = 88, 132, 18
    rect = (2, 2, W - 4, 14)  # rim is the outermost pixel row inside
    R = 3
    rim_col = (0.47, 0.46, 0.44)
    for y in range(H):
        for x in range(W):
            px, py = x + 0.5, y + 0.5
            d = rrect_sdf(px, py, *rect, R)
            # shadow: faint halo all around, stronger shifted to the bottom right
            ds = max(0.0, rrect_sdf(px - 0.5, py - 0.8, *rect, R))
            shadow = max(0.72 * math.exp(-ds ** 1.5 / 1.6), 0.3 * math.exp(-max(d, 0) / 4))
            c = (0, 0, 0, shadow if d > -1 else 0)
            # rim (supersampled band -1 < d < 0) and fill
            rim = coverage(lambda u, v: -1 <= rrect_sdf(u, v, *rect, R) < 0, x, y)
            inside = coverage(lambda u, v: rrect_sdf(u, v, *rect, R) < -1, x, y)
            if inside:
                t = clamp((py - 3.5) / 9.0)
                base = 0.6 + 0.2 * (2 * t - 1) ** 2
                dd = max(0.0, -d - 1.5)
                a = base + (1 - base) * 0.78 * 0.5 ** dd
                c = over(c, (0.01, 0.01, 0.01, a * inside))
            if rim:
                c = over(c, rim_col + (rim,))
            put(im, X0 + x, y, c)
    save(im, "Bar")


# ---------------------------------------------------------------------------
# HealthFill.tga: flat left-to-right gradient (75 % -> 100 % brightness), tinted by
# the bar color
def health_fill():
    im = Image.new("RGBA", (128, 16))
    for x in range(128):
        v = (190 + 62 * x / 127) / 255
        for y in range(16):
            put(im, x, y, (v, v, v, 1))
    save(im, "HealthFill")


# ---------------------------------------------------------------------------
# CastFill.tga: gray fill, lighter towards the bottom, with short soft brush
# strokes leaning to the right (random placement, fixed seed)
def cast_fill():
    W, H = 256, 16
    rnd = random.Random(20261016)
    strokes = []
    x = 6.0
    while x < W - 6:
        ang = math.radians(rnd.uniform(18, 38))
        length = rnd.uniform(10, 22)
        cx, cy = x, rnd.uniform(9, 11.5)
        dx, dy = math.cos(ang) * length / 2, -math.sin(ang) * length / 2
        strokes.append((cx - dx, cy - dy, cx + dx, cy + dy, rnd.uniform(1.3, 2.2), rnd.uniform(0.1, 0.2)))
        x += rnd.uniform(5, 13)

    def seg_dist(px, py, x0, y0, x1, y1):
        vx, vy = x1 - x0, y1 - y0
        t = clamp(((px - x0) * vx + (py - y0) * vy) / (vx * vx + vy * vy))
        return math.hypot(px - x0 - t * vx, py - y0 - t * vy)

    im = Image.new("RGBA", (W, H))
    for y in range(H):
        t = y / (H - 1)
        base = 0.455 + 0.17 * clamp((t - 0.2) / 0.65)
        for x in range(W):
            px, py = x + 0.5, y + 0.5
            s = 0.0
            for x0, y0, x1, y1, width, gain in strokes:
                if abs(px - (x0 + x1) / 2) > 14:
                    continue
                d = seg_dist(px, py, x0, y0, x1, y1)
                s = max(s, gain * math.exp(-(d / width) ** 2))
            v = base + s * clamp((t - 0.15) / 0.3)
            put(im, x, y, (v, v, v * 0.99, 1))
    save(im, "CastFill")


# ---------------------------------------------------------------------------
# Selected.tga / SelectedLine.tga: 2 px yellow line with chamfered corners, the
# first one with a gold glow outside. 64 x 64, region 1..62, line at 10..53.
LINE = (1.0, 0.957, 0.576)
GLOW = (1.0, 0.741, 0.125)
L0, L1 = 10, 53
CO, CI = 3.55, 2.35  # outer cut, inner cut (fitted to the reference corner)
GLOW_R, GLOW_REACH = 9.3, 10.0


def line_cov(x, y, w=2):
    return coverage(lambda u, v: chamfer_inside(u, v, L0, L0, L1, L1, CO)
                    and not chamfer_inside(u, v, L0 + w, L0 + w, L1 - w, L1 - w, CI), x, y)


def selected(glow):
    im = Image.new("RGBA", (64, 64))
    for y in range(64):
        for x in range(64):
            c = ((1.0, 0.741, 0.125, 0.0) if glow else LINE + (0.0,))
            if glow and 1 <= x < 62 and 1 <= y < 62:
                d = rrect_sdf(x + 0.5, y + 0.5, L0, L0, L1, L1, GLOW_R)
                if d > 0:
                    c = GLOW + ((1 - min(d, GLOW_REACH) / GLOW_REACH) ** 2,)
            lc = line_cov(x, y)
            if lc:
                c = over(c, LINE + (lc,))
            put(im, x, y, c)
    save(im, "Selected" if glow else "SelectedLine")


# SelectedLine050 .. 200: the line alone at other thicknesses (50-200 % of 2 px),
# 32 x 32, line from the texture edge inwards. Same inner cut; the outer cut grows
# so the 45 degree part stays as thick as the straight parts.
def selected_lines():
    for pct in (50, 75, 125, 150, 175, 200):
        w = 2 * pct / 100
        co = CI + (2 - math.sqrt(2)) * w
        im = Image.new("RGBA", (32, 32))
        for y in range(32):
            for x in range(32):
                a = coverage(lambda u, v: chamfer_inside(u, v, 0, 0, 32, 32, co)
                             and not chamfer_inside(u, v, w, w, 32 - w, 32 - w, CI), x, y)
                put(im, x, y, LINE + (a,))
        save(im, "SelectedLine%03d" % pct)


# ---------------------------------------------------------------------------
# Nameplates.tga atlas (256 x 256), three regions:
#   kick line 0,101 - 218,120: 1 px white line, rounded, soft glow outside
#   hover     0,121 - 212,135: 2 px gray line, rounded
#   dim       2,137 - 210,147: 30 % black, rounded
def nameplates():
    im = Image.new("RGBA", (256, 256), (0, 0, 0, 0))
    # kick line: outer edge of the 1 px line
    k = (4, 105, 214, 117)
    for y in range(101, 120):
        for x in range(0, 218):
            d = rrect_sdf(x + 0.5, y + 0.5, *k, 2.5)
            line = coverage(lambda u, v: -1 <= rrect_sdf(u, v, *k, 2.5) < 0, x, y)
            g = 0.0
            if d > 0:
                g = 0.25 * math.exp(-(d - 0.5) * 0.55) if d < 2.5 else 0.04
            put(im, x, y, over((1, 1, 1, g), (1, 1, 1, line)))
    # hover line
    h = (0, 121, 212, 135)
    for y in range(121, 135):
        for x in range(0, 212):
            a = coverage(lambda u, v: -2 <= rrect_sdf(u, v, *h, 3.5) < 0, x, y)
            put(im, x, y, (0.5, 0.5, 0.5, a))
    # dim overlay
    m = (2, 137, 210, 147)
    for y in range(137, 147):
        for x in range(2, 210):
            a = coverage(lambda u, v: rrect_sdf(u, v, *m, 2.5) < 0, x, y)
            put(im, x, y, (0, 0, 0, 0.3 * a))
    save(im, "Nameplates")


for f in sys.argv[2:] or ["bar", "health_fill", "cast_fill", "sel", "selected_lines", "nameplates"]:
    if f == "sel":
        selected(True)
        selected(False)
    else:
        globals()[f]()
