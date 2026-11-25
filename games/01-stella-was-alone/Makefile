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

# The tune (src/tune.inc). TUNE there picks what the normal ROM holds;
# `make tunes` additionally builds one ROM per draft beside it, and
# `make preview` renders each to WAV for listening without a console.
# TUNE 0 is the old drone, kept for A/B.
TUNES = 0 1 2 3

tunes: $(TUNES:%=build/stella-was-alone-tune%.bin)

build/stella-was-alone-tune%.bin: src/main.asm src/vcs.h src/text.inc src/tune.inc
	@mkdir -p build
	cd src && dasm main.asm -f3 -v0 -DTUNE=$* -o../$@ -l../build/tune$*.lst -s../build/tune$*.sym
	@size=$$(wc -c < $@); \
	if [ $$size -ne 4096 ]; then \
		echo "ERROR: tune $* ROM is $$size bytes, expected 4096"; \
		rm -f $@; \
		exit 1; \
	fi
	python3 tools/check_levels.py $@ build/tune$*.sym src/main.asm | tail -1

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

clean:
	rm -rf build

.PHONY: all check run clean tunes preview headless
