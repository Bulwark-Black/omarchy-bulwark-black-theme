#!/usr/bin/env python3
"""
Render the looping comet animation used as the theme's preview.

The still wallpaper cannot show the one thing the theme is built around, so the
README image moves. This draws the same comets the shell plugin animates -- same
twelve traces, same four-layer taper, same accent -- and advances them along the
circuit by hand, one frame at a time.

    ./make-preview-anim.py                          # ships-with default
    ./make-preview-anim.py --frames 72 --comets 24  # denser, smoother

Requires ImageMagick 7 (`magick`). No browser, no fonts, no network.

WHY NOT A SCREEN RECORDING
--------------------------
A capture of the live plugin would be honest but unreproducible: it bakes in
whatever the compositor, the monitor and the moment happened to do. This reads
the trace table straight out of Background.qml's twin in make-wallpaper.py, so
the motion is the plugin's own geometry and anyone can regenerate it.

LOOPING
-------
Each comet completes a whole number of trips over the clip, so the last frame
hands back to the first with nothing to blend. Comets are given different trip
counts to keep them from marching in lockstep.
"""

import argparse
import importlib.util
import os
import shutil
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))

# make-wallpaper.py owns the trace table, the layer taper and the palette. Load
# it rather than restating any of it -- a comet that drifts off the drawn circuit
# because the two copies disagreed is exactly the bug this avoids.
_spec = importlib.util.spec_from_file_location(
    "mw", os.path.join(HERE, "make-wallpaper.py"))
mw = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(mw)

REFERENCE_WIDTH = 3840.0   # the width the trace geometry is authored against


def die(msg):
    print("error: " + msg, file=sys.stderr)
    sys.exit(1)


def build_comets(count, seed, width, height, scale):
    """Pick each comet's trace, its tile on the grid, and its phase and speed."""
    import random
    rng = random.Random(seed)
    step = mw.TILE_UNITS * mw.PATTERN_SCALE * scale
    cols, rows = int(width // step) + 1, int(height // step) + 1

    comets = []
    for i in range(count):
        pts = mw.polyline(mw.TRACES[rng.randrange(len(mw.TRACES))])
        ox = rng.randrange(cols) * mw.TILE_UNITS
        oy = rng.randrange(rows) * mw.TILE_UNITS
        pts = [((x + ox) * mw.PATTERN_SCALE * scale,
                (y + oy) * mw.PATTERN_SCALE * scale) for x, y in pts]
        total = sum(abs(pts[j + 1][0] - pts[j][0]) + abs(pts[j + 1][1] - pts[j][1])
                    for j in range(len(pts) - 1))
        if total <= 0:
            continue
        # Whole trips only, or the loop seams. Two thirds run at single speed.
        trips = 1 if i % 3 else 2
        comets.append({"pts": pts, "total": total,
                       "phase": rng.random(), "trips": trips})
    return comets


def envelope(phase):
    """The plugin's own fade, so a comet arrives and leaves the way it does live.

    Background.qml calls it the epulse-fade: in fast, hold, dip, flicker, out.
    Without it a comet snaps on at the start of its wire and snaps off at the
    end, which is the tell that you are watching a loop rather than traffic.
    """
    if phase < 0.07:
        return phase / 0.07
    if phase < 0.68:
        return 1.0
    if phase < 0.82:
        return 1.0 - (phase - 0.68) / 0.14 * 0.65
    if phase < 0.88:
        return 0.35 + (phase - 0.82) / 0.06 * 0.35
    return max(0.0, 1.0 - (phase - 0.88) / 0.12)


def draw_frame(tmp, base, width, height, comets, t, scale, out):
    """One frame: the four taper layers, screened over the still background."""
    stage = base
    for idx, (colour, w, op, blur, lit_frac) in enumerate(mw.LAYERS):
        sw = max(1.0, w * scale)
        cmd = ["magick", "-size", "%dx%d" % (width, height), "xc:none",
               "-stroke", colour, "-strokewidth", "%.2f" % sw, "-fill", "none"]
        drew = False
        for c in comets:
            phase = ((t * c["trips"]) + c["phase"]) % 1.0
            fade = envelope(phase)
            if fade < 0.01:
                continue
            head = phase * c["total"]
            seg = mw.subpath(c["pts"], max(0.0, head - lit_frac * c["total"]), head)
            if len(seg) < 2:
                continue
            # stroke-opacity is per-draw, so every comet carries its own point on
            # the fade inside one canvas pass. Splitting them into separate passes
            # would multiply the render by the comet count for the same picture.
            cmd += ["-draw", "stroke-opacity %.4f polyline %s"
                    % (fade, " ".join("%.1f,%.1f" % q for q in seg))]
            drew = True
        if not drew:
            continue
        lay = os.path.join(tmp, "lay%d.png" % idx)
        if blur:
            cmd += ["-blur", "0x%.1f" % max(1.0, blur * scale)]
        cmd += ["-alpha", "set", "-channel", "A", "-evaluate", "multiply",
                str(op), "+channel", lay]
        mw.run(cmd)
        nxt = os.path.join(tmp, "st%d.png" % idx)
        mw.run(["magick", stage, lay, "-compose", "Screen", "-composite", nxt])
        stage = nxt
    if stage is base:
        shutil.copy(base, out)
    else:
        shutil.move(stage, out)


def main():
    ap = argparse.ArgumentParser(
        description="Render the looping comet preview animation.")
    ap.add_argument("--background", default=os.path.join(
        HERE, os.pardir, "backgrounds", "01-circuit-4k.png"),
        help="still to animate over (default: the shipped wallpaper)")
    ap.add_argument("--size", default="1200x675", help="output size")
    ap.add_argument("--supersample", type=int, default=2, metavar="N",
                    help="draw at N x size then downscale, for clean thin strokes")
    ap.add_argument("--comets", type=int, default=18, metavar="N")
    # Background.qml gives each comet 2800 + rand(3700) ms for a whole wire,
    # divided by the speed slider, which ships at 0.55 -- so a real comet takes
    # 5.1s to 11.8s to cross. A comet here does one or two whole trips per clip,
    # so an 11s clip puts both 11s and 5.5s inside that range. Shorter clips
    # cannot: at 8s the two-trip comets run at 4s, faster than the plugin's
    # quickest, and the whole thing reads as a screensaver.
    ap.add_argument("--seconds", type=float, default=11.0, metavar="S",
                    help="clip length; keep it near the plugin's own 5-12s crossing")
    ap.add_argument("--fps", type=int, default=12)
    ap.add_argument("--quality", type=int, default=72, help="webp quality")
    ap.add_argument("--seed", type=int, default=3)
    ap.add_argument("-o", "--out", default="preview-anim.webp")
    a = ap.parse_args()

    if not shutil.which("magick"):
        die("ImageMagick 7 (magick) is required")
    if not os.path.isfile(a.background):
        die("background not found: " + a.background)
    if not 1 <= a.comets <= 48:
        die("--comets must be between 1 and 48")
    if not 1.0 <= a.seconds <= 30.0:
        die("--seconds must be between 1 and 30")
    if not 4 <= a.fps <= 30:
        die("--fps must be between 4 and 30")
    a.frames = max(2, int(round(a.seconds * a.fps)))
    if not 1 <= a.supersample <= 4:
        die("--supersample must be between 1 and 4")

    m = mw.re.fullmatch(r"(\d+)x(\d+)", a.size)
    if not m:
        die("--size must look like 1200x675")
    W, H = int(m.group(1)), int(m.group(2))
    SW, SH = W * a.supersample, H * a.supersample
    scale = SW / REFERENCE_WIDTH

    comets = build_comets(a.comets, a.seed, SW, SH, scale)
    if not comets:
        die("no comets placed; try a larger --size")

    with tempfile.TemporaryDirectory() as tmp:
        base = os.path.join(tmp, "base.png")
        mw.run(["magick", a.background, "-resize", "%dx%d!" % (SW, SH), base])

        frames = []
        for f in range(a.frames):
            raw = os.path.join(tmp, "raw%03d.png" % f)
            draw_frame(tmp, base, SW, SH, comets, f / float(a.frames), scale, raw)
            small = os.path.join(tmp, "f%03d.png" % f)
            mw.run(["magick", raw, "-resize", "%dx%d!" % (W, H), "-strip", small])
            os.remove(raw)
            frames.append(small)
            sys.stderr.write("\r  frame %d/%d" % (f + 1, a.frames))
            sys.stderr.flush()
        sys.stderr.write("\n")

        delay = max(1, round(100.0 / a.fps))
        mw.run(["magick", "-delay", str(delay), "-loop", "0"] + frames +
               ["-define", "webp:lossless=false",
                "-define", "webp:method=6",
                "-define", "webp:auto-filter=true",
                "-quality", str(a.quality), a.out])

    size = os.path.getsize(a.out)
    print("wrote %s (%dx%d, %d frames, %.1fs loop, %.1f KB)"
          % (a.out, W, H, a.frames, a.frames / float(a.fps), size / 1024.0))


if __name__ == "__main__":
    main()
