#!/usr/bin/env python3
"""Generate the branded background + caption overlays for the demo film.

Outputs into <outdir> (default demo/build):
  bg.png            1080x1920 dark gradient + warm glow + phone shadow + wordmark
  mask.png          rounded-rect alpha mask for the phone screen
  cap_00..NN.png    full-frame transparent caption overlays (one per beat)

The phone screen is placed fit-height with top/bottom bands for the wordmark and
lower-third captions. scripts/make_demo.sh consumes these.
"""
import os
import sys
import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

W, H = 1080, 1920
# Phone sits a touch smaller and higher so there's a real band beneath it for
# big, legible captions (the earlier tiny lower-third text was hard to read).
PW, PH = 690, 1500
PX, PY = (W - PW) // 2, 118                 # 195, 118  (bottom edge at 1618)
R = 44
ACCENT = (236, 96, 46)                      # deep-orange (app seed family)

OUT = sys.argv[1] if len(sys.argv) > 1 else "demo/build"
os.makedirs(OUT, exist_ok=True)

HELV = "/System/Library/Fonts/HelveticaNeue.ttc"
AVENIR = "/System/Library/Fonts/Avenir Next.ttc"


def font(path, size, index=0):
    return ImageFont.truetype(path, size, index=index)


def tracked(draw, xy, text, fnt, fill, spacing, anchor_center_x=None):
    """Draw text with manual letter-spacing. If anchor_center_x is set, center."""
    widths = [draw.textlength(c, font=fnt) for c in text]
    total = sum(widths) + spacing * (len(text) - 1)
    x = (anchor_center_x - total / 2) if anchor_center_x is not None else xy[0]
    y = xy[1]
    for c, w in zip(text, widths):
        draw.text((x, y), c, font=fnt, fill=fill)
        x += w + spacing
    return total


# ---------------------------------------------------------------- background
ys = np.linspace(0, 1, H)[:, None]
xs = np.linspace(0, 1, W)[None, :]
top = np.array([20, 16, 15]); bot = np.array([7, 6, 6])
grad = top[None, None, :] * (1 - ys[..., None]) + bot[None, None, :] * ys[..., None]
d = np.sqrt(((xs - 0.5) * 1.15) ** 2 + ((ys - 0.40) * 1.0) ** 2)
g = np.clip(1 - d / 0.72, 0, 1) ** 2.3
warm = np.array([236, 92, 44])
img = grad + g[..., None] * (warm - grad) * 0.5
bg = Image.fromarray(np.clip(img, 0, 255).astype(np.uint8), "RGB")

# soft drop shadow beneath the phone
sh = Image.new("L", (W, H), 0)
ImageDraw.Draw(sh).rounded_rectangle([PX, PY + 30, PX + PW, PY + PH + 30],
                                     radius=R + 8, fill=210)
sh = sh.filter(ImageFilter.GaussianBlur(52))
bg = Image.composite(Image.new("RGB", (W, H), (0, 0, 0)), bg, sh)

# hairline edge catch around the screen
ring = Image.new("L", (W, H), 0)
ImageDraw.Draw(ring).rounded_rectangle([PX - 1, PY - 1, PX + PW + 1, PY + PH + 1],
                                       radius=R + 1, outline=70, width=2)
bg = Image.composite(Image.new("RGB", (W, H), (255, 185, 150)), bg, ring)

# subtle grain baked into the background (cheap — avoids a per-frame blend in
# ffmpeg, which pushed the encode past 25 min). Screen-blend a low-amplitude
# monochrome noise field over the whole background.
rng0 = np.random.default_rng(11)
gnoise = rng0.normal(0, 7, (H, W, 1)).astype(np.float32)
bg = Image.fromarray(
    np.clip(np.asarray(bg, np.float32) + gnoise, 0, 255).astype(np.uint8), "RGB")

# baked top wordmark
d0 = ImageDraw.Draw(bg)
wm = font(AVENIR, 30, index=0)
tracked(d0, (0, 78), "N I C E N A G M A", wm, (208, 196, 190), 3, anchor_center_x=W / 2)
bg.save(os.path.join(OUT, "bg.png"))

# ---------------------------------------------------------------- phone mask
mask = Image.new("L", (PW, PH), 0)
ImageDraw.Draw(mask).rounded_rectangle([0, 0, PW - 1, PH - 1], radius=R, fill=255)
mask.save(os.path.join(OUT, "mask.png"))

# ---------------------------------------------------------------- grain
# Single static monochrome grain field; make_demo.sh screen-blends it at low
# opacity for filmic texture (cheap — unlike the per-frame noise filter).
rng = np.random.default_rng(7)
gr = rng.normal(128, 40, (H, W)).clip(0, 255).astype(np.uint8)
Image.fromarray(gr, "L").convert("RGB").save(os.path.join(OUT, "grain.png"))

# ---------------------------------------------------------------- captions
# Big, centred captions in the band below the phone (phone bottom = PY+PH = 1618).
# Bold weight + a soft dark halo so they read clearly over the dark background.
BAND_CY = 1770                               # vertical centre of the caption band
CAP_FONT = "/System/Library/Fonts/Supplemental/Arial Bold.ttf"
captions = [
    "Compose your own nagma",   # 0  sargam editor (shown, not typed)
    "Play your lehra",          # 1
    "Set the tempo",            # 2
    "Add the tanpura",          # 3
]

big = font(CAP_FONT, 60)
for i, text in enumerate(captions):
    im = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    dr = ImageDraw.Draw(im)
    bbox = dr.textbbox((0, 0), text, font=big)
    tw, th = bbox[2] - bbox[0], bbox[3] - bbox[1]
    tx = (W - tw) / 2 - bbox[0]
    ty = BAND_CY - th / 2 - bbox[1]
    # soft dark halo for legibility, then the light text
    dr.text((tx, ty), text, font=big, fill=(245, 240, 238, 255),
            stroke_width=2, stroke_fill=(10, 8, 8, 210))
    # short accent underline centred beneath the text
    uw = min(tw * 0.5, 220)
    uy = BAND_CY + th / 2 + 26
    dr.rounded_rectangle([(W - uw) / 2, uy, (W + uw) / 2, uy + 5], radius=2,
                         fill=ACCENT + (255,))
    im.save(os.path.join(OUT, f"cap_{i:02d}.png"))

print(f"wrote bg.png, mask.png, {len(captions)} captions to {OUT}/  "
      f"(PX,PY,PW,PH={PX},{PY},{PW},{PH})")
