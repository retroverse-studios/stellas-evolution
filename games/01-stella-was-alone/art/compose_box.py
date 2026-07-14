#!/usr/bin/env python3
"""Compose an Atari-2600-style box front: title bands + rainbow rules around SDXL art."""
import sys
from PIL import Image, ImageDraw, ImageFont

ART_IN = sys.argv[1]
OUT = sys.argv[2]

W, H = 1500, 2000
INK = (18, 16, 14)
PAPER = (242, 238, 228)
RED = (200, 52, 31)
AMBER = (232, 160, 32)
GREEN = (46, 125, 70)

TTC = "/System/Library/Fonts/HelveticaNeue.ttc"


def find_face(*want):
    """Return (path, index) whose style name contains all wanted words."""
    for i in range(24):
        try:
            f = ImageFont.truetype(TTC, 40, index=i)
        except OSError:
            break
        fam, style = f.getname()
        if all(w.lower() in style.lower() for w in want):
            return i
    return None


idx_cbold = find_face("Condensed", "Bold")
idx_bold = find_face("Bold") if idx_cbold is None else idx_cbold
idx_med = find_face("Medium") or 0


def font(size, index):
    return ImageFont.truetype(TTC, size, index=index)


img = Image.new("RGB", (W, H), INK)
d = ImageDraw.Draw(img)

# ---- top band ----------------------------------------------------------
pad = 70
y = 60
brand_f = font(34, idx_med)
d.text((pad, y), "RETROVERSE STUDIOS", font=brand_f, fill=PAPER)
d.text((pad, y + 46), "GAME PROGRAM™ INSTRUCTIONS INSIDE", font=brand_f, fill=(150, 143, 130))
# numbered badge, top right (Atari silver-box style)
bs = 96
d.rectangle([W - pad - bs, y - 6, W - pad, y - 6 + bs], outline=PAPER, width=5)
one_f = font(64, idx_bold)
ob = d.textbbox((0, 0), "1", font=one_f)
d.text((W - pad - bs / 2 - (ob[2] - ob[0]) / 2, y - 6 + bs / 2 - (ob[3] - ob[1]) / 2 - ob[1]),
       "1", font=one_f, fill=PAPER)

# ---- title -------------------------------------------------------------
ty = 210
title_f = font(150, idx_cbold if idx_cbold is not None else idx_bold)
d.text((pad, ty), "STELLA", font=title_f, fill=PAPER)
d.text((pad, ty + 150), "WAS ALONE", font=title_f, fill=PAPER)

# ---- rainbow rules (the beam) ------------------------------------------
ry = ty + 340
for i, c in enumerate((RED, AMBER, GREEN)):
    d.rectangle([pad, ry + i * 26, W - pad, ry + i * 26 + 14], fill=c)

# ---- artwork window ----------------------------------------------------
art_top = ry + 110
art_bottom = H - 190
art = Image.open(ART_IN).convert("RGB")
win_w, win_h = W - 2 * pad, art_bottom - art_top
scale = max(win_w / art.width, win_h / art.height)
art = art.resize((round(art.width * scale), round(art.height * scale)), Image.LANCZOS)
cx, cy = art.width // 2, min(art.height - win_h // 2, int(art.height * 0.42))
art = art.crop((cx - win_w // 2, cy - win_h // 2, cx - win_w // 2 + win_w, cy - win_h // 2 + win_h))
img.paste(art, (pad, art_top))
d.rectangle([pad, art_top, W - pad, art_bottom], outline=PAPER, width=4)

# ---- bottom band -------------------------------------------------------
foot_f = font(33, idx_med)
line1 = "VIDEO GAME CARTRIDGE"
line2 = "FOR USE WITH THE ATARI® 2600™ VIDEO COMPUTER SYSTEM™"
b1 = d.textbbox((0, 0), line1, font=foot_f)
b2 = d.textbbox((0, 0), line2, font=foot_f)
d.text(((W - b1[2]) / 2, H - 150), line1, font=foot_f, fill=PAPER)
d.text(((W - b2[2]) / 2, H - 100), line2, font=foot_f, fill=(150, 143, 130))

img.save(OUT)
print("faces: cbold idx", idx_cbold, "| bold idx", idx_bold, "| med idx", idx_med)
print("wrote", OUT, img.size)
