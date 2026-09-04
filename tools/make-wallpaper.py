#!/usr/bin/env python3
"""
Generate a Bulwark Black wallpaper, optionally with your own logo.

The theme ships with the Bulwark Black emblem. If you'd rather have your own
mark on the desktop, point this at your logo and it will be stripped down and
recoloured to the theme accent the same way ours is, so it sits in the palette
instead of on top of it.

    ./make-wallpaper.py                                   # ships-with default
    ./make-wallpaper.py --logo mylogo.png                 # your mark
    ./make-wallpaper.py --logo mylogo.png --logo-size 700 --comets 12

Requires ImageMagick 7 (`magick`). No browser, no fonts, no network.

LOGO GUIDELINES
---------------
The processing keeps a pixel in proportion to its *brightness*, then paints
what survives in the accent colour. That has consequences worth knowing before
you pick a file:

  * A dark or transparent background. Transparency is NOT required — the mask
    comes from brightness, so dark pixels drop out by themselves and an opaque
    logo on black works fine. A logo on a light background becomes a solid gold
    box and is refused.
  * Light artwork on transparency. Dark-on-transparent art nearly vanishes,
    because dark pixels are what gets dropped. Invert it first (--invert).
  * At least 512x512, ideally >= the --logo-size you intend, so it is never
    upscaled. 1024x1024 is a good default.
  * Roughly square. Very wide or tall marks get letterboxed into the square
    slot rather than cropped.
  * Simple, high-contrast shapes. Photographs and fine gradients turn to mud
    at 5% opacity over a near-black field.

The script refuses a logo that breaks the hard constraints and warns about the
soft ones, rather than quietly producing something ugly.
"""

import argparse
import hashlib
import os
import re
import shutil
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
ASSETS = os.path.join(HERE, "assets")

ACCENT_DEFAULT = "#e0b64d"
# Matches colors.toml: background #18140c, with a warm lift at the centre.
GRAD_INNER, GRAD_MID, GRAD_OUTER = "#211b10", "#18140c", "#0d0c07"

TILE_UNITS = 320          # circuit-pattern.svg viewBox
PATTERN_SCALE = 1.4       # 320 * 1.4 = 448px tile at 4K; matches the site at 1x

TRACES = [
    "M0,60 L80,60 L80,90 L160,90 L160,60 L240,60 L240,30 L320,30",
    "M0,180 L40,180 L40,150 L130,150 L130,180 L210,180 L210,210 L320,210",
    "M0,260 L90,260 L90,290 L200,290 L200,260 L320,260",
    "M30,0 L30,40 L70,40 L70,80",
    "M120,0 L120,30 L100,30 L100,60",
    "M200,0 L200,20 L180,20 L180,50",
    "M280,0 L280,60 L260,60 L260,90 L290,90 L290,120",
    "M50,320 L50,290 L75,290 L75,250",
    "M150,320 L150,300 L130,300 L130,240",
    "M240,320 L240,270 L260,270 L260,220",
    "M160,90 L160,120 L190,120 L190,160",
    "M230,150 L230,110 L260,110 L260,140",
]


def prune_cache(cache_dir, prefix, keep):
    """Keep only the N most recently used cache entries under one prefix."""
    try:
        entries = [os.path.join(cache_dir, f) for f in os.listdir(cache_dir)
                   if f.startswith(prefix)]
    except OSError:
        return
    if len(entries) <= keep:
        return
    entries.sort(key=lambda f: os.path.getmtime(f), reverse=True)
    for stale in entries[keep:]:
        try:
            os.remove(stale)
        except OSError:
            pass


def die(msg):
    sys.exit("error: " + msg)


def warn(msg):
    print("warning: " + msg, file=sys.stderr)


def run(args):
    p = subprocess.run(args, capture_output=True, text=True)
    if p.returncode != 0:
        die("ImageMagick failed:\n" + (p.stderr.strip() or " ".join(args[:6])))
    return p.stdout.strip()


def identify(path, fmt):
    return run(["magick", "identify", "-format", fmt, path])


def rasterize_if_vector(tmp, path, target):
    """Render an SVG to a transparent PNG before anything else touches it.

    Two things go wrong otherwise. ImageMagick reports an SVG's nominal viewBox
    size — simple-icons ship 24x24 — so a perfectly good vector logo is refused
    as "too small". And it rasterises onto white unless told not to, which makes
    every transparent SVG look like a logo on a solid background and trips the
    plate check.
    """
    try:
        fmt = identify(path, "%m").strip().upper()
    except SystemExit:
        return path
    if fmt not in ("SVG", "MVG"):
        return path

    out = os.path.join(tmp, "vector.png")
    side = max(512, min(2048, int(target) * 2 if target else 1024))
    run(["magick", "-background", "none", "-density", "1200", path,
         "-resize", "%dx%d" % (side, side), "-trim", "+repage",
         "-bordercolor", "none", "-border", "%d" % max(2, side // 64), out])
    return out


# ---------------------------------------------------------------- logo checks

def validate_logo(path, logo_size):
    if not os.path.isfile(path):
        die("logo not found: " + path)
    try:
        w, h, alpha = identify(path, "%w %h %A").split()
        w, h = int(w), int(h)
    except Exception:
        die("could not read %s as an image" % path)

    if min(w, h) < 256:
        die("logo is %dx%d; minimum is 256x256 (512+ recommended)" % (w, h))
    if min(w, h) < 512:
        warn("logo is %dx%d; 512x512 or larger is recommended" % (w, h))
    if min(w, h) < logo_size:
        warn("logo is %dpx but will be drawn at %dpx, so it gets upscaled; "
             "use --logo-size %d or a larger file" % (min(w, h), logo_size, min(w, h)))

    ratio = max(w, h) / min(w, h)
    if ratio > 2.5:
        die("logo aspect ratio is %.1f:1; keep it under 2.5:1 (square is best)" % ratio)
    if ratio > 1.4:
        warn("logo is %.1f:1; it will be fitted into a square slot, not cropped" % ratio)

    if float(identify(path, "%[fx:mean.a]")) > 0.995:
        warn("logo is fully opaque. If it sits on a solid light background, "
             "that background becomes part of the mark — see the plate check.")
    return w, h


def coverage_check(mask_path, allow_plate):
    """Sanity-check the processed mask before it is painted and composited."""
    mean = float(identify(mask_path, "%[fx:mean]"))
    if mean < 0.004:
        die("after processing, almost nothing of the logo is left (mean %.4f). "
            "This usually means the art is dark-on-transparent: try --invert." % mean)

    # A logo on a solid light background survives masking as a bright slab with
    # the mark punched out of it. The giveaway is the border: a real mark fades
    # to transparent at the edges, a plate does not. %A cannot detect this --
    # ImageMagick reports "Blend" for opaque and transparent PNGs alike.
    w, h = (int(v) for v in identify(mask_path, "%w %h").split())
    band = max(2, min(w, h) // 25)
    edges = [
        "%dx%d+0+0" % (w, band),
        "%dx%d+0+%d" % (w, band, h - band),
        "%dx%d+0+0" % (band, h),
        "%dx%d+%d+0" % (band, h, w - band),
    ]
    edge_mean = max(float(run(["magick", mask_path, "-crop", g, "+repage",
                               "-format", "%[fx:mean]", "info:"])) for g in edges)
    if edge_mean > 0.25 and not allow_plate:
        die("the logo looks like it has a solid background: its edges stay "
            "bright after processing (edge mean %.2f), so it would render as a "
            "coloured slab with the mark cut out of it. Remove the background "
            "and save a transparent PNG. If your mark genuinely runs to the "
            "edges, re-run with --allow-plate." % edge_mean)
    if mean > 0.75:
        warn("the processed logo is nearly solid (mean %.2f); it may read as a "
             "block rather than a mark." % mean)
    return mean


# ------------------------------------------------------------------- pipeline

def logo_cache_path(src, accent, erode, invert, threshold):
    try:
        stamp = os.path.getmtime(src)
    except OSError:
        stamp = 0
    key = hashlib.sha1(("|".join(str(v) for v in (
        os.path.abspath(src), stamp, accent, erode, invert, threshold))
    ).encode()).hexdigest()[:16]
    return os.path.join(
        os.environ.get("XDG_CACHE_HOME", os.path.expanduser("~/.cache")),
        "bulwark-black", "logo-%s.png" % key)


def build_logo(tmp, src, accent, erode, invert, threshold, allow_plate,
               use_cache=True):
    cached = logo_cache_path(src, accent, erode, invert, threshold)
    if use_cache and os.path.isfile(cached):
        return cached

    alpha = os.path.join(tmp, "a.png")
    lum = os.path.join(tmp, "l.png")
    mask = os.path.join(tmp, "m.png")
    out = os.path.join(tmp, "logo.png")

    run(["magick", src, "-alpha", "extract", alpha])
    lum_cmd = ["magick", src, "-alpha", "off", "-colorspace", "gray"]
    if invert:
        lum_cmd += ["-negate"]
    run(lum_cmd + [lum])

    if erode > 0:
        eroded = os.path.join(tmp, "ae.png")
        # Trims stray marks that sit just inside the silhouette edge — our own
        # source logo has a dashed arc there.
        run(["magick", alpha, "-morphology", "Erode", "Disk:%d" % erode, eroded])
        alpha = eroded

    # Keep brightness x opacity, then clamp near-black so anti-aliasing does
    # not survive as faint speckle.
    run(["magick", lum, alpha, "-compose", "Multiply", "-composite",
         "-level", "%d%%,100%%" % threshold, mask])
    coverage_check(mask, allow_plate)
    size = identify(mask, "%wx%h")
    run(["magick", "-size", size, "xc:" + accent, mask, "-alpha", "off",
         "-compose", "CopyOpacity", "-composite", out])
    if use_cache:
        try:
            os.makedirs(os.path.dirname(cached), exist_ok=True)
            run(["magick", out, "-depth", "8", "-strip", cached])
            prune_cache(os.path.dirname(cached), "logo-", 8)
        except SystemExit:
            pass  # an unwritable cache is not worth failing the build over
    return out


def polyline(d):
    pts = [(float(a), float(b)) for a, b in
           re.findall(r"(-?\d+(?:\.\d+)?),(-?\d+(?:\.\d+)?)", d)]
    return pts


def subpath(pts, start, end):
    """Points of the polyline between two distances along it."""
    out, travelled = [], 0.0
    for i in range(len(pts) - 1):
        (x0, y0), (x1, y1) = pts[i], pts[i + 1]
        seg = abs(x1 - x0) + abs(y1 - y0)
        if seg == 0:
            continue
        for edge in (start, end):
            if travelled < edge <= travelled + seg:
                t = (edge - travelled) / seg
                out.append((x0 + (x1 - x0) * t, y0 + (y1 - y0) * t))
        if start <= travelled <= end:
            out.append((x0, y0))
        travelled += seg
    if start <= travelled <= end:
        out.append(pts[-1])
    return out


def draw_comets(tmp, base, width, height, count, seed):
    """Draw all comets, one full-canvas pass per layer rather than per comet.

    Compositing each comet separately meant 4*N full-size operations, which took
    ~48s for 10 comets at 1080p and far worse at 4K. Batching the draws into one
    canvas per layer makes it 4 regardless of count.
    """
    import random
    rng = random.Random(seed)
    step = TILE_UNITS * PATTERN_SCALE
    cols, rows = int(width // step) + 1, int(height // step) + 1
    layers = [("#a8842f", 14, 0.16, 6, 0.48), ("#e0b64d", 7, 0.40, 2, 0.32),
              ("#f2c14e", 4, 0.90, 0, 0.16), ("#fff7e6", 3, 1.00, 0, 0.08)]

    picks = []
    for _ in range(count):
        pts = polyline(TRACES[rng.randrange(len(TRACES))])
        ox, oy = rng.randrange(cols) * TILE_UNITS, rng.randrange(rows) * TILE_UNITS
        pts = [((x + ox) * PATTERN_SCALE, (y + oy) * PATTERN_SCALE) for x, y in pts]
        total = sum(abs(pts[i + 1][0] - pts[i][0]) + abs(pts[i + 1][1] - pts[i][1])
                    for i in range(len(pts) - 1))
        picks.append((pts, total, rng.uniform(0.35, 0.95) * total))

    out = base
    for colour, w, op, blur, lit_frac in layers:
        cmd = ["magick", "-size", "%dx%d" % (width, height), "xc:none",
               "-stroke", colour, "-strokewidth", str(w), "-fill", "none"]
        drew = False
        for pts, total, head in picks:
            seg = subpath(pts, max(0, head - lit_frac * total), head)
            if len(seg) < 2:
                continue
            cmd += ["-draw", "polyline " + " ".join("%.1f,%.1f" % q for q in seg)]
            drew = True
        if not drew:
            continue
        lay = os.path.join(tmp, "layer%d.png" % w)
        if blur:
            cmd += ["-blur", "0x%d" % blur]
        cmd += ["-alpha", "set", "-channel", "A", "-evaluate", "multiply",
                str(op), "+channel", lay]
        run(cmd)
        nxt = os.path.join(tmp, "stage%d.png" % w)
        run(["magick", out, lay, "-compose", "Screen", "-composite", nxt])
        out = nxt
    return out


def main():
    ap = argparse.ArgumentParser(
        description="Generate a Bulwark Black wallpaper, optionally with your own logo.",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=__doc__.split("LOGO GUIDELINES")[1])
    ap.add_argument("--logo", default=os.path.join(ASSETS, "logo.png"),
                    help="logo image (default: the Bulwark Black emblem)")
    ap.add_argument("--logo-size", type=int, default=None, metavar="PX",
                    help="drawn size of the logo, 0 to omit it "
                         "(default: scales with --size; 880 at 4K)")
    ap.add_argument("--comets", type=int, default=0, metavar="N",
                    help="static comets to bake in, 0-24 (default: 0 — the "
                         "shell plugin animates them live instead)")
    ap.add_argument("--accent", default=ACCENT_DEFAULT, help="accent colour")
    ap.add_argument("--size", default="3840x2160", help="output size")
    ap.add_argument("--pattern-opacity", type=float, default=0.26, metavar="F")
    ap.add_argument("--erode", type=int, default=6, metavar="PX",
                    help="shrink the logo silhouette to drop edge artefacts "
                         "(default: 6; use 0 for clean vector exports)")
    ap.add_argument("--threshold", type=int, default=14, metavar="PCT",
                    help="brightness below this %% is dropped (default: 14)")
    ap.add_argument("--allow-plate", action="store_true",
                    help="skip the solid-background check")
    ap.add_argument("--invert", action="store_true",
                    help="for dark-on-transparent art")
    ap.add_argument("--seed", type=int, default=7)
    ap.add_argument("--no-cache", action="store_true",
                    help="rebuild the cached background and logo layers")
    ap.add_argument("-o", "--out", default="wallpaper.png")
    a = ap.parse_args()

    if not shutil.which("magick"):
        die("ImageMagick 7 (`magick`) is required and was not found on PATH")

    # Order matters: a wrong --accent or a missing logo used to surface as a
    # confusing "--logo-size must be between..." because the default size
    # exceeded a small canvas and tripped first.
    if not re.fullmatch(r"\d+x\d+", a.size):
        die("--size must look like 3840x2160")
    W, H = (int(v) for v in a.size.split("x"))
    if not re.fullmatch(r"#[0-9a-fA-F]{6}", a.accent):
        die("--accent must be a #rrggbb colour")
    if not 0 <= a.comets <= 24:
        die("--comets must be between 0 and 24")

    # Default scales with the canvas (880px on a 2160-tall frame), so small
    # --size runs do not need an explicit --logo-size.
    if a.logo_size is None:
        a.logo_size = max(40, round(min(W, H) * 0.407))
    if a.logo_size and not 40 <= a.logo_size <= min(W, H):
        die("--logo-size must be 0, or between 40 and %d for this output size"
            % min(W, H))

    pattern_svg = os.path.join(ASSETS, "circuit-pattern.svg")
    if not os.path.isfile(pattern_svg):
        die("missing " + pattern_svg)

    with tempfile.TemporaryDirectory() as tmp:
        if a.logo_size:
            if not os.path.isfile(a.logo):
                die("logo not found: " + a.logo)
            a.logo = rasterize_if_vector(tmp, a.logo, a.logo_size)
            validate_logo(a.logo, a.logo_size)

        # Gradient + tiled pattern (+ any baked comets) are identical for every
        # rebuild at the same settings — about 7s of a 9s 4K run — while only the
        # logo actually changes. Cache that layer so resizing a logo is quick.
        key = hashlib.sha1(("|".join(str(v) for v in (
            W, H, a.pattern_opacity, a.comets, a.seed,
            GRAD_INNER, GRAD_MID, GRAD_OUTER, PATTERN_SCALE))).encode()).hexdigest()[:16]
        cache_dir = os.path.join(
            os.environ.get("XDG_CACHE_HOME", os.path.expanduser("~/.cache")),
            "bulwark-black")
        cached = os.path.join(cache_dir, "base-%s.png" % key)

        if a.no_cache or not os.path.isfile(cached):
            base = os.path.join(tmp, "base.png")
            run(["magick", "-size", "%dx%d" % (W, H),
                 "radial-gradient:%s-%s" % (GRAD_INNER, GRAD_OUTER), base])

            tile = max(8, int(TILE_UNITS * PATTERN_SCALE * (W / 3840.0)))
            tile_png = os.path.join(tmp, "tile.png")
            run(["magick", "-background", "none", "-density", "384", pattern_svg,
                 "-resize", "%dx%d!" % (tile, tile), tile_png])
            tiled = os.path.join(tmp, "tiled.png")
            run(["magick", "-size", "%dx%d" % (W, H), "tile:" + tile_png,
                 "-alpha", "set", "-channel", "A", "-evaluate", "multiply",
                 str(a.pattern_opacity), "+channel", tiled])
            stage = os.path.join(tmp, "stage.png")
            run(["magick", base, tiled, "-compose", "Over", "-composite", stage])

            if a.comets:
                stage = draw_comets(tmp, stage, W, H, a.comets, a.seed)

            try:
                os.makedirs(cache_dir, exist_ok=True)
                run(["magick", stage, "-depth", "8", "-strip", cached])
                prune_cache(cache_dir, "base-", 4)
            except SystemExit:
                pass  # a cache we cannot write is not worth failing over
        else:
            stage = cached

        if a.logo_size:
            logo = build_logo(tmp, a.logo, a.accent, a.erode, a.invert, a.threshold,
                               a.allow_plate, use_cache=not a.no_cache)
            sized = os.path.join(tmp, "sized.png")
            run(["magick", logo, "-resize", "%dx%d" % (a.logo_size, a.logo_size), sized])
            glow = os.path.join(tmp, "glow.png")
            run(["magick", sized, "-alpha", "extract",
                 "-resize", "25%", "-blur", "0x10", "-resize", "400%",
                 "-level", "0%,60%", glow])
            glowc = os.path.join(tmp, "glowc.png")
            run(["magick", "-size", identify(glow, "%wx%h"), "xc:" + a.accent,
                 glow, "-alpha", "off", "-compose", "CopyOpacity", "-composite",
                 "-channel", "A", "-evaluate", "multiply", "0.22", "+channel", glowc])
            run(["magick", stage, glowc, "-gravity", "center", "-compose", "Screen",
                 "-composite", sized, "-gravity", "center", "-compose", "Over",
                 "-composite", "-depth", "8", "-strip", a.out])
        else:
            run(["magick", stage, "-depth", "8", "-strip", a.out])

    print("wrote %s (%s)" % (a.out, identify(a.out, "%wx%h")))
    print("install it with:  omarchy theme bg set %s" % os.path.abspath(a.out))


if __name__ == "__main__":
    main()
