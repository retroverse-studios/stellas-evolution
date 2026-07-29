ROM := build/stella-was-alone.bin

all: $(ROM) check

$(ROM): src/main.asm src/vcs.h src/text.inc
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

clean:
	rm -rf build

.PHONY: all check run clean
