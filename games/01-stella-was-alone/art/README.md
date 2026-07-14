# Box Art — Stella Was Alone

- `box-front.png` — composed box front (1500×2000): title bands + rainbow rules
  over candidate A, in the style of the classic numbered Atari boxes.
- `boxart-a.png` — raw art, candidate A (the monolith). **Used on the box.**
- `boxart-b.png` — raw art, candidate B (arcade cabinet on a cliff). Unused;
  could suit the manual back cover or the series landing page.
- `compose_box.py` — rebuilds `box-front.png` from a raw art PNG
  (`python3 compose_box.py boxart-a.png box-front.png`). Uses macOS
  HelveticaNeue.ttc (Condensed Bold) via Pillow.

## Regenerating the raw art

Generated locally with [limn](https://github.com/) → SwarmUI → SDXL
(`juggernautXL_v9`), 896×1152. SDXL can't spell, so all typography is
composited afterward by `compose_box.py` — keep prompts text-free.

Candidate A (seed 41):

    limn -m juggernautXL_v9 -s 896x1152 --seed 41 \
      --negative "text, letters, words, typography, logo, watermark, signature, human faces, photo" \
      -o boxart-a.png \
      "1982 vintage video game box art, dramatic airbrushed sci-fi illustration: a tall glowing red rectangular monolith towering protectively beside a small wide flat green rectangular slab, standing together on a dark geometric platform world of black angular terrain, deep indigo starfield sky with a rainbow beam of light on the horizon, dramatic rim lighting, retro 1980s Atari-style painted illustration, gouache airbrush painting, no text"

Candidate B (seed 7):

    limn -m juggernautXL_v9 -s 896x1152 --seed 7 \
      --negative "text, letters, words, typography, logo, watermark, signature, human faces, photo" \
      -o boxart-b.png \
      "vintage 1980s arcade cabinet art painting, two heroic geometric beings — a tall luminous crimson rectangle and a squat emerald green rectangle — leaping across a chasm between black platforms inside a vast dark computer world, scanline stars, glowing rainbow horizon beam, dramatic perspective from below, airbrushed retro sci-fi illustration, epic and lonely mood, no text"
