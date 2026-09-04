# Preparing a Logo for the Bulwark Black Wallpaper

The theme's wallpaper generator refuses artwork it cannot render well, rather
than producing something ugly. Your job is to turn the image the user actually
wants into one it accepts, without silently degrading it.

## How the generator sees a logo

This is the whole of it, and every rule below follows from it:

1. Build a mask = **brightness × opacity**.
2. Clamp anything under ~14% brightness to fully transparent.
3. Erode the silhouette ~6px, to shed stray marks along the edge.
4. Paint whatever survives in one flat accent colour.

So it wants a **light mark on a dark or transparent ground**. Transparency is
not required — an opaque JPEG of a white logo on black works perfectly. What
fails is a *light* background, because bright pixels survive the mask and you
get a coloured slab with the logo punched out of it.

Colour in the source is discarded. Only luminance survives.

## Start with the doctor

```bash
tools/logo-doctor.py <image>          # diagnose
tools/logo-doctor.py <image> --fix    # repair, writes <image>-fixed.png
```

It repairs the three mechanical cases: a solid background (flood-filled from the
corners), dark artwork (inverted), and a too-wide mark (padded to a square). If
`--fix` writes a file and reports that it passes, test it and you are done.

Do not stop at the doctor when it says a problem needs judgement.

## What the doctor cannot do

**Too small.** Upscaling invents detail that was never in the file, and it looks
like it. Go and find the real asset instead:

- a vector original — SVG, PDF, AI, EPS. The generator rasterises vectors at
  high density, so even a 24×24 viewBox is fine.
- the same mark at higher resolution on the site it came from, a press kit, a
  brand page, or the project's repository.
- a favicon is a last resort and usually looks like one.

Ask the user where the logo came from before searching; they usually know, and
it saves guessing.

**Photographs and gradients.** These turn to mud at low opacity over near-black,
because the mask throws away every hue and keeps only lightness. A photo needs
reducing to a flat silhouette or line mark first. That is a design decision, not
a mechanical one — show the user what you propose before committing to it.

**Fine detail.** Thin strokes and small text vanish once the mark is drawn at a
few hundred pixels on a dark field. Simplify, or accept that it will not read.

## Verify by looking

Never hand back a logo you have not seen rendered:

```bash
tools/make-wallpaper.py --logo <prepared> --size 1280x720 --logo-size 420 \
    -o /tmp/logo-test.png
```

Open the result. Check for the things that pass validation but still look wrong:

- a faint rectangle around the mark — background not fully removed
- a hollow shape — the interior was dark and got masked away
- speckle along the edge — raise `--erode`
- a shape you cannot identify at a glance — too much detail for this treatment

## Installing it

```bash
cp <prepared> ~/.config/omarchy/themes/bulwark-black/tools/assets/<name>.png
```

Then either pick it from the Comets widget in the bar, or:

```bash
tools/set-logo.sh --rebuild
```

The wallpaper is written to `~/.config/omarchy/backgrounds/bulwark-black/`, so
the theme's own branded wallpaper is never overwritten.
`tools/set-logo.sh --defaults` puts everything back.

## Be straight about the result

If the logo cannot be made to work well — a photographic mark, a wordmark that
is mostly small text — say so plainly and explain why, rather than shipping a
gold blob. The user can choose a different asset, simplify the mark, or keep the
one the theme ships. All three are better outcomes than a bad wallpaper they
have to look at every day.
