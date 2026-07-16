ROM := build/stella-was-together.bin

all: $(ROM) check

$(ROM): src/main.asm src/vcs.h src/text.inc
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

# Decision-gate proof: every toggle floor must be solvable WITH the
# world-switch and unsolvable WITHOUT it. Build fails if either half
# of any floor's proof fails.
src/text.inc: tools/gentext.py
	python3 tools/gentext.py src/text.inc

check: $(ROM)
	python3 tools/check_levels.py $(ROM) build/main.sym src/main.asm

run: $(ROM)
	stella $(ROM)

clean:
	rm -rf build

.PHONY: all check run clean
