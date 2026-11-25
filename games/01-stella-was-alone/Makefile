ROM := build/stella-was-alone.bin

all: $(ROM) check

$(ROM): src/main.asm src/vcs.h src/text.inc src/tune.inc
	@mkdir -p build
	cd src && dasm main.asm -f3 -v0 -o../$(ROM) -l../build/main.lst -s../build/main.sym
	@ls -l $(ROM)
	@size=$$(wc -c < $(ROM)); \
	if [ $$size -ne 4096 ]; then \
		echo "ERROR: ROM is $$size bytes, expected exactly 4096 (4K, no bankswitching)"; \
		rm -f $(ROM); \
		exit 1; \
	fi
	@echo "ROM is exactly 4096 bytes"

src/text.inc: tools/gentext.py
	python3 tools/gentext.py src/text.inc

# Level proofs: every level and both goal variants must be provably
# completable under PLACE AND HOLD (decision #26) -- a reachable
# STANDING state on each character's own goal, at least one character
# solo. Build fails if any proof breaks. This is a separate target (not
# a step inside the ROM recipe) so the proof re-runs on every `make`,
# not only when the ROM happens to be out of date.
check: $(ROM)
	python3 tools/check_levels.py $(ROM) build/main.sym src/main.asm

run: $(ROM)
	stella $(ROM)

# The tune (src/tune.inc), rendered to WAV for listening without a console:
# at tempo, and as it plays while the clock is low.
preview:
	@mkdir -p build/tune-previews
	python3 tools/tune_preview.py build/tune-previews --fast

# Run the ROM itself (tools/headless.py): a 6502 with the timer, the
# input and the audio registers, driven a frame at a time through every
# screen -- title, story, play, the tune, the completion beat, two
# shapes, the ending, the upside-down replay, the epilogue, endless, a
# cold boot with garbage in RAM. What check_levels.py is to the levels,
# this is to everything else that happens in vertical blank.
headless: $(ROM)
	python3 tools/headless.py $(ROM) build/main.sym

# The manual's pictures (manual/pictures), drawn from the cartridge's own
# bytes by tools/manual_pictures.py: the ten rooms with both shapes and
# both placements of the lights, the title, the cast, the closing screen.
# Needs Pillow. Not part of `make`: a picture is documentation, and it
# only needs drawing again when a room or a screen changes.
pictures: $(ROM)
	python3 tools/manual_pictures.py $(ROM) build/main.sym src/main.asm manual/pictures

clean:
	rm -rf build

.PHONY: all check run clean preview headless pictures
