#!/usr/bin/env python3
"""
Diagnose a logo the wallpaper generator refused, and repair it where the repair
is unambiguous.

    logo-doctor.py mylogo.png            # what is wrong with it
    logo-doctor.py mylogo.png --fix      # repair it and print the new path
    logo-doctor.py mylogo.png --brief    # a brief for a coding agent

make-wallpaper.py is deliberately strict: it refuses artwork that would render
as a gold slab or vanish entirely, rather than producing something ugly. That is
the right default, but "rejected" is a dead end for someone who just wants their
logo on their desktop. Most rejections have a mechanical fix — the same ones
applied by hand to the Bulwark emblem: drop a background, invert dark artwork,
erode a stray edge, pad a wide mark into a square.

What --fix cannot do is invent resolution. A 64x64 favicon has no detail to
recover; that needs someone to find the real asset, which is what --brief hands
to an agent.

Requires ImageMagick 7.
"""

import argparse
import os
import shutil
import subprocess
import sys

MIN_SIDE = 256
GOOD_SIDE = 512
MAX_RATIO = 2.5
PLATE_EDGE = 0.25
FAINT_MEAN = 0.004


def run(args, check=True):
    p = subprocess.run(args, capture_output=True, text=True)
    if check and p.returncode != 0:
        sys.exit("error: ImageMagick failed: " + (p.stderr.strip() or " ".join(args[:5])))
    return p.stdout.strip()


def idf(path, fmt):
    return run(["magick", "identify", "-format", fmt, path])


def mask_stats(path, tmp, invert=False, erode=6, threshold=14):
    """Build the same mask make-wallpaper.py builds, and measure it."""
    a, l, m = (os.path.join(tmp, n) for n in ("a.png", "l.png", "m.png"))
    run(["magick", path, "-alpha", "extract", a])
    lum = ["magick", path, "-alpha", "off", "-colorspace", "gray"]
    if invert:
        lum += ["-negate"]
    run(lum + [l])
    if erode:
        e = os.path.join(tmp, "ae.png")
        run(["magick", a, "-morphology", "Erode", "Disk:%d" % erode, e])
        a = e
    run(["magick", l, a, "-compose", "Multiply", "-composite",
         "-level", "%d%%,100%%" % threshold, m])
    mean = float(idf(m, "%[fx:mean]"))
    w, h = (int(v) for v in idf(m, "%w %h").split())
    band = max(2, min(w, h) // 25)
    geos = ["%dx%d+0+0" % (w, band), "%dx%d+0+%d" % (w, band, h - band),
            "%dx%d+0+0" % (band, h), "%dx%d+%d+0" % (band, h, w - band)]
    edge = max(float(run(["magick", m, "-crop", g, "+repage",
                          "-format", "%[fx:mean]", "info:"])) for g in geos)
    return mean, edge


def diagnose(path, tmp):
    """Return a list of (code, human explanation, auto-fixable?)."""
    problems = []
    fmt = idf(path, "%m").upper()
    w, h = (int(v) for v in idf(path, "%w %h").split())
    vector = fmt in ("SVG", "MVG")

    if not vector and min(w, h) < MIN_SIDE:
        problems.append(("too_small",
                         "%dx%d is below the %d px minimum. Upscaling invents "
                         "detail that was never there." % (w, h, MIN_SIDE), False))
    elif not vector and min(w, h) < GOOD_SIDE:
        problems.append(("smallish",
                         "%dx%d works but is under the recommended %d px."
                         % (w, h, GOOD_SIDE), False))

    ratio = max(w, h) / max(1, min(w, h))
    if ratio > MAX_RATIO:
        problems.append(("aspect",
                         "%.1f:1 is wider than the %.1f:1 limit; it needs "
                         "padding into a square." % (ratio, MAX_RATIO), True))

    mean, edge = mask_stats(path, tmp)
    inv_mean, inv_edge = mask_stats(path, tmp, invert=True)

    if edge > PLATE_EDGE and inv_edge <= PLATE_EDGE and inv_mean > FAINT_MEAN:
        problems.append(("inverted",
                         "The artwork is dark on a light background. Inverting "
                         "gives a clean mark.", True))
    elif edge > PLATE_EDGE:
        problems.append(("plate",
                         "The edges stay bright after masking (%.2f), so it has "
                         "a solid light background that would render as a gold "
                         "slab with the mark cut out." % edge, True))
    elif mean < FAINT_MEAN and inv_mean > FAINT_MEAN:
        problems.append(("dark_art",
                         "The artwork is dark on transparency, so brightness "
                         "masking drops it. It needs inverting.", True))
    elif mean < FAINT_MEAN:
        problems.append(("empty",
                         "Almost nothing survives masking either way (%.4f). "
                         "There may be no artwork here." % mean, False))
    return problems


def repair(path, problems, out, tmp):
    """Apply the mechanical fixes. Returns a list of what was done."""
    codes = {c for c, _, _ in problems}
    done = []
    cur = path

    if "plate" in codes:
        # Flood from all four corners so a solid ground becomes transparency.
        # Fuzz is generous: scans and JPEG artefacts leave a background that is
        # nearly, but not exactly, one colour.
        f = os.path.join(tmp, "nobg.png")
        w, h = (int(v) for v in idf(cur, "%w %h").split())
        cmd = ["magick", cur, "-alpha", "set", "-fuzz", "12%"]
        for x, y in ((0, 0), (w - 1, 0), (0, h - 1), (w - 1, h - 1)):
            cmd += ["-draw", "alpha %d,%d floodfill" % (x, y)]
        run(cmd + [f])
        cur = f
        done.append("removed the solid background by flood-filling from the corners")

    if "inverted" in codes or "dark_art" in codes:
        # Negate for real rather than just recommending --invert, so the file
        # this writes works with no extra flags — including from the bar
        # widget, which has nowhere to pass one. Only the luminance is ever
        # read, so a negative here is equivalent to inverting at build time.
        n = os.path.join(tmp, "neg.png")
        run(["magick", cur, "-alpha", "set", "-channel", "RGB", "-negate",
             "+channel", n])
        cur = n
        done.append("inverted the artwork (it was dark; brightness masking "
                    "keeps light pixels)")

    if "aspect" in codes:
        p = os.path.join(tmp, "square.png")
        w, h = (int(v) for v in idf(cur, "%w %h").split())
        side = max(w, h)
        run(["magick", cur, "-background", "none", "-gravity", "center",
             "-extent", "%dx%d" % (side, side), p])
        cur = p
        done.append("padded to a %dx%d square with transparency" % (side, side))

    if cur != path:
        run(["magick", cur, "-depth", "8", "-strip", out])
    return done


AGENT_BRIEF = """\
I want to use an image as the logo on my Bulwark Black desktop wallpaper, but
the theme's generator refuses it. Please prepare the image so it is accepted.

  image:     {path}
  size:      {size}
  format:    {fmt}

What the generator found wrong:
{problems}

How the generator treats a logo, so you know what "good" means: it builds a mask
from brightness multiplied by opacity, clamps near-black to fully transparent,
erodes the silhouette slightly to shed stray edge marks, and paints whatever
survives in a single accent colour. So it wants light artwork on a dark or
transparent ground, roughly square, at least 512px, with no solid background
plate. Transparency is not required — an opaque logo on black works fine.

What to do:

1. Try the mechanical repairs first:
       {tools}/logo-doctor.py "{path}" --fix
   It removes a solid background, pads a non-square mark, and tells you when
   --invert is needed. If that produces a file, test it and stop.

2. If the image is simply too small ({size}), the fix is not upscaling — that
   invents detail. Look for the original asset: a vector version (SVG/PDF/AI),
   a larger PNG on the site or press kit it came from, or the source file. A
   24x24 icon-set SVG is fine; the generator rasterises vectors at high density.

3. If the artwork is a photograph or has fine gradients, it will read as mud at
   5% opacity over near-black. Reduce it to a flat silhouette or line mark
   first — that is what this palette can actually render.

4. Verify by building a wallpaper and looking at it:
       {tools}/make-wallpaper.py --logo <prepared> --size 1280x720 \\
           --logo-size 420 -o /tmp/logo-test.png
   Open /tmp/logo-test.png. The mark should read cleanly in gold against the
   circuit pattern, with no rectangle around it and no missing interior.

5. When it looks right, install it:
       cp <prepared> ~/.config/omarchy/themes/bulwark-black/tools/assets/mylogo.png
   then pick it from the Comets widget in the bar, or run
       {tools}/set-logo.sh --rebuild

Full guidance, including every check and why it exists, is in the theme's
README and in `{tools}/make-wallpaper.py --help`.
"""


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("image")
    ap.add_argument("--fix", action="store_true", help="apply mechanical repairs")
    ap.add_argument("--brief", action="store_true",
                    help="print a brief for a coding agent")
    ap.add_argument("-o", "--out", help="where --fix writes (default: alongside)")
    a = ap.parse_args()

    if not shutil.which("magick"):
        sys.exit("error: ImageMagick 7 (`magick`) is required")
    if not os.path.isfile(a.image):
        sys.exit("error: no such file: " + a.image)

    import tempfile
    with tempfile.TemporaryDirectory() as tmp:
        problems = diagnose(a.image, tmp)
        blocking = [p for p in problems if p[0] != "smallish"]

        if not blocking:
            print("This logo should be accepted as-is.")
            for _, msg, _ in problems:
                print("  note: " + msg)
            return

        if a.brief:
            tools = os.path.dirname(os.path.abspath(__file__))
            print(AGENT_BRIEF.format(
                path=os.path.abspath(a.image),
                size=idf(a.image, "%wx%h"),
                fmt=idf(a.image, "%m"),
                problems="\n".join("  - " + m for _, m, _ in blocking),
                tools=tools))
            return

        print("Problems found:")
        for _, msg, fixable in blocking:
            print("  %s %s" % ("[fixable]" if fixable else "[manual] ", msg))

        if not a.fix:
            if all(f for _, _, f in blocking):
                print("\nAll of these are mechanical. Re-run with --fix.")
            else:
                print("\nSome need judgement. Re-run with --brief to get "
                      "instructions for your coding agent.")
            return

        out = a.out or (os.path.splitext(a.image)[0] + "-fixed.png")
        done = repair(a.image, blocking, out, tmp)
        if not done:
            print("\nNothing here can be repaired mechanically. "
                  "Use --brief to hand it to your agent.")
            return
        print("\nApplied:")
        for d in done:
            print("  - " + d)
        if os.path.isfile(out):
            left = diagnose(out, tmp)
            still = [p for p in left if p[0] not in ("smallish",)]
            print("\nWrote %s" % out)
            if still:
                print("Still outstanding:")
                for _, msg, _ in still:
                    print("  - " + msg)
            else:
                print("It passes every check now.")


if __name__ == "__main__":
    main()
