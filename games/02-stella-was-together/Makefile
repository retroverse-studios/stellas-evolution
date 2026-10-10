ROM := build/stella-was-together.bin

all: $(ROM) check

TEXTGEN := src/text.inc src/storytab.inc

$(ROM): src/main.asm src/vcs.h $(TEXTGEN)
	@mkdir -p build
	cd src && dasm main.asm -f3 -v0 -o../$(ROM) -l../build/main.lst -s../build/main.sym
	@ls -l $(ROM)
	@size=$$(wc -c < $(ROM)); \
	if [ $$size -ne 8192 ]; then \
		echo "ERROR: ROM is $$size bytes, expected exactly 8192 (F8 = 2 x 4K)"; \
		rm -f $(ROM); \
		exit 1; \
	fi
	@echo "ROM is exactly 8192 bytes — F8 layout intact"

$(TEXTGEN): tools/gentext.py
	python3 tools/gentext.py src

# Floor proofs: every real floor must be solvable (helpers allowed),
# free of Y-only false completions, and its TEACHING load-bearing --
# Floor 1's coop boost, Floor 2's Marcus-only door, Floor 3's
# unsolvable-without-wrap twist, Act 2's portal floors proven
# unsolvable with the doors shut (plus the portal art-vs-table audit),
# and Act 3's world-swap floors proven unsolvable with swaps off (the
# interleave floors in EACH world alone), with the swap-safety grammar
# audited (only one-way boxes may differ between worlds; no grounded
# rift state may swap into a wall). Build fails if any proof breaks.
check: $(ROM)
	python3 tools/check_levels.py $(ROM) build/main.sym src/main.asm

run: $(ROM)
	stella $(ROM)

clean:
	rm -rf build

.PHONY: all check run clean
